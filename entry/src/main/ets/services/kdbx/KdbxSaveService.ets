import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { ByteUtils, Kdbx, KdbxCustomIcon, KdbxUuid } from 'kdbxweb';
import { Constants } from '../../common/constants/Constants';
import { CacheConstants } from '../../storage';
import { CommonUtils, KdbxUtils, ResourceManager } from '../../common/utils';
import { FileService } from '../../services/FileService';
import { LoadingDialog } from '../../components/loading/LoadingDialogUtils';
import { SaveDatabaseCallback } from '../../workers/callback/SaveDatabaseCallback';
import { ToastSaveDatabaseCallback } from '../../workers/callback/ToastSaveDatabaseCallback';
import { DatabaseSave } from '../../workers/DatabaseSave';
import { ConflictStrategy, SaveDatabaseMessage } from '../../workers/DatabaseSaveWorkerParam';
import { DatabaseWorkerFactory } from '../../workers/DatabaseWorkerFactory';
import { LoadDatabase } from '../../workers/DatabaseLoadWorkerParam';
import KdbxLoadService from './KdbxLoadService';
import { ConflictMessage, LoadMessage, MessageType, SuccessMessage, WorkerMessage } from '../../workers/WorkerParam';
import { EventBus } from '../EventBus';

const DOMAIN = 0x0000;
const TAG = 'KdbxSaveService';

/**
 * 保存数据库服务类
 * 保存冲突时弹框让用户选择处理策略：合并（保留双方修改）/ 覆盖（丢弃远端修改）/ 重载（丢弃本地修改）
 */
export default class KdbxSaveService {
  private static databaseWorker: worker.ThreadWorker | null = null;

  /**
   * 保存数据库
   * @param callback 回调
   * @param conflictStrategy 冲突处理策略，默认 AUTO（检测到冲突时弹框询问用户）
   * @returns 结果信息
   */
  public static saveDatabase(callback?: SaveDatabaseCallback, conflictStrategy?: string): void {
    const strategy: string = conflictStrategy ?? ConflictStrategy.AUTO;
    // 重载策略由服务层拦截：放弃本地修改，直接从远端重新加载数据库
    if (strategy === ConflictStrategy.RELOAD) {
      KdbxSaveService.reloadFromRemote(callback);
      return;
    }
    // 启用保存线程，保存数据库
    const dbFileParam = FileService.getDbFileParam();
    if (!dbFileParam.database) {
      hilog.error(DOMAIN, TAG, 'Database is null');
      if (callback && callback.onError) {
        callback.onError(ResourceManager.getString($r('app.string.invalid_database')));
      }
      return;
    }

    const saveDatabaseReq = new SaveDatabaseMessage(dbFileParam.database, dbFileParam, strategy);
    const callbackWarp = KdbxSaveService.callbackWarp(callback);
    if (Constants.ASYNC_SAVE_DATABASE) {
      KdbxSaveService.saveDatabaseAsync(saveDatabaseReq, callbackWarp);
    } else {
      new DatabaseSave(callbackWarp).handleSaveDatabase(saveDatabaseReq);
    }
  }

  /**
   * 保存数据库（UI 便捷入口）：清空自定义图标显示缓存，未指定回调时以 Toast 提示结果
   * @param callback 回调
   * @param conflictStrategy 冲突处理策略，默认 AUTO（冲突时弹框询问用户）
   */
  public static saveDatabaseFromUi(callback?: SaveDatabaseCallback, conflictStrategy?: string): void {
    KdbxUtils.clearCustomIconMap();
    KdbxSaveService.saveDatabase(callback ?? new ToastSaveDatabaseCallback(), conflictStrategy);
  }

  /**
   * 添加自定义图标到数据库并保存
   * @param database 数据库实例
   * @param base64Images base64编码的图像数据（格式：data:image/png;base64,...)
   * @param callback 保存回调
   */
  public static async addCustomIcon(database: Kdbx, base64Images: string[], callback?: SaveDatabaseCallback): Promise<void> {
    try {
      if (!database || !base64Images || base64Images.length === 0) {
        callback?.onError?.('Invalid database or base64 image');
        return;
      }
      for (const base64Image of base64Images) {
        // 从base64字符串中提取实际的base64数据部分
        const base64Data = base64Image.split(',')[1];
        if (!base64Data) {
          callback?.onError?.('Invalid base64 image');
          continue;
        }
        // 将base64转换为ArrayBuffer
        const iconData = ByteUtils.base64ToBytes(base64Data);
        // 添加自定义图标到数据库
        database.meta.customIcons.set(KdbxUuid.random().id, { data: iconData } as KdbxCustomIcon);
      }
      // 清除缓存，确保新图标可见
      KdbxUtils.clearCustomIconMap();
      // 保存数据库
      KdbxSaveService.saveDatabase(callback ?? new ToastSaveDatabaseCallback());
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Add custom icon error: %{public}s', error);
      callback?.onError?.(error.message);
    }
  }

  /**
   * 处理保存冲突：弹框让用户选择处理策略
   * @param message 冲突信息
   * @param callback 原始回调（选择策略后继续保存时复用）
   */
  private static handleConflict(message: ConflictMessage, callback?: SaveDatabaseCallback): void {
    // 关闭保存过程的加载弹框，避免与冲突弹框叠加
    LoadingDialog.hideLoading();
    hilog.info(DOMAIN, TAG, 'Save conflict detected, remoteModifiedTime: %{public}d', message.remoteModifiedTime);
    const dialogOptions: promptAction.ShowDialogOptions = {
      title: $r('app.string.save_conflict_title'),
      message: $r('app.string.save_conflict_message'),
      buttons: [
        { text: $r('app.string.save_conflict_merge'), color: '#007dfe' },
        { text: $r('app.string.save_conflict_overwrite'), color: '#007dfe' },
        { text: $r('app.string.save_conflict_reload'), color: '#e84026' }
      ]
    };
    CommonUtils.showDialog(dialogOptions).then((response: ShowDialogSuccessResponse) => {
      if (response.index === 0) {
        // 合并：保留双方修改
        KdbxSaveService.saveDatabase(callback, ConflictStrategy.MERGE);
      } else if (response.index === 1) {
        // 覆盖：丢弃远端修改
        KdbxSaveService.saveDatabase(callback, ConflictStrategy.OVERWRITE);
      } else if (response.index === 2) {
        // 重载：丢弃本地修改，以远端为准
        KdbxSaveService.saveDatabase(callback, ConflictStrategy.RELOAD);
      }
    }).catch((error: Error) => {
      // 用户关闭弹框：放弃本次保存，本地修改保留在内存中
      hilog.warn(DOMAIN, TAG, 'Conflict dialog dismissed: %{public}s', error?.message);
      // 刷新列表以反映内存中保留的修改（新增条目在保存前已写入内存库，
      // 不刷新会导致列表与内存状态不一致，用户退回列表后看不到刚添加的条目）
      EventBus.emit<void>(EventBus.DATABASE_UPDATE);
    });
  }

  /**
   * 从远端重新加载数据库（丢弃本地未保存的修改）
   * @param callback 原始回调，重载完成后回调 onSuccess/onError，保证调用方流程不挂起
   */
  private static reloadFromRemote(callback?: SaveDatabaseCallback): void {
    const dbFileParam = FileService.getDbFileParam();
    if (!dbFileParam.database) {
      hilog.error(DOMAIN, TAG, 'Database is null');
      if (callback && callback.onError) {
        callback.onError(ResourceManager.getString($r('app.string.invalid_database')));
      }
      return;
    }
    // 强制从远端刷新，忽略仅使用本地缓存的设置
    CacheConstants.setForceRefresh(true);
    const loadParam = LoadDatabase.byDbFileParam(dbFileParam);
    KdbxLoadService.loadDatabase(loadParam, {
      onSuccessMessage: (message: SuccessMessage) => {
        KdbxUtils.arrayBufferToKdbx(message.data, loadParam).then((database: Kdbx) => {
          FileService.resetDbFileParam(database, message.modifiedTime, message.version ?? null,
            message.contentHash ?? null);
          EventBus.emit<void>(EventBus.DATABASE_RELOAD);
          if (callback && callback.onSuccess) {
            callback.onSuccess(message);
          }
        }).catch((error: Error) => {
          hilog.error(DOMAIN, TAG, 'Reload database error: %{public}s', error?.message);
          if (callback && callback.onError) {
            callback.onError(error.message);
          } else {
            CommonUtils.showToast(error.message);
          }
        });
      },
      onErrorMessage: (message: LoadMessage) => {
        const errorMessage: string = ResourceManager.getMessage(message.message);
        if (callback && callback.onError) {
          callback.onError(errorMessage);
        } else {
          CommonUtils.showToast(errorMessage);
        }
      }
    });
  }

  /**
   * 异步方式 - 保存数据库
   * @param req
   * @param callback
   */
  static async saveDatabaseAsync(req: SaveDatabaseMessage, callback?: SaveDatabaseCallback) {
    // 释放之前的异步线程
    if (KdbxSaveService.databaseWorker) {
      try {
        KdbxSaveService.databaseWorker.terminate();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Save database worker terminate error: %{public}s', error.message);
      }
      KdbxSaveService.databaseWorker = null;
      hilog.info(DOMAIN, TAG, 'Database save worker terminated');
    }

    req.data = await KdbxUtils.kdbxToArrayBuffer(req.data);
    KdbxSaveService.saveDatabaseWorker(req, callback);
  }

  /**
   * 保存数据库线程
   * @param savedDb
   * @param dbFileParam
   */
  private static saveDatabaseWorker(req: SaveDatabaseMessage, callback?: SaveDatabaseCallback): void {
    KdbxSaveService.databaseWorker = DatabaseWorkerFactory.createSaveWorker();
    try {
      KdbxSaveService.databaseWorker.postMessage(req, [req.data as ArrayBuffer]);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Save database worker error: %{public}s', err.message);
      if (callback && callback.onError) {
        callback.onError(err.message);
      } else {
        CommonUtils.showToast(err.message);
      }
      return;
    }
    // work 线程中执行
    KdbxSaveService.databaseWorker.onmessage = (e: MessageEvents) => {
      let data = e.data as WorkerMessage;
      switch (data.type) {
        // 提示消息
        case MessageType.MESSAGE:
          KdbxSaveService.onMessage(data as LoadMessage, callback);
          return;
        case MessageType.SUCCESS:
          KdbxSaveService.onSuccess(data as SuccessMessage, callback);
          return;
        case MessageType.CONFLICT:
          KdbxSaveService.onConflict(data as ConflictMessage, callback);
          return;
        case MessageType.ERROR:
          KdbxSaveService.onError(data as LoadMessage, callback);
          return;
      }
    }

    // 注册onerror回调，当Worker线程发生异常时被调用，在宿主线程执行
    KdbxSaveService.databaseWorker.onAllErrors = (err: ErrorEvent) => {
      // 忽略NativeCustomSpan和ViewV2错误
      if (err.message.indexOf('NativeCustomSpan') != -1 || err.message.indexOf('ViewV2') != -1) {
        hilog.debug(DOMAIN, TAG, 'Load database error: %{public}s', err.message);
        return;
      }

      // 打印错误日志
      hilog.error(DOMAIN, TAG, 'Save database error: %{public}s', err.message);
      if (callback && callback.onError) {
        callback.onError(err.message);
      }
    }
  }

  static callbackWarp(callback?: SaveDatabaseCallback): SaveDatabaseCallback {
    return {
      onSuccess: (message: SuccessMessage) => {
        KdbxSaveService.handleSuccess(message, callback);
      },
      onError: callback?.onError,
      onMessage: callback?.onMessage,
      onConflict: (message: ConflictMessage) => {
        KdbxSaveService.handleConflict(message, callback);
      }
    }
  }

  static handleSuccess(message: SuccessMessage, callback?: SaveDatabaseCallback) {
    // 数据库保存成功：更新版本基线（modifiedTime + version + contentHash），供下次保存做冲突检测
    const dbFileParam = FileService.getDbFileParam();
    dbFileParam.modifiedTime = message.modifiedTime;
    dbFileParam.version = message.version ?? null;
    dbFileParam.contentHash = message.contentHash ?? null;
    if (message.isMerge) {
      KdbxUtils.arrayBufferToKdbx(message.data, FileService.getDbFileParam()).then(kdbx => {
        FileService.getDbFileParam().database = kdbx;
        EventBus.emit<void>(EventBus.DATABASE_RELOAD);
        if (callback && callback.onSuccess) {
          callback.onSuccess(message);
        }
      }).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Save database error: %{public}s, %{public}s', error?.message, error?.stack);
        if (callback && callback.onError) {
          callback.onError(error.message);
        } else {
          CommonUtils.showToast(error.message);
        }
      });
    } else {
      EventBus.emit<void>(EventBus.DATABASE_UPDATE);
      if (callback && callback.onSuccess) {
        callback.onSuccess(message);
      }
    }
  }

  static onSuccess(message: SuccessMessage, callback?: SaveDatabaseCallback) {
    if (!callback) {
      return;
    }
    if (callback.onSuccess) {
      callback.onSuccess(message);
    }
  }

  static onConflict(message: ConflictMessage, callback?: SaveDatabaseCallback) {
    if (!callback) {
      return;
    }
    if (callback.onConflict) {
      callback.onConflict(message);
    }
  }

  static onMessage(data: LoadMessage, callback?: SaveDatabaseCallback) {
    if (!callback) {
      return;
    }
    if (callback.onMessage) {
      callback.onMessage(ResourceManager.getMessage(data.message));
    }
  }

  static onError(data: LoadMessage, callback?: SaveDatabaseCallback) {
    if (!callback) {
      return;
    }
    if (callback.onError) {
      callback.onError(ResourceManager.getMessage(data.message));
    }
  }
}
