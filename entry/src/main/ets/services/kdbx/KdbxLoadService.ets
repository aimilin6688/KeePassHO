import { LoadDatabase } from '../../workers/DatabaseLoadWorkerParam';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LoadMessage, MessageType, ProgressMessage, PrewarmMessage, PrewarmResultMessage, SuccessMessage, toErrorMessage, WorkerMessage } from '../../workers/WorkerParam';
import { CommonUtils, ResourceManager } from '../../common/utils';
import { DatabaseLoad } from '../../workers/DatabaseLoad';
import { DatabaseWorkerFactory } from '../../workers/DatabaseWorkerFactory';
import { Constants } from '../../common/constants/Constants';
import { CacheConstants } from '../../storage/cache/CacheConstants';
import { StorageConfig, StorageType } from '../../storage';
import { LoadDispatchCache } from './LoadDispatchCache';
import { LoadDispatchService } from './LoadDispatchService';

const DOMAIN = 0x0000;
const TAG = 'KdbxLoadService';

/**
 * 串行加载队列元素：加载参数 + 任务回调
 */
class PendingLoad {
  readonly loadParam: LoadDatabase;
  readonly callback?: KdbxLoadServiceCallback;

  constructor(loadParam: LoadDatabase, callback?: KdbxLoadServiceCallback) {
    this.loadParam = loadParam;
    this.callback = callback;
  }
}

export default class KdbxLoadService {
  // 常驻加载 Worker（POOL_DATABASE_WORKER = true 时进程级复用；null 表示待懒创建）
  private static databaseWorker: worker.ThreadWorker | null = null;
  // 常驻池化忙标志：加载进行中时立即拒绝新请求（worker_busy），
  // 替代旧行为的 "kill 重来"，防双击打开导致两次成功导航
  private static workerBusy: boolean = false;
  // 串行加载队列（AutoOpen 子库后台串行打开）：FIFO，前一个任务终态后派发下一个
  private static pendingLoads: PendingLoad[] = [];
  // 当前在途的队列任务（非 null 表示有任务在飞；兼作终态回调身份令牌，防重复推进）
  private static currentPendingLoad: PendingLoad | null = null;

  /**
   * 加载数据库（三入口统一：Password 主打开 / DatabaseView 刷新 / KdbxSaveService 合并重载）
   * 分级调度（SIZE_DISPATCH_LOAD = true）：小库（≤ SYNC_LOAD_MAX_BYTES）主线程直开，
   * 大库/未知走 Worker；总开关关闭时保持"恒 Worker"现状
   */
  public static loadDatabase(loadParam: LoadDatabase, callback?: KdbxLoadServiceCallback): void {
    if (!Constants.ASYNC_LOAD_DATABASE) {
      new DatabaseLoad().handleLoadDatabase(loadParam, callback);
      return;
    }
    if (!Constants.SIZE_DISPATCH_LOAD) {
      KdbxLoadService.asyncLoadDatabase(loadParam, callback);
      return;
    }
    KdbxLoadService.dispatchAndLoad(loadParam, callback);
  }

  /**
   * 排队加载数据库（AutoOpen 多子库后台串行打开场景）：
   * 与 loadDatabase 相比不因 Worker 忙而立即拒绝，而是 FIFO 排队，
   * 前一个任务到达任一终态（成功/错误/异常/退出）后自动派发下一个；
   * 同一任务的重复终态（如 SUCCESS 后 Worker 退出）只推进队列一次。
   * 注意：与队列外的直连加载（用户解锁/下拉刷新）并发时仍可能收到 worker_busy 错误，
   * 该场景由调用方以失败事件兜底（与 kp2a 子库打开失败语义一致）
   */
  public static enqueueLoad(loadParam: LoadDatabase, callback?: KdbxLoadServiceCallback): void {
    KdbxLoadService.pendingLoads.push(new PendingLoad(loadParam, callback));
    KdbxLoadService.dispatchNextPendingLoad();
  }

  /**
   * 派发队首任务；有任务在飞或队列空时跳过
   */
  private static dispatchNextPendingLoad(): void {
    if (KdbxLoadService.currentPendingLoad !== null) {
      return;
    }
    const next: PendingLoad | undefined = KdbxLoadService.pendingLoads.shift();
    if (next === undefined) {
      return;
    }
    KdbxLoadService.currentPendingLoad = next;
    const wrapped: KdbxLoadServiceCallback = {
      onLoadMessage: next.callback?.onLoadMessage,
      onProgressMessage: next.callback?.onProgressMessage,
      onSuccessMessage: (message: SuccessMessage) => {
        KdbxLoadService.finishPendingLoad(next);
        if (next.callback?.onSuccessMessage) {
          next.callback.onSuccessMessage(message);
        }
      },
      onErrorMessage: (message: LoadMessage) => {
        KdbxLoadService.finishPendingLoad(next);
        if (next.callback?.onErrorMessage) {
          next.callback.onErrorMessage(message);
        }
      },
      onAllErrors: (err: ErrorEvent) => {
        KdbxLoadService.finishPendingLoad(next);
        if (next.callback?.onAllErrors) {
          next.callback.onAllErrors(err);
        }
      },
      onexit: (e: number) => {
        KdbxLoadService.finishPendingLoad(next);
        if (next.callback?.onexit) {
          next.callback.onexit(e);
        }
      }
    };
    KdbxLoadService.loadDatabase(next.loadParam, wrapped);
  }

  /**
   * 队列任务终态：清除在飞标记并派发下一个（身份令牌守卫防重复推进）
   */
  private static finishPendingLoad(done: PendingLoad): void {
    if (KdbxLoadService.currentPendingLoad !== done) {
      return;
    }
    KdbxLoadService.currentPendingLoad = null;
    KdbxLoadService.dispatchNextPendingLoad();
  }

  /**
   * 尺寸解析 → 路由：小库主线程直开（Kdbx 实例直接引用传递，零协议税）；
   * 大库/未知走 Worker。precheckSize 随参数透传供守卫去重；
   * 成功回调统一回填调度缓存（fileSize 回传）
   */
  private static dispatchAndLoad(loadParam: LoadDatabase, callback?: KdbxLoadServiceCallback): void {
    const wrapped: KdbxLoadServiceCallback = {
      onLoadMessage: callback?.onLoadMessage,
      onSuccessMessage: (message: SuccessMessage) => {
        if (message.fileSize !== undefined && message.fileSize > 0) {
          LoadDispatchCache.put(loadParam.filePath, message.fileSize);
        }
        callback?.onSuccessMessage?.(message);
      },
      onProgressMessage: callback?.onProgressMessage,
      onErrorMessage: callback?.onErrorMessage,
      onAllErrors: callback?.onAllErrors,
      onexit: callback?.onexit
    };
    LoadDispatchService.resolveSize(loadParam.filePath, loadParam.storageType, loadParam.storageConfig)
      .then((size: number | undefined) => {
        const tDispatch: number = Date.now();
        if (size !== undefined && size > 0) {
          loadParam.precheckSize = size;
          if (size <= Constants.SYNC_LOAD_MAX_BYTES) {
            hilog.info(DOMAIN, TAG, 'dispatch: main thread, size=%{public}d: %{public}s',
              size, loadParam.filePath);
            new DatabaseLoad().handleLoadDatabase(loadParam, wrapped);
          } else {
            hilog.info(DOMAIN, TAG, 'dispatch: worker, size=%{public}d: %{public}s',
              size, loadParam.filePath);
            KdbxLoadService.asyncLoadDatabase(loadParam, wrapped);
          }
        } else {
          hilog.info(DOMAIN, TAG, 'dispatch: worker, size=unknown: %{public}s', loadParam.filePath);
          KdbxLoadService.asyncLoadDatabase(loadParam, wrapped);
        }
        hilog.info(DOMAIN, TAG, 'dispatch resolve: %{public}d ms', Date.now() - tDispatch);
      })
      .catch(() => {
        // 解析异常：保守走 Worker（不劣于现状）
        hilog.warn(DOMAIN, TAG, 'dispatch resolve failed, fallback to worker');
        KdbxLoadService.asyncLoadDatabase(loadParam, wrapped);
      });
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
    const w: worker.ThreadWorker = KdbxLoadService.ensureWorker();
    try {
      w.postMessage(JSON.stringify(loadParam));
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
    // 每任务挂载消息与生命周期处理（参考 KdbxSaveService：回调经闭包注入，不落静态字段）。
    // postMessage 返回后同步挂载：Worker 响应事件不可能先于当前同步块到达；
    // 新任务覆盖上一任务（或预热默认）挂载的处理器，天然防串扰
    KdbxLoadService.installWorkerHandlers(w, callback);
  }

  /**
   * 懒创建常驻 Worker 并挂载默认消息处理（无任务回调：
   * 仅扇出 PREWARM_RESULT 更新调度缓存 + 终态清理），
   * 加载任务投递后由 installWorkerHandlers 以任务回调覆盖
   */
  private static ensureWorker(): worker.ThreadWorker {
    if (KdbxLoadService.databaseWorker === null) {
      const w: worker.ThreadWorker = DatabaseWorkerFactory.createLoadWorker();
      KdbxLoadService.installWorkerHandlers(w, undefined);
      KdbxLoadService.databaseWorker = w;
    }
    return KdbxLoadService.databaseWorker;
  }

  /**
   * 挂载指定 Worker 的消息与生命周期处理（回调经参数闭包注入，随任务覆盖）。
   * 共享状态（databaseWorker / workerBusy）清理以实例身份守卫：
   * 被替换/终止的陈旧 Worker 迟到事件不清空新一代 Worker 的在途状态，
   * 回调仍送达其所属任务（stopWorker 触发的退出同样送达 onexit）
   */
  private static installWorkerHandlers(w: worker.ThreadWorker, callback?: KdbxLoadServiceCallback): void {
    // 注册onmessage回调，当宿主线程接收到来自其创建的Worker通过workerPort.postMessage接口发送的消息时被调用，在宿主线程执行
    w.onmessage = (e: MessageEvents) => {
      const data = e.data as WorkerMessage;
      switch (data.type) {
        // 预热结果：仅更新调度缓存，与任务回调无关
        case MessageType.PREWARM_RESULT:
          KdbxLoadService.handlePrewarmResult(data as PrewarmResultMessage);
          return;
        // 提示消息
        case MessageType.MESSAGE:
          KdbxLoadService.handleLoadMessage(data, callback);
          return;
        // 传输进度（下载）：与 MESSAGE 同款扇出语义（回调随任务闭包注入，天然防串扰）
        case MessageType.PROGRESS:
          KdbxLoadService.handleProgressMessage(data, callback);
          return;
        case MessageType.SUCCESS:
          // 任务终态：释放忙标志，Worker 保留复用；
          // 回调不清空——与旧闭包语义一致，onexit/onAllErrors 在任务完成后仍可送达（下次加载自然覆盖）
          if (KdbxLoadService.databaseWorker === w) {
            KdbxLoadService.workerBusy = false;
          }
          KdbxLoadService.handleSuccessMessage(data, callback);
          return;
        case MessageType.ERROR:
          // 任务终态：释放忙标志，Worker 保留复用（回调保留同上）
          if (KdbxLoadService.databaseWorker === w) {
            KdbxLoadService.workerBusy = false;
          }
          KdbxLoadService.handleErrorMessage(data, callback);
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
      // 常驻 isolate 异常：终止并置空引用，释放忙标志，下次操作重建（崩溃自愈）；
      // 陈旧 Worker（已被新一代替换）不得清理新一代的在途状态
      try {
        w.terminate();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Terminate broken load worker error: %{public}s', e.message);
      }
      if (KdbxLoadService.databaseWorker === w) {
        KdbxLoadService.databaseWorker = null;
        KdbxLoadService.workerBusy = false;
      }
      if (callback?.onAllErrors) {
        callback.onAllErrors(err);
      }
    }

    // 注册onexit回调，当Worker销毁时被调用，在宿主线程执行
    // 常驻模式下仅在异常退出 / 显式 stopWorker（应用恢复重置）时触发
    w.onexit = (e: number) => {
      hilog.info(DOMAIN, TAG, 'Database load worker exit: %{public}d', e);
      // 陈旧 Worker 迟到退出不清空新一代 Worker 的在途状态；
      // 当前 Worker 消亡则置空引用供下次操作重建，释放忙标志（在途任务兜底）
      if (KdbxLoadService.databaseWorker === w) {
        KdbxLoadService.databaseWorker = null;
        KdbxLoadService.workerBusy = false;
      }
      if (callback?.onexit) {
        callback.onexit(e);
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
    // 预热须对调用方透明：快照并在创建后恢复，保证后续加载任务的强制刷新语义；
    // 复用已有 Worker 时不重挂处理器（保留上一任务回调的 onexit/onAllErrors 送达语义，
    // PREWARM_RESULT 扇出对任务回调与默认挂载均有效）
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
  private static handleLoadMessage(data: WorkerMessage, callback?: KdbxLoadServiceCallback) {
    const loadMessage = data as LoadMessage;
    hilog.debug(DOMAIN, TAG, 'Received loading message:  %{public}s', ResourceManager.getMessage(loadMessage.message));
    if (callback?.onLoadMessage) {
      callback.onLoadMessage(loadMessage);
    }
  }

  /**
   * 处理来自线程的传输进度消息（下载字节进度，纯数据不含文案）
   * @param data 进度消息
   * @param onProgressMessage 进度回调
   */
  private static handleProgressMessage(data: WorkerMessage, callback?: KdbxLoadServiceCallback) {
    const progressMessage = data as ProgressMessage;
    if (callback?.onProgressMessage) {
      callback.onProgressMessage(progressMessage);
    }
  }

  /**
   * 处理来自线程的成功消息
   * @param data
   * @param onSuccessMessage
   */
  private static handleSuccessMessage(data: WorkerMessage, callback?: KdbxLoadServiceCallback) {
    const successMessage = data as SuccessMessage;
    hilog.info(DOMAIN, TAG, 'Received success message: modifiedTime:%{public}d, isMerge:%{public}s', successMessage.modifiedTime,
      successMessage.isMerge);
    if (callback?.onSuccessMessage) {
      callback.onSuccessMessage(successMessage);
    }
  }

  /**
   * 处理来自线程的错误消息
   * @param data
   * @param onErrorMessage
   */
  private static handleErrorMessage(data: WorkerMessage, callback?: KdbxLoadServiceCallback) {
    let errorMessage = data as LoadMessage;
    hilog.error(DOMAIN, TAG, 'Received error message: %{public}s', errorMessage.message);
    if (callback?.onErrorMessage) {
      callback.onErrorMessage(errorMessage);
    }
  }


  /**
   * 终止 Worker。
   * 常驻池化下不再被业务例行调用，仅供单测 / 紧急清理 /
   * 应用恢复（Ability 重建）时重置 Worker 池使用；在途 onexit 兜底释放忙标志。
   */
  public static stopWorker() {
    // 终止 Worker（回调不在此清空：任务回调经闭包绑定在 Worker 的处理器上，
    // 由 onexit 送达回调——与旧闭包语义一致，任务完成后 stopWorker 仍能触发 onexit）
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
   * 传输进度消息（下载字节进度，限频后 ≥500ms/条；存储不支持进度时不会触发）
   */
  onProgressMessage?: (message: ProgressMessage) => void;

  /**
   * 加载成功消息
   */
  onSuccessMessage?: (message: SuccessMessage) => void;

  /**
   * 加载错误消息
   */
  onErrorMessage?: (message: LoadMessage) => void;
}
