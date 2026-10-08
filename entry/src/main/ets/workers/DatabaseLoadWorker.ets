import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { Kdbx } from 'kdbxweb';
import { LoadDatabase } from './DatabaseLoadWorkerParam';
import { CacheConstants } from '../storage/cache/CacheConstants';
import { CommonUtils, KdbxUtils } from '../common/utils';
import { AttachmentCacheService } from '../services/kdbx/AttachmentCacheService';
import { SessionFileService } from '../services/kdbx/SessionFileService';
import { FileInfo } from '../storage';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LoadMessage, InitWorkerMessage, MessageType, PrewarmMessage, PrewarmResultMessage, SuccessMessage, toErrorMessage, toLoadMessage, WorkerMessage } from './WorkerParam';
import { DatabaseLoad } from './DatabaseLoad';

const DOMAIN = 0x0000;
const TAG = 'DatabaseLoadWorker';
// 初始化 worker
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// 常驻壳任务串行链（Worker 常驻池化 #3）：常驻 isolate 复用后消息不再被
// "每操作重建" 隔断，两条任务消息可能先后到达同一 isolate；
// 以 Promise 链串联任务执行，防消息交错（与主线程 busy 拒绝双保险）
let taskChain: Promise<void> = Promise.resolve();

/**
 * 每任务缓存策略：任务消息附带非 undefined 策略字段时覆盖 INIT 快照
 * （常驻模式下 INIT 快照过期）；旧格式消息（无策略字段）保持 INIT 快照不变
 */
function applyTaskCachePolicy(carrier: LoadDatabase): void {
  if (carrier.enableLocalCache === undefined && carrier.onlyUseCache === undefined
    && carrier.forceRefresh === undefined) {
    return;
  }
  CacheConstants.setWorkerCachePolicy(carrier.enableLocalCache ?? CacheConstants.isEnableLocalCache(),
    carrier.onlyUseCache ?? CacheConstants.getOnlyCache(), carrier.forceRefresh ?? false);
}

// 监听主线程消息（仅 worker 线程注册；主线程加载本模块时 workerPort 为空，跳过）
if (workerPort) {
  workerPort.onmessage = (event: MessageEvents) => {
    const message = JSON.parse(event.data) as WorkerMessage;
    hilog.debug(DOMAIN, TAG, 'Load worker receive message type:%{public}s', message.type);
    if (message.type === MessageType.INIT_WORKER) {
      // 注入主线程沙箱路径与缓存策略快照：Worker 线程无 Context/AppStorage/preferences
      const init = message as InitWorkerMessage;
      CommonUtils.setWorkerPaths(init.filesDir, init.cacheDir);
      CacheConstants.setWorkerCachePolicy(init.enableLocalCache, init.onlyUseCache, init.forceRefresh);
      // 附件缓存密钥快照（S4 附件磁盘化）：Worker 线程无 Asset Kit 环境
      AttachmentCacheService.setWorkerKey(init.attachCacheKey);
      // §7.4：会话密钥/目录快照注入（isolate 静态不共享，M0 包裹需与主线程同密钥）
      SessionFileService.setWorkerSession(init.sessionKeyBase64, init.sessionDir);
      return;
    }
    if (message.type === MessageType.PREWARM) {
      // 预热：不走 taskChain（fire-and-forget，只读元数据操作），
      // 避免预热请求悬挂时阻塞后续真实加载任务；与加载任务共用同一存储实例（同配置复用连接）
      const prewarm = message as PrewarmMessage;
      new DatabaseLoadWorker().handlePrewarm(prewarm);
      return;
    }
    if (message.type === MessageType.LOAD_DATABASE) {
      const request = message as LoadDatabase;
      // 策略在任务实际执行前一刻生效（而非消息到达时），保证串行任务各自策略正确
      taskChain = taskChain.then(() => {
        applyTaskCachePolicy(request);
        return new DatabaseLoadWorker().handleLoadDatabase(request);
      }).catch((error: Error) => {
        // 兜底：handleLoadDatabase 正常不会 reject；此处向主线程回错，避免在途回调悬挂
        hilog.error(DOMAIN, TAG, 'Load task chain error: %{public}s', error?.message ?? 'unknown');
        try {
          workerPort.postMessage(toErrorMessage(error?.message ?? 'load failed'));
        } catch (postError) {
          hilog.error(DOMAIN, TAG, 'Post chain error failed: %{public}s', postError.message);
        }
      });
    }
  };
}

/**
 * 处理数据库加载任务
 * @param request 请求
 */
export class DatabaseLoadWorker extends DatabaseLoad {
  /**
   * Worker 运输模式启用 M0 v3 直传容器：解密解压后不建模型，
   * 原始 XML + 头部 + 池引用经 SFW1 流式包裹直传，主线程只解析一次
   * （非 v4+ChaCha20 由基类回退全模型 KPSN 路径）
   */
  protected useContainerTransport(): boolean {
    return true;
  }

  /**
   * 预热：在 Worker isolate 内完成存储模块图初始化 + rcp session/TLS 建立，
   * 并以 getInfoOrNull 探测大小回传主线程（写入加载调度缓存）。
   * 失败无害（fire-and-forget，仅日志），不占用 busy 状态
   * @param request 预热请求（仅元数据，无凭证）
   */
  async handlePrewarm(request: PrewarmMessage): Promise<void> {
    const tStart: number = Date.now();
    const result: PrewarmResultMessage = new PrewarmResultMessage(request.filePath);
    try {
      const manager: KdbxFileManager = new KdbxFileManager(request.storageType, request.storageConfig);
      const info: FileInfo | null = await manager.getInfoOrNull(request.filePath);
      if (info !== null) {
        result.size = info.size;
        result.version = info.version ?? null;
      }
    } catch (error) {
      result.error = (error as Error).message;
    }
    hilog.info(DOMAIN, TAG, 'prewarm done: file=%{public}s size=%{public}d error=%{public}s, %{public}d ms',
      request.filePath, result.size ?? -1, result.error ?? 'none', Date.now() - tStart);
    try {
      workerPort.postMessage(result);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'postPrewarmResult error:%{public}s', error.message);
    }
  }

  /**
   * 发送加载消息
   * @param message 消息
   */
  postMessage(message: string | Resource, onLoadMessage?: (message: LoadMessage) => void) {
    try {
      workerPort.postMessage(toLoadMessage(message));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'postMessage error:%{public}s', error.message);
      this.postErrorMessage(error.message);
    }
  }

  /**
   * 发送失败消息
   * @param message 消息（原始文本或资源 ID，由主线程本地化）
   */
  postErrorMessage(message: string | number, onErrorMessage?: (message: LoadMessage) => void) {
    try {
      workerPort.postMessage(toErrorMessage(message));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'postErrorMessage error:%{public}s', error.message);
      if (onErrorMessage) {
        onErrorMessage(toErrorMessage(error.message));
      } else {
        CommonUtils.showToast(error.message);
      }
    }

  }

  /**
   * 发送成功消息
   * v3 直传快路径：m0Path 已由基类设置（SFW1 流式容器，data 为空缓冲），直接投递；
   * v1/v2 全模型路径（回退/合并）：模型序列化字节经会话密钥包裹落盘 M0 文件，仅传路径跨线程；
   * 大缓冲不再随消息驻留线程队列（KPSN ArrayBuffer 跨线程协议退役）
   * @param message 消息
   */
  async postSuccessMessage(message: SuccessMessage, onSuccessMessage?: (message: SuccessMessage) => void) {
    try {
      if (message.data instanceof Kdbx) {
        let logTime = Date.now();
        const snapshotBytes: ArrayBuffer = await KdbxUtils.kdbxToArrayBuffer(message.data as Kdbx);
        message.m0Path = await SessionFileService.wrapToFile(snapshotBytes, 'm0_load_');
        message.data = new ArrayBuffer(0);
        hilog.info(DOMAIN, TAG, "Kdbx to m0 session file time: %{public}d ms", Date.now() - logTime);
      }
      workerPort.postMessage(message);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'postSuccessMessage error:%{public}s', error.message);
      this.postErrorMessage(error.message);
    }
  }
}


