import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConflictMessage, InitWorkerMessage, ProgressMessage, MessageType, SuccessMessage, toErrorMessage, toLoadMessage, WorkerMessage } from './WorkerParam';
import { SaveDatabaseMessage } from './DatabaseSaveWorkerParam';
import { DatabaseSave } from './DatabaseSave';
import { SaveDatabaseCallback } from './callback/SaveDatabaseCallback';
import { CacheConstants } from '../storage/cache/CacheConstants';
import { CommonUtils } from '../common/utils';
import { AttachmentCacheService } from '../services/kdbx/AttachmentCacheService';
import { SessionFileService } from '../services/kdbx/SessionFileService';

const DOMAIN = 0x0000;
const TAG = 'DatabaseSaveWorker';
// 初始化 worker
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// 常驻壳任务串行链（Worker 常驻池化 #3）：常驻 isolate 复用后消息不再被
// "每操作重建" 隔断，两条任务消息可能先后到达同一 isolate；
// 以 Promise 链串联任务执行，防消息交错（与主线程 saveLock 互斥链双保险）
let taskChain: Promise<void> = Promise.resolve();

/**
 * 每任务缓存策略：任务消息附带非 undefined 策略字段时覆盖 INIT 快照
 * （常驻模式下 INIT 快照过期）；旧格式消息（无策略字段）保持 INIT 快照不变
 */
function applyTaskCachePolicy(carrier: SaveDatabaseMessage): void {
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
    const message = event.data as WorkerMessage;
    hilog.debug(DOMAIN, TAG, 'Save worker receive message type:%{public}s', message.type);
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
    if (message.type === MessageType.SAVE_DATABASE) {
      const request = message as SaveDatabaseMessage;
      // 策略在任务实际执行前一刻生效（而非消息到达时），保证串行任务各自策略正确
      taskChain = taskChain.then(() => {
        applyTaskCachePolicy(request);
        return new DatabaseSaveWorker().handleSaveDatabase(request);
      }).catch((error: Error) => {
        // 兜底：向主线程回错释放保存互斥锁，避免 saveLock 永久排队
        hilog.error(DOMAIN, TAG, 'Save task chain error: %{public}s', error?.message ?? 'unknown');
        try {
          workerPort.postMessage(toErrorMessage(error?.message ?? 'save failed'));
        } catch (postError) {
          hilog.error(DOMAIN, TAG, 'Post chain error failed: %{public}s', postError.message);
        }
      });
    }
  };
}

/**
 * 保存数据库
 */
class DatabaseSaveWorker extends DatabaseSave {
  constructor(callback?: SaveDatabaseCallback) {
    super(callback);
  }

  /**
   * 发送加载消息
   * @param message 消息
   */
  postMessage(message: string | Resource) {
    try {
      workerPort.postMessage(toLoadMessage(message));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'postMessage error:%{public}s', error.message);
      this.postErrorMessage(error.message);
    }
  }

  /**
   * 发送传输进度消息
   * @param message 进度消息（纯数据，主线程不本地化）
   */
  postProgressMessage(message: ProgressMessage) {
    try {
      workerPort.postMessage(message);
    } catch (error) {
      // 进度消息发送失败仅记录：进度是附属信息，不得中断保存流程
      hilog.error(DOMAIN, TAG, 'postProgressMessage error:%{public}s', error.message);
    }
  }

  /**
   * 发送失败消息
   * @param message 消息（原始文本或资源 ID，由主线程本地化）
   * @param detail 错误明细（原始错误文本，由主线程拼接在本地化前缀后展示）
   */
  postErrorMessage(message: string | number, detail?: string) {
    try {
      workerPort.postMessage(toErrorMessage(message, detail));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'postErrorMessage error:%{public}s', error.message);
      CommonUtils.showToast(String(message));
    }
  }

  /**
   * 发送成功消息
   * @param message
   */
  postSuccessMessage(message: SuccessMessage) {
    try {
      // §7.4：合并模型走 M0 会话文件（仅路径跨线程）；data 为空缓冲或回退路径落盘字节
      workerPort.postMessage(message);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'postSuccessMessage error:%{public}s', error.message);
      this.postErrorMessage(error.message);
    }
  }

  /**
   * 发送冲突消息
   * @param message 冲突信息
   */
  postConflictMessage(message: ConflictMessage) {
    try {
      workerPort.postMessage(message);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'postConflictMessage error:%{public}s', error.message);
      this.postErrorMessage(error.message);
    }
  }
}




