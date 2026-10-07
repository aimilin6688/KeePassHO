import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { Kdbx } from 'kdbxweb';
import { LoadDatabase } from './DatabaseLoadWorkerParam';
import { CacheConstants } from '../storage/cache/CacheConstants';
import { CommonUtils, KdbxUtils } from '../common/utils';
import { AttachmentCacheService } from '../services/kdbx/AttachmentCacheService';
import { SessionFileService } from '../services/kdbx/SessionFileService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LoadMessage, InitWorkerMessage, MessageType, SuccessMessage, toErrorMessage, toLoadMessage, WorkerMessage } from './WorkerParam';
import { DatabaseLoad } from './DatabaseLoad';

const DOMAIN = 0x0000;
const TAG = 'DatabaseLoadWorker';
// 初始化 worker
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

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
    if (message.type === MessageType.LOAD_DATABASE) {
      const request = message as LoadDatabase;
      new DatabaseLoadWorker().handleLoadDatabase(request);
    }
  };
}

/**
 * 处理数据库加载任务
 * @param request 请求
 */
export class DatabaseLoadWorker extends DatabaseLoad {
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
   * §7.4：模型序列化字节经会话密钥包裹落盘 M0 文件，仅传路径跨线程；
   * 大缓冲不再随消息驻留线程队列（KPSN ArrayBuffer 跨线程协议退役）
   * @param message 消息
   */
  async postSuccessMessage(message: SuccessMessage, onSuccessMessage?: (message: SuccessMessage) => void) {
    try {
      let logTime = Date.now();
      const snapshotBytes: ArrayBuffer = await KdbxUtils.kdbxToArrayBuffer(message.data as Kdbx);
      message.m0Path = await SessionFileService.wrapToFile(snapshotBytes, 'm0_load_');
      message.data = new ArrayBuffer(0);
      hilog.info(DOMAIN, TAG, "Kdbx to m0 session file time: %{public}d ms", Date.now() - logTime);
      workerPort.postMessage(message);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'postSuccessMessage error:%{public}s', error.message);
      this.postErrorMessage(error.message);
    }
  }
}


