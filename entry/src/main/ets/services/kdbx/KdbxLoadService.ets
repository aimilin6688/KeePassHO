import { LoadDatabase } from '../../workers/DatabaseLoadWorkerParam';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LoadMessage, MessageType, PrewarmMessage, PrewarmResultMessage, SuccessMessage, toErrorMessage, WorkerMessage } from '../../workers/WorkerParam';
import { CommonUtils, ResourceManager } from '../../common/utils';
import { DatabaseLoad } from '../../workers/DatabaseLoad';
import { DatabaseWorkerFactory } from '../../workers/DatabaseWorkerFactory';
import { Constants } from '../../common/constants/Constants';
import { CacheConstants } from '../../storage/cache/CacheConstants';
import { StorageConfig, StorageType } from '../../storage';
import { LoadDispatchCache } from './LoadDispatchCache';

const DOMAIN = 0x0000;
const TAG = 'KdbxLoadService';

export default class KdbxLoadService {
  // 常驻加载 Worker（POOL_DATABASE_WORKER = true 时进程级复用；null 表示待懒创建）
  private static databaseWorker: worker.ThreadWorker | null = null;
  // 常驻池化忙标志：加载进行中时立即拒绝新请求（worker_busy），
  // 替代旧行为的 "kill 重来"，防双击打开导致两次成功导航
  private static workerBusy: boolean = false;
  // 在途任务回调（PREWARM 结果与加载回调并存的必要前提：onmessage 创建时一次性注册按 type 扇出）
  private static currentCallback: KdbxLoadServiceCallback | null = null;
  // Worker 代际计数：每次创建新 Worker 递增；被替换的陈旧 Worker 迟到事件按代际忽略，
  // 不清空新一代 Worker 的在途状态（stopWorker 不递增——当前 Worker 的 onexit 仍需送达回调）
  private static workerGeneration: number = 0;

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

    // 懒创建常驻 Worker（旧行为下上方已置空，必新建）；
    // onmessage/onAllErrors/onexit 在创建时一次性注册（含 PREWARM_RESULT 扇出）
    try {
      KdbxLoadService.ensureWorker().postMessage(JSON.stringify(loadParam));
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
    // postMessage 返回后同步赋值：Worker 响应事件不可能先于当前同步块到达
    KdbxLoadService.currentCallback = callback ?? null;
  }

  /**
   * 懒创建常驻 Worker 并注册一次性消息处理（PREWARM_RESULT / MESSAGE / SUCCESS / ERROR 扇出）
   */
  private static ensureWorker(): worker.ThreadWorker {
    if (KdbxLoadService.databaseWorker === null) {
      const w: worker.ThreadWorker = DatabaseWorkerFactory.createLoadWorker();
      KdbxLoadService.workerGeneration++;
      KdbxLoadService.installWorkerHandlers(w, KdbxLoadService.workerGeneration);
      KdbxLoadService.databaseWorker = w;
    }
    return KdbxLoadService.databaseWorker;
  }

  /**
   * Worker 创建时一次性注册消息与生命周期处理（替代旧行为的"每次加载重挂"，
   * 使 PREWARM_RESULT 在无加载任务/加载在途时均能被正确处理）。
   * 生命周期事件按代际守卫：陈旧 Worker（已被新一代替换）的迟到事件整体忽略
   */
  private static installWorkerHandlers(w: worker.ThreadWorker, generation: number): void {
    // 注册onmessage回调，当宿主线程接收到来自其创建的Worker通过workerPort.postMessage接口发送的消息时被调用，在宿主线程执行
    w.onmessage = (e: MessageEvents) => {
      const data = e.data as WorkerMessage;
      switch (data.type) {
        // 预热结果：仅更新调度缓存，与在途任务回调无关
        case MessageType.PREWARM_RESULT:
          KdbxLoadService.handlePrewarmResult(data as PrewarmResultMessage);
          return;
        // 提示消息
        case MessageType.MESSAGE:
          KdbxLoadService.handleLoadMessage(data, KdbxLoadService.currentCallback?.onLoadMessage);
          return;
        case MessageType.SUCCESS:
          // 任务终态：释放忙标志，Worker 保留复用；
          // currentCallback 不清空——与旧闭包语义一致，onexit/onAllErrors 在任务完成后仍可送达（下次加载自然覆盖）
          KdbxLoadService.workerBusy = false;
          KdbxLoadService.handleSuccessMessage(data, KdbxLoadService.currentCallback?.onSuccessMessage);
          return;
        case MessageType.ERROR:
          // 任务终态：释放忙标志，Worker 保留复用（currentCallback 保留同上）
          KdbxLoadService.workerBusy = false;
          KdbxLoadService.handleErrorMessage(data, KdbxLoadService.currentCallback?.onErrorMessage);
          return;
      }
    }
    // 注册onmessageerror回调，当Worker对象接收到无法序列化的消息时被调用，在宿主线程执行
    w.onAllErrors = (err: ErrorEvent) => {
      // 忽略NativeCustomSpan和ViewV2错误
      if (err.message.indexOf('NativeCustomSpan') != -1 || err.message.indexOf('ViewV2') != -1) {
        hilog.debug(DOMAIN, TAG, 'Load database error: %{public}s', err.message);
        return;
      }

      // 打印错误日志
      hilog.error(DOMAIN, TAG, 'Load database error: %{public}s', err.message);
      // 代际守卫：被替换的陈旧 Worker 迟到报错不得终止新 Worker 或清空在途回调
      if (generation !== KdbxLoadService.workerGeneration) {
        hilog.warn(DOMAIN, TAG, 'Stale worker error ignored (replaced)');
        return;
      }
      // 常驻 isolate 异常：终止并置空引用，释放忙标志，下次操作重建（崩溃自愈）
      try {
        KdbxLoadService.databaseWorker?.terminate();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Terminate broken load worker error: %{public}s', e.message);
      }
      KdbxLoadService.databaseWorker = null;
      KdbxLoadService.workerBusy = false;
      const onAllErrors = KdbxLoadService.currentCallback?.onAllErrors;
      KdbxLoadService.currentCallback = null;
      if (onAllErrors) {
        onAllErrors(err);
      }
    }

    // 注册onexit回调，当Worker销毁时被调用，在宿主线程执行
    // 常驻模式下仅在异常退出 / 显式 stopWorker（应用恢复重置）时触发
    w.onexit = (e: number) => {
      hilog.info(DOMAIN, TAG, 'Database load worker exit: %{public}d', e);
      // 代际守卫：被新一代替换的陈旧 Worker 迟到退出事件不清空新 Worker 的在途状态；
      // stopWorker 触发的退出（代际未变）正常清理并送达 onexit 回调（清理幂等）
      if (generation !== KdbxLoadService.workerGeneration) {
        hilog.debug(DOMAIN, TAG, 'Stale worker exit ignored (replaced)');
        return;
      }
      // Worker 已消亡：置空引用供下次操作重建；释放忙标志（在途任务兜底）
      KdbxLoadService.databaseWorker = null;
      KdbxLoadService.workerBusy = false;
      const onexit = KdbxLoadService.currentCallback?.onexit;
      KdbxLoadService.currentCallback = null;
      if (onexit) {
        onexit(e);
      }
    }
  }

  /**
   * 预热常驻加载 Worker（页面展示期调用，用户输入密码期间完成）：
   * - Worker isolate 模块图初始化（消除首次加载冷启动）
   * - Worker 内存储连接建立（消除大库下载冷 TLS）
   * - getInfoOrNull 探测大小回填加载调度缓存
   * busy（加载在途）时跳过；不设置 busy；不消费 forceRefresh（一次性标志归加载任务所有）。
   * 失败无害（fire-and-forget，仅日志）
   */
  public static prewarm(filePath: string, storageType: StorageType, storageConfig: StorageConfig): void {
    if (!Constants.ASYNC_LOAD_DATABASE || !Constants.POOL_DATABASE_WORKER) {
      return;
    }
    if (KdbxLoadService.workerBusy) {
      hilog.debug(DOMAIN, TAG, 'prewarm skipped: worker busy');
      return;
    }
    // Worker 创建会消费 forceRefresh（buildInitMessage 就地读取清标志），
    // 预热须对调用方透明：快照并在创建后恢复，保证后续加载任务的强制刷新语义
    const savedForceRefresh: boolean = CacheConstants.getForceRefresh();
    try {
      KdbxLoadService.ensureWorker().postMessage(JSON.stringify(new PrewarmMessage(filePath, storageType, storageConfig)));
      if (savedForceRefresh) {
        CacheConstants.setForceRefresh(true);
      }
      hilog.info(DOMAIN, TAG, 'prewarm sent: %{public}s', filePath);
    } catch (e) {
      if (savedForceRefresh) {
        CacheConstants.setForceRefresh(true);
      }
      hilog.warn(DOMAIN, TAG, 'prewarm failed (ignored): %{public}s', e.message);
    }
  }

  /**
   * 处理 Worker 预热结果：有效大小写入加载调度缓存（供分级调度零网络决策）
   */
  private static handlePrewarmResult(result: PrewarmResultMessage): void {
    if (result.size !== undefined && result.size > 0) {
      LoadDispatchCache.put(result.filePath, result.size);
    }
    hilog.info(DOMAIN, TAG, 'prewarm result: file=%{public}s size=%{public}d error=%{public}s',
      result.filePath, result.size ?? -1, result.error ?? 'none');
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
    // 终止 Worker（currentCallback 不在此清空：由 onexit 送达回调后清理，
    // 与旧闭包语义一致——任务完成后 stopWorker 仍能触发 onexit）
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
