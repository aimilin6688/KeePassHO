import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConflictMessage, InitWorkerMessage, MessageType, SuccessMessage, toErrorMessage, toLoadMessage, WorkerMessage } from './WorkerParam';
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
      new DatabaseSaveWorker().handleSaveDatabase(request);
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
   * 发送失败消息
   * @param message 消息（原始文本或资源 ID，由主线程本地化）
   */
  postErrorMessage(message: string | number) {
    try {
      workerPort.postMessage(toErrorMessage(message));
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




