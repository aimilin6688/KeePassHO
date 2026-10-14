import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { ByteUtils, Kdbx, KdbxCustomIcon, KdbxUuid } from 'kdbxweb';
import { Constants } from '../../common/constants/Constants';
import { CacheConstants } from '../../storage';
import { CommonUtils, KdbxUtils, ResourceManager } from '../../common/utils';
import { FileService } from '../../services/FileService';
import { LoadingDialog, LoadingState } from '../../components/loading/LoadingDialogUtils';
import { SaveDatabaseCallback } from '../../workers/callback/SaveDatabaseCallback';
import { ToastSaveDatabaseCallback } from '../../workers/callback/ToastSaveDatabaseCallback';
import { DatabaseSave } from '../../workers/DatabaseSave';
import { ConflictStrategy, SaveDatabaseMessage } from '../../workers/DatabaseSaveWorkerParam';
import { DatabaseWorkerFactory } from '../../workers/DatabaseWorkerFactory';
import { LoadDatabase } from '../../workers/DatabaseLoadWorkerParam';
import KdbxLoadService from './KdbxLoadService';
import { LoadDispatchCache } from './LoadDispatchCache';
import { RecentFile } from '../TypeDefined';
import { AuthType } from '../TypeDefined';
import { RecentFilesService } from '../RecentFilesService';
import { ConflictMessage, LoadMessage, MessageType, ProgressMessage, SuccessMessage, WorkerMessage } from '../../workers/WorkerParam';
import { EventBus } from '../EventBus';

const DOMAIN = 0x0000;
const TAG = 'KdbxSaveService';

/**
 * 待执行保存请求槽位元素：保存回调 + 冲突处理策略
 */
class PendingSave {
  callback?: SaveDatabaseCallback;
  conflictStrategy: string;

  constructor(callback: SaveDatabaseCallback | undefined, conflictStrategy: string) {
    this.callback = callback;
    this.conflictStrategy = conflictStrategy;
  }
}

/**
 * 保存数据库服务类
 * 保存冲突时弹框让用户选择处理策略：合并（保留双方修改）/ 覆盖（丢弃远端修改）/ 重载（丢弃本地修改）
 */
export default class KdbxSaveService {
  private static databaseWorker: worker.ThreadWorker | null = null;
  /**
   * 保存进行中标志：true 时拒绝新请求入队，仅更新 pendingSave 槽位（合并）
   */
  private static saving: boolean = false;
  /**
   * 待执行保存槽位（最多 1 个）：保存进行中到达的新请求替换此槽位，
   * 中间状态无需落盘——锁内取最新模型构造请求，最终状态等价
   */
  private static pendingSave: PendingSave | null = null;

  /**
   * 保存数据库
   * 保存进行中时仅保留最新请求（静默整体替换待执行槽位），中间请求直接丢弃、不通知旧回调；
   * 最终状态由槽位取出时取最新模型落盘保证
   * @param callback 回调
   * @param conflictStrategy 冲突处理策略，默认 AUTO（检测到冲突时弹框询问用户）
   */
  public static saveDatabase(callback?: SaveDatabaseCallback, conflictStrategy?: string): void {
    const strategy: string = conflictStrategy ?? ConflictStrategy.AUTO;
    // 重载策略由服务层拦截：放弃本地修改，直接从远端重新加载数据库
    if (strategy === ConflictStrategy.RELOAD) {
      KdbxSaveService.reloadFromRemote(callback);
      return;
    }
    const dbFileParam = FileService.getDbFileParam();
    if (!dbFileParam.database) {
      hilog.error(DOMAIN, TAG, 'Database is null');
      if (callback && callback.onError) {
        callback.onError(ResourceManager.getString($r('app.string.invalid_database')));
      }
      return;
    }

    // 挑战-应答（XC）库保存拦截：kdbxweb 保存时重新生成 KDF seed，解锁时的 YubiKey 应答
    // 仅对当前 seed 有效，直接保存将产生无法再次解锁的文件（数据损坏）；
    // 「保存前重贴卡」两阶段保存支持前明确阻断（RELOAD 远端重载不受影响：seed 未变、应答仍有效）
    if (dbFileParam.authType && AuthType.useChallengeResponseXc(dbFileParam.authType)) {
      hilog.warn(DOMAIN, TAG, 'Save blocked: challenge-response (XC) database save requires re-challenge, not supported yet');
      if (callback && callback.onError) {
        callback.onError(ResourceManager.getString($r('app.string.error_challenge_response_save_unsupported')));
      }
      return;
    }

    // 保存进行中：静默合并——新请求整体替换待执行槽位（回调与策略），旧请求直接丢弃，
    // 不通知旧回调；最终状态由后继保存取最新模型落盘保证
    if (KdbxSaveService.saving) {
      KdbxSaveService.pendingSave = new PendingSave(callback, strategy);
      hilog.info(DOMAIN, TAG, 'Save in progress, coalesced pending save (replaced)');
      return;
    }

    // 空闲：立即执行保存
    KdbxSaveService.executeSave(callback, strategy);
  }

  /**
   * 执行一次保存（从空闲态调用，或从 pendingSave 槽位取出后调用）
   * 保存终态后检查 pendingSave 槽位，有则继续执行下一轮
   */
  private static executeSave(callback: SaveDatabaseCallback | undefined, conflictStrategy: string): void {
    KdbxSaveService.saving = true;
    const currentParam = FileService.getDbFileParam();
    if (!currentParam.database) {
      hilog.error(DOMAIN, TAG, 'Database is null in executeSave');
      if (callback && callback.onError) {
        callback.onError(ResourceManager.getString($r('app.string.invalid_database')));
      }
      KdbxSaveService.onSaveDone();
      return;
    }
    const saveDatabaseReq = new SaveDatabaseMessage(currentParam.database, currentParam, conflictStrategy);
    // 一次性释放守卫：release 有多条触发路径（callbackWarp 终态 / 异常 catch 兜底 / Worker
    // onexit 等），重复触发会把进行中保存的 saving 提前置 false，导致下一请求并发保存，
    // 必须保证每轮保存仅推进一次 onSaveDone
    let released = false;
    const release = (): void => {
      if (released) {
        return;
      }
      released = true;
      KdbxSaveService.onSaveDone();
    };
    const callbackWarp = KdbxSaveService.callbackWarp(callback, release);
    if (Constants.ASYNC_SAVE_DATABASE) {
      KdbxSaveService.saveDatabaseAsync(saveDatabaseReq, callbackWarp, release);
    } else {
      new DatabaseSave(callbackWarp).handleSaveDatabase(saveDatabaseReq)
        .catch((error: Error) => {
          hilog.error(DOMAIN, TAG, 'Save database rejected: %{public}s', error?.message);
          callbackWarp.onError?.(error?.message ?? 'save failed');
        });
    }
  }

  /**
   * 保存终态处理：检查 pendingSave 槽位，有则继续执行下一轮保存；无则回到空闲态
   */
  private static onSaveDone(): void {
    const pending: PendingSave | null = KdbxSaveService.pendingSave;
    KdbxSaveService.pendingSave = null;
    if (pending !== null) {
      hilog.info(DOMAIN, TAG, 'Pending save found, executing next round');
      KdbxSaveService.executeSave(pending.callback, pending.conflictStrategy);
    } else {
      KdbxSaveService.saving = false;
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
    // 按接口约定先通知调用方冲突已发生（等待上层决定处理策略），再走 AUTO 弹框流程
    callback?.onConflict?.(message);
    // 关闭保存过程的加载弹框与线性进度弹框，避免与冲突弹框叠加
    LoadingDialog.hideLoading();
    LoadingDialog.hide(LoadingState.LINEAR_PROGRESS).catch(() => {
    });
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
      // 被放弃的保存若携带改密字段，同样必须清理，防止残留被后续保存静默应用（F1 回归）
      FileService.clearPendingCredentialChanges();
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
    // F4：RELOAD 策略语义 = 放弃本地修改（含本次改密意图）。
    // 若本次保存携带改密字段，重载成功后不得回调 onSuccess（改密页会误报"改密成功"并跳转登录页，
    // 但远端密码并未变更，用户按新密码登录将失败），应回调 onError 提示改密已被放弃。
    const hadPendingCredentialChanges = FileService.hasPendingCredentialChanges();
    // F1 回归：清理待应用凭证字段，防止残留的 newPassword 等被后续普通保存静默应用
    FileService.clearPendingCredentialChanges();
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
        KdbxUtils.successMessageToKdbx(message, loadParam).then((database: Kdbx) => {
          FileService.resetDbFileParam(database, message.modifiedTime, message.version ?? null,
            message.contentHash ?? null);
          EventBus.emit<void>(EventBus.DATABASE_RELOAD);
          if (hadPendingCredentialChanges) {
            // 改密意图随重载被放弃：通知 onError（改密页停留并提示），不误报成功
            const abandonedMessage: string =
              ResourceManager.getString($r('app.string.change_password_abandoned_by_reload'));
            if (callback && callback.onError) {
              callback.onError(abandonedMessage);
            } else {
              CommonUtils.showToast(abandonedMessage);
            }
          } else if (callback && callback.onSuccess) {
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
   * 常驻池化（POOL_DATABASE_WORKER = true）：复用常驻 Worker；
   * false 时保留旧行为（每操作 terminate + 重建）
   * @param req
   * @param callback
   * @param release 保存锁释放函数（终态回调，异常路径必须调用，否则后续保存永久排队）
   */
  static async saveDatabaseAsync(req: SaveDatabaseMessage, callback?: SaveDatabaseCallback,
    release?: () => void) {
    // 旧行为：释放之前的异步线程（互斥锁保证此时上一个 Worker 已空闲，terminate 仅做清理）
    if (!Constants.POOL_DATABASE_WORKER && KdbxSaveService.databaseWorker) {
      try {
        KdbxSaveService.databaseWorker.terminate();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Save database worker terminate error: %{public}s', error.message);
      }
      KdbxSaveService.databaseWorker = null;
      hilog.info(DOMAIN, TAG, 'Database save worker terminated');
    }

    // 缓存策略随任务注入（常驻模式下 INIT 快照会过期；须先于 Worker 创建，
    // 使任务消息携带的 forceRefresh 覆盖 INIT 快照中被消费的值）
    DatabaseWorkerFactory.attachCachePolicy(req);

    try {
      req.data = await KdbxUtils.kdbxToArrayBuffer(req.data);
      KdbxSaveService.saveDatabaseWorker(req, callback, release);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Save database serialize error: %{public}s', error?.message);
      if (callback && callback.onError) {
        callback.onError(error?.message ?? 'save failed');
      } else {
        CommonUtils.showToast(error?.message ?? 'save failed');
      }
      release?.();
    }
  }

  /**
   * 保存数据库线程
   * @param savedDb
   * @param dbFileParam
   */
  private static saveDatabaseWorker(req: SaveDatabaseMessage, callback?: SaveDatabaseCallback,
    release?: () => void): void {
    // 懒创建常驻 Worker（旧行为下上方已置空，必新建；保存锁保证无并发保存）
    if (KdbxSaveService.databaseWorker === null) {
      KdbxSaveService.databaseWorker = DatabaseWorkerFactory.createSaveWorker();
    }
    try {
      KdbxSaveService.databaseWorker.postMessage(req, [req.data as ArrayBuffer]);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Save database worker error: %{public}s', err.message);
      KdbxSaveService.databaseWorker = null;
      if (callback && callback.onError) {
        callback.onError(err.message);
      } else {
        CommonUtils.showToast(err.message);
      }
      release?.();
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
        case MessageType.PROGRESS:
          KdbxSaveService.onProgress(data as ProgressMessage, callback);
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
      // 常驻 isolate 异常：终止并置空引用，下次操作重建（崩溃自愈）
      try {
        KdbxSaveService.databaseWorker?.terminate();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Terminate broken save worker error: %{public}s', e.message);
      }
      KdbxSaveService.databaseWorker = null;
      if (callback && callback.onError) {
        callback.onError(err.message);
      }
      release?.();
    }

    // 注册onexit回调：Worker 销毁时释放保存锁，防止常驻 Worker 被外部终止
    // （应用恢复重置 / 紧急清理）时后续保存永久排队
    KdbxSaveService.databaseWorker.onexit = (code: number) => {
      hilog.info(DOMAIN, TAG, 'Database save worker exit: %{public}d', code);
      KdbxSaveService.databaseWorker = null;
      // 在途保存被外部终止：改密未完成，清理待应用凭证字段（F1 回归）
      FileService.clearPendingCredentialChanges();
      release?.();
    }
  }

  /**
   * 终止常驻保存 Worker。
   * 常驻池化下不再被业务例行调用，仅供紧急清理 / 应用恢复（Ability 重建）
   * 时重置 Worker 池使用；在途保存由 onexit 兜底释放互斥锁。
   */
  public static stopWorker(): void {
    if (KdbxSaveService.databaseWorker) {
      try {
        KdbxSaveService.databaseWorker.terminate();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Save database worker terminate error: %{public}s', error.message);
      }
      KdbxSaveService.databaseWorker = null;
      hilog.info(DOMAIN, TAG, 'Database save worker terminated');
    }
  }

  static callbackWarp(callback?: SaveDatabaseCallback, release?: () => void): SaveDatabaseCallback {
    return {
      onSuccess: (message: SuccessMessage) => {
        KdbxSaveService.handleSuccess(message, callback, release);
      },
      onError: (message: string) => {
        // 保存失败：清理待应用的改密凭证字段（F1 回归），
        // 防止残留的 newPassword/newKeyLocation/notUseKeyFile 被后续普通保存静默应用（锁定风险）
        FileService.clearPendingCredentialChanges();
        callback?.onError?.(message);
        release?.();
      },
      onMessage: (message: string) => {
        callback?.onMessage?.(message);
      },
      onProgress: (message: ProgressMessage) => {
        callback?.onProgress?.(message);
      },
      onConflict: (message: ConflictMessage) => {
        KdbxSaveService.handleConflict(message, callback);
        release?.();
      }
    }
  }

  static handleSuccess(message: SuccessMessage, callback?: SaveDatabaseCallback, release?: () => void) {
    // 数据库保存成功：更新版本基线（modifiedTime + version + contentHash），供下次保存做冲突检测
    const dbFileParam = FileService.getDbFileParam();
    dbFileParam.modifiedTime = message.modifiedTime;
    dbFileParam.version = message.version ?? null;
    dbFileParam.contentHash = message.contentHash ?? null;
    // 保存后库大小可能剧增（附件等）：回填加载调度尺寸事实（进程内存 + 最近文件持久化快照），
    // 避免下次加载按旧尺寸误判"小库"派发主线程（大库解密+解析阻塞 UI）
    KdbxSaveService.refreshSizeCache(dbFileParam.filePath, message.fileSize);
    if (message.isMerge) {
      // §7.4：合并模型走 M0 会话文件解包裹还原（仅路径跨线程），缺失时回退消息内 data
      KdbxUtils.successMessageToKdbx(message, FileService.getDbFileParam()).then(kdbx => {
        FileService.getDbFileParam().database = kdbx;
        EventBus.emit<void>(EventBus.DATABASE_RELOAD);
        if (callback && callback.onSuccess) {
          callback.onSuccess(message);
        }
        release?.();
      }).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Save database error: %{public}s, %{public}s', error?.message, error?.stack);
        if (callback && callback.onError) {
          callback.onError(error.message);
        } else {
          CommonUtils.showToast(error.message);
        }
        release?.();
      });
    } else {
      EventBus.emit<void>(EventBus.DATABASE_UPDATE);
      if (callback && callback.onSuccess) {
        callback.onSuccess(message);
      }
      release?.();
    }
  }

  /**
   * 保存成功后回填尺寸调度事实：分级加载尺寸解析链的 ① 调度缓存（进程内存）与
   * ② 最近文件持久化快照（RecentFile.fileSize）两级来源同步更新。
   * best-effort：失败仅记日志，不影响保存主流程
   * @param filePath 远端文件路径
   * @param fileSize 保存后的新尺寸（字节），无效值忽略
   */
  private static refreshSizeCache(filePath: string, fileSize: number | undefined): void {
    if (fileSize === undefined || fileSize <= 0) {
      return;
    }
    LoadDispatchCache.put(filePath, fileSize);
    RecentFilesService.getRecentFile(filePath).then((recentFile: RecentFile | null) => {
      if (recentFile === null) {
        return;
      }
      recentFile.fileSize = fileSize;
      RecentFilesService.addRecentFile(recentFile).catch((error: Error) => {
        hilog.warn(DOMAIN, TAG, 'Refresh recent file size failed: %{public}s', error.message);
      });
    }).catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'Read recent file for size refresh failed: %{public}s', error.message);
    });
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

  static onProgress(data: ProgressMessage, callback?: SaveDatabaseCallback) {
    if (!callback) {
      return;
    }
    if (callback.onProgress) {
      callback.onProgress(data);
    }
  }

  static onError(data: LoadMessage, callback?: SaveDatabaseCallback) {
    if (!callback) {
      return;
    }
    if (callback.onError) {
      const prefix: string = ResourceManager.getMessage(data.message);
      callback.onError(data.detail ? `${prefix}: ${data.detail}` : prefix);
    }
  }
}
