import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from '../../common/utils/CommonUtils';
import KdbxUtils from '../../common/utils/KdbxUtils';
import ResourceManager from '../../common/utils/ResourceManager';
import { FileService } from '../../services/FileService';
import { SaveDatabaseMessage } from '../../workers/DatabaseSaveWorkerParam';
import { LoadMessage, MessageType, SuccessMessage, WorkerMessage } from '../../workers/WorkerParam';
import { EventBus } from '../EventBus';
import { DbFileParam } from '../TypeDefined';

const DOMAIN = 0x0000;
const TAG = 'KdbxSaveService';

export interface SaveDatabaseCallback {
  /**
   * 保存成功
   */
  onSuccess?: () => void;

  /**
   * 保存失败
   * @param message 异常消息
   */
  onError?: (message: string) => void;

  /**
   * 过程消息
   * @param message
   */
  onMessage?: (message: string) => void;
}

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
    if (KdbxSaveService.databaseWorker) {
      KdbxSaveService.databaseWorker.terminate();
      KdbxSaveService.databaseWorker = null;
      hilog.info(DOMAIN, TAG, 'Database save worker terminated');
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
    KdbxUtils.kdbxToArrayBuffer(dbFileParam.database).then(async savedDb => {
      KdbxSaveService.saveDatabaseWorker(savedDb, dbFileParam, callback);
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Database is null');
      if (callback && callback.onError) {
        callback.onError(error.message);
      }
    });
  }

  /**
   * 保存数据库线程
   * @param savedDb
   * @param dbFileParam
   */
  private static saveDatabaseWorker(savedDb: ArrayBuffer, dbFileParam: DbFileParam, callback?: SaveDatabaseCallback): void {
    KdbxSaveService.databaseWorker = new worker.ThreadWorker('entry/ets/workers/DatabaseSaveWorker.ets');
    KdbxSaveService.databaseWorker.postMessage(new SaveDatabaseMessage(savedDb, dbFileParam), [savedDb]);

    // 注册onmessage回调，当宿主线程接收到来自其创建的Worker通过workerPort.postMessage接口发送的消息时被调用，在宿主线程执行
    KdbxSaveService.databaseWorker.onmessage = (e: MessageEvents) => {
      let data = e.data as WorkerMessage;
      switch (data.type) {
        // 错误消息
        case MessageType.ERROR:
          let errorMessage = data as LoadMessage;
          if (callback && callback.onError) {
            callback.onError(ResourceManager.getString(errorMessage.message));
          }
          KdbxSaveService.handleErrorMessage(errorMessage);
          return;
        // 加载进度消息
        case MessageType.MESSAGE:
          const loadMessage = data as LoadMessage;
          if (callback && callback.onMessage) {
            callback.onMessage(ResourceManager.getString(loadMessage.message));
          }
          KdbxSaveService.handleLoadMessage(loadMessage);
          return;
        // 数据库加载成功
        case MessageType.SUCCESS:
          let successMessage = data as SuccessMessage;
          if (callback && callback.onSuccess) {
            callback?.onSuccess();
          }
          KdbxSaveService.handleSuccessMessage(successMessage);
          return;
      }
    }

    // 注册onerror回调，当Worker线程发生异常时被调用，在宿主线程执行
    KdbxSaveService.databaseWorker.onAllErrors = (err: ErrorEvent) => {
      hilog.error(DOMAIN, TAG, 'Save database error: %{public}s', err.message);
      if (err.message.indexOf('NativeCustomSpan') != -1) {
        return;
      }
      if (callback && callback.onError) {
        callback.onError(err.message);
      }
      CommonUtils.showToast(err.message);
    }
  }

  /**
   * 处理来自线程的错误消息
   * @param data
   */
  private static handleErrorMessage(errorMessage: LoadMessage) {
    hilog.error(DOMAIN, TAG, 'Save database error: %{public}s', errorMessage.message);
    CommonUtils.showToast(ResourceManager.getString(errorMessage.message));
  }

  /**
   * 处理来自线程的进度消息
   * @param data
   */
  private static handleLoadMessage(loadMessage: LoadMessage) {
    // 加载进度消息
    hilog.info(DOMAIN, TAG, 'Received save database message:  %{public}s', ResourceManager.getString(loadMessage.message));
    CommonUtils.showToast(ResourceManager.getString(loadMessage.message));
  }

  /**
   * 处理来自线程的成功消息
   * @param data
   */
  private static handleSuccessMessage(successMessage: SuccessMessage) {
    // 数据库加载成功
    FileService.getDbFileParam().modifiedTime = successMessage.modifiedTime;
    if (successMessage.isMerge) {
      KdbxUtils.arrayBufferToKdbx(successMessage.data, FileService.getDbFileParam()).then(kdbx => {
        FileService.getDbFileParam().database = kdbx;
        EventBus.emit<void>(EventBus.DATABASE_MERGE);
      })
    } else {
      EventBus.emit<void>(EventBus.DATABASE_UPDATE);
    }
    CommonUtils.showToast(ResourceManager.getString($r('app.string.save_success_message')));
  }
}