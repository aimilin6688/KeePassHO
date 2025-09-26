import { LoadDatabase } from '../../workers/DatabaseLoadWorkerParam';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LoadMessage, MessageType, SuccessMessage, WorkerMessage } from '../../workers/WorkerParam';
import ResourceManager from '../../common/utils/ResourceManager';
import { DatabaseLoad } from '../../workers/DatabaseLoad';
import { Constants } from '../../common/constants/Constants';

const DOMAIN = 0x0000;
const TAG = 'KdbxLoadService';

export default class KdbxLoadService {
  // 启用加载线程，加载数据库
  private static databaseWorker: worker.ThreadWorker | null = null;

  /**
   * 加载数据库
   */
  public static loadDatabase(loadParam: LoadDatabase, callback?: KdbxLoadServiceCallback): void {
    if (Constants.ASYNC_LOAD_DATABASE) {
      KdbxLoadService.asyncLoadDatabase(loadParam, callback);
    } else {
      new DatabaseLoad().handleLoadDatabase(loadParam, callback);
    }
  }

  /**
   * 异步线程加载数据库
   * @param loadParam 加载参数
   * @param callback 回调地址
   */
  private static asyncLoadDatabase(loadParam: LoadDatabase, callback?: KdbxLoadServiceCallback): void {
    KdbxLoadService.stopWorker();

    // 创建 Worker
    KdbxLoadService.databaseWorker = new worker.ThreadWorker('entry/ets/workers/DatabaseLoadWorker.ets');
    KdbxLoadService.databaseWorker.postMessage(JSON.stringify(loadParam));

    // 注册onmessage回调，当宿主线程接收到来自其创建的Worker通过workerPort.postMessage接口发送的消息时被调用，在宿主线程执行
    KdbxLoadService.databaseWorker.onmessage = (e: MessageEvents) => {
      let data = e.data as WorkerMessage;
      switch (data.type) {
        // 提示消息
        case MessageType.MESSAGE:
          KdbxLoadService.handleLoadMessage(data, callback?.onLoadMessage);
          return;
        case MessageType.SUCCESS:
          KdbxLoadService.handleSuccessMessage(data, callback?.onSuccessMessage);
          return;
        case MessageType.ERROR:
          KdbxLoadService.handleErrorMessage(data, callback?.onErrorMessage);
          return;
      }
    }
    // 注册onmessageerror回调，当Worker对象接收到无法序列化的消息时被调用，在宿主线程执行
    KdbxLoadService.databaseWorker.onAllErrors = (err: ErrorEvent) => {
      hilog.error(DOMAIN, TAG, 'Load database error: %{public}s', err.message);
      if (err.message.indexOf('NativeCustomSpan') != -1) {
        return;
      }
      if (callback?.onAllErrors) {
        callback.onAllErrors(err);
      }
    }

    // 注册onexit回调，当Worker销毁时被调用，在宿主线程执行
    KdbxLoadService.databaseWorker.onexit = (e: number) => {
      hilog.info(DOMAIN, TAG, 'Database load worker exit: %{public}d', e);
      if (callback?.onexit) {
        callback.onexit(e);
      }
    }
  }

  /**
   * 处理加载进度消息
   * @param data
   * @param onLoadMessage
   */
  private static handleLoadMessage(data: WorkerMessage, onLoadMessage?: (message: LoadMessage) => void) {
    const loadMessage = data as LoadMessage;
    hilog.debug(DOMAIN, TAG, 'Received loading message:  %{public}s', ResourceManager.getString(loadMessage.message));
    if (onLoadMessage) {
      onLoadMessage(loadMessage);
    }
  }

  /**
   * 处理来自线程的成功消息
   * @param data
   * @param onSuccessMessage
   */
  private static handleSuccessMessage(data: WorkerMessage, onSuccessMessage?: (message: SuccessMessage) => void) {
    const successMessage = data as SuccessMessage;
    hilog.info(DOMAIN, TAG, 'Received success message: modifiedTime:%{public}d, isMerge:%{public}s', successMessage.modifiedTime, successMessage.isMerge);
    if (onSuccessMessage) {
      onSuccessMessage(successMessage);
    }
  }

  /**
   * 处理来自线程的错误消息
   * @param data
   * @param onErrorMessage
   */
  private static handleErrorMessage(data: WorkerMessage, onErrorMessage?: (message: LoadMessage) => void) {
    let errorMessage = data as LoadMessage;
    hilog.error(DOMAIN, TAG, 'Received error message: %{public}s', errorMessage.message);
    if (onErrorMessage) {
      onErrorMessage(errorMessage);
    }
  }


  /**
   * 终止 Worker
   */
  public static stopWorker() {
    // 终止 Worker
    if (KdbxLoadService.databaseWorker) {
      try {
        KdbxLoadService.databaseWorker.terminate();
        KdbxLoadService.databaseWorker = null;
        hilog.info(DOMAIN, TAG, 'Database load worker terminated');
      } catch (e) {
        hilog.info(DOMAIN, TAG, 'Database load worker terminated error: %{public}s', e);
      }
    }
  }
}

export interface KdbxLoadServiceCallback {
  /**
   * Worker销毁
   */
  onexit?: (e: number) => void;

  /**
   * Worker异常
   */
  onAllErrors?: (err: ErrorEvent) => void;

  /**
   * 加载进度消息
   */
  onLoadMessage?: (message: LoadMessage) => void;

  /**
   * 加载成功消息
   */
  onSuccessMessage?: (message: SuccessMessage) => void;

  /**
   * 加载错误消息
   */
  onErrorMessage?: (message: LoadMessage) => void;
}