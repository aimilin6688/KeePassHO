import { LoadDatabase } from '../../workers/DatabaseLoadWorkerParam';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LoadMessage, MessageType, SuccessMessage, toErrorMessage, WorkerMessage } from '../../workers/WorkerParam';
import { CommonUtils, ResourceManager } from '../../common/utils';
import { DatabaseLoad } from '../../workers/DatabaseLoad';
import { DatabaseWorkerFactory } from '../../workers/DatabaseWorkerFactory';
import { Constants } from '../../common/constants/Constants';

const DOMAIN = 0x0000;
const TAG = 'KdbxLoadService';

export default class KdbxLoadService {
  // 常驻加载 Worker（POOL_DATABASE_WORKER = true 时进程级复用；null 表示待懒创建）
  private static databaseWorker: worker.ThreadWorker | null = null;
  // 常驻池化忙标志：加载进行中时立即拒绝新请求（worker_busy），
  // 替代旧行为的 "kill 重来"，防双击打开导致两次成功导航
  private static workerBusy: boolean = false;

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
   * 常驻池化（POOL_DATABASE_WORKER = true）：懒创建/复用 Worker，忙时立即拒绝；
   * false 时保留旧行为（每操作 stopWorker + 重建）
   * @param loadParam 加载参数
   * @param callback 回调地址
   */
  private static asyncLoadDatabase(loadParam: LoadDatabase, callback?: KdbxLoadServiceCallback): void {
    if (Constants.POOL_DATABASE_WORKER) {
      // 忙判定：立即拒绝，不排队
      if (KdbxLoadService.workerBusy) {
        const busyMessage: LoadMessage = toErrorMessage('worker_busy');
        if (callback?.onErrorMessage) {
          callback.onErrorMessage(busyMessage);
        } else {
          CommonUtils.showToast(ResourceManager.getMessage('worker_busy'));
        }
        return;
      }
      KdbxLoadService.workerBusy = true;
    } else {
      // 旧行为：每操作 terminate 旧 Worker 后重建
      KdbxLoadService.stopWorker();
    }

    // 缓存策略随任务注入（常驻模式下 INIT 快照会过期；须先于 Worker 创建，
    // 使任务消息携带的 forceRefresh 覆盖 INIT 快照中被消费的值）
    DatabaseWorkerFactory.attachCachePolicy(loadParam);

    // 懒创建常驻 Worker（旧行为下上方已置空，必新建）
    if (KdbxLoadService.databaseWorker === null) {
      KdbxLoadService.databaseWorker = DatabaseWorkerFactory.createLoadWorker();
    }

    try {
      KdbxLoadService.databaseWorker.postMessage(JSON.stringify(loadParam));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Load database error: %{public}s', e.message);
      // 通道异常：置空引用，下次操作重建
      KdbxLoadService.databaseWorker = null;
      KdbxLoadService.workerBusy = false;
      if (callback?.onErrorMessage) {
        callback.onErrorMessage(e.message);
      } else {
        CommonUtils.showToast(e.message);
      }
      return;
    }

    // 注册onmessage回调，当宿主线程接收到来自其创建的Worker通过workerPort.postMessage接口发送的消息时被调用，在宿主线程执行
    KdbxLoadService.databaseWorker.onmessage = (e: MessageEvents) => {
      let data = e.data as WorkerMessage;
      switch (data.type) {
        // 提示消息
        case MessageType.MESSAGE:
          KdbxLoadService.handleLoadMessage(data, callback?.onLoadMessage);
          return;
        case MessageType.SUCCESS:
          // 任务终态：释放忙标志，Worker 保留复用
          KdbxLoadService.workerBusy = false;
          KdbxLoadService.handleSuccessMessage(data, callback?.onSuccessMessage);
          return;
        case MessageType.ERROR:
          // 任务终态：释放忙标志，Worker 保留复用
          KdbxLoadService.workerBusy = false;
          KdbxLoadService.handleErrorMessage(data, callback?.onErrorMessage);
          return;
      }
    }
    // 注册onmessageerror回调，当Worker对象接收到无法序列化的消息时被调用，在宿主线程执行
    KdbxLoadService.databaseWorker.onAllErrors = (err: ErrorEvent) => {
      // 忽略NativeCustomSpan和ViewV2错误
      if (err.message.indexOf('NativeCustomSpan') != -1 || err.message.indexOf('ViewV2') != -1) {
        hilog.debug(DOMAIN, TAG, 'Load database error: %{public}s', err.message);
        return;
      }

      // 打印错误日志
      hilog.error(DOMAIN, TAG, 'Load database error: %{public}s', err.message);
      // 常驻 isolate 异常：终止并置空引用，释放忙标志，下次操作重建（崩溃自愈）
      try {
        KdbxLoadService.databaseWorker?.terminate();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Terminate broken load worker error: %{public}s', e.message);
      }
      KdbxLoadService.databaseWorker = null;
      KdbxLoadService.workerBusy = false;
      if (callback?.onAllErrors) {
        callback.onAllErrors(err);
      }
    }

    // 注册onexit回调，当Worker销毁时被调用，在宿主线程执行
    // 常驻模式下仅在异常退出 / 显式 stopWorker（应用恢复重置）时触发
    KdbxLoadService.databaseWorker.onexit = (e: number) => {
      hilog.info(DOMAIN, TAG, 'Database load worker exit: %{public}d', e);
      // Worker 已消亡：置空引用供下次操作重建；释放忙标志（在途任务兜底）
      KdbxLoadService.databaseWorker = null;
      KdbxLoadService.workerBusy = false;
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
    hilog.debug(DOMAIN, TAG, 'Received loading message:  %{public}s', ResourceManager.getMessage(loadMessage.message));
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
    hilog.info(DOMAIN, TAG, 'Received success message: modifiedTime:%{public}d, isMerge:%{public}s', successMessage.modifiedTime,
      successMessage.isMerge);
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
   * 终止 Worker。
   * 常驻池化下不再被业务例行调用，仅供单测 / 紧急清理 /
   * 应用恢复（Ability 重建）时重置 Worker 池使用；在途 onexit 兜底释放忙标志。
   */
  public static stopWorker() {
    // 终止 Worker
    if (KdbxLoadService.databaseWorker) {
      try {
        KdbxLoadService.databaseWorker.terminate();
        KdbxLoadService.databaseWorker = null;
        KdbxLoadService.workerBusy = false;
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