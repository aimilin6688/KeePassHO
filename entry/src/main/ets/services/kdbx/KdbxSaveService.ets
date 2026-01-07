import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../../common/constants/Constants';
import { CommonUtils, KdbxUtils, ResourceManager } from '../../common/utils';
import { FileService } from '../../services/FileService';
import { SaveDatabaseCallback } from '../../workers/callback/SaveDatabaseCallback';
import { DatabaseSave } from '../../workers/DatabaseSave';
import { SaveDatabaseMessage } from '../../workers/DatabaseSaveWorkerParam';
import { LoadMessage, MessageType, SuccessMessage, WorkerMessage } from '../../workers/WorkerParam';
import { EventBus } from '../EventBus';

const DOMAIN = 0x0000;
const TAG = 'KdbxSaveService';

/**
 * 保存数据库服务类
 */
export default class KdbxSaveService {
  private static databaseWorker: worker.ThreadWorker | null = null;

  /**
   * 保存数据库
   * @returns 结果信息
   */
  public static saveDatabase(callback?: SaveDatabaseCallback): void {
    // 启用保存线程，保存数据库
    const dbFileParam = FileService.getDbFileParam();
    if (!dbFileParam.database) {
      hilog.error(DOMAIN, TAG, 'Database is null');
      if (callback && callback.onError) {
        callback.onError(ResourceManager.getString($r('app.string.invalid_database')));
      }
      return;
    }

    const saveDatabaseReq = new SaveDatabaseMessage(dbFileParam.database, dbFileParam);
    const callbackWarp = KdbxSaveService.callbackWarp(callback);
    if (Constants.ASYNC_SAVE_DATABASE) {
      KdbxSaveService.saveDatabaseAsync(saveDatabaseReq, callbackWarp);
    } else {
      new DatabaseSave(callbackWarp).handleSaveDatabase(saveDatabaseReq);
    }
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
    KdbxSaveService.databaseWorker = new worker.ThreadWorker('entry/ets/workers/DatabaseSaveWorker.ets');
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
    // work 现成中执行
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
      onMessage: callback?.onMessage
    }
  }

  static handleSuccess(message: SuccessMessage, callback?: SaveDatabaseCallback) {
    // 数据库加载成功
    FileService.getDbFileParam().modifiedTime = message.modifiedTime;
    if (message.isMerge) {
      KdbxUtils.arrayBufferToKdbx(message.data, FileService.getDbFileParam()).then(kdbx => {
        FileService.getDbFileParam().database = kdbx;
        EventBus.emit<void>(EventBus.DATABASE_RELOAD);
        if (callback && callback.onSuccess) {
          callback.onSuccess(message);
        }
      }).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Save database error: %{public}s', error.message);
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

  static onMessage(data: LoadMessage, callback?: SaveDatabaseCallback) {
    if (!callback) {
      return;
    }
    if (callback.onMessage) {
      callback.onMessage(ResourceManager.getString(data.message));
    }
  }

  static onError(data: LoadMessage, callback?: SaveDatabaseCallback) {
    if (!callback) {
      return;
    }
    if (callback.onError) {
      callback.onError(ResourceManager.getString(data.message));
    }
  }
}