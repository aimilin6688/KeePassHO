import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { Kdbx } from 'kdbxweb';
import { LoadDatabase } from './DatabaseLoadWorkerParam';
import { CommonUtils, KdbxUtils } from '../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LoadMessage, MessageType, SuccessMessage, toErrorMessage, toLoadMessage, WorkerMessage } from './WorkerParam';
import { DatabaseLoad } from './DatabaseLoad';

const DOMAIN = 0x0000;
const TAG = 'DatabaseLoadWorker';
// 初始化 worker
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// 监听主线程消息
workerPort.onmessage = (event: MessageEvents) => {
  const message = JSON.parse(event.data) as WorkerMessage;
  hilog.debug(DOMAIN, TAG, 'Load worker receive message type:%{public}s', message.type);
  if (message.type === MessageType.LOAD_DATABASE) {
    const request = message as LoadDatabase;
    new DatabaseLoadWorker().handleLoadDatabase(request);
  }
};

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
   * @param message 消息
   */
  postErrorMessage(message: string, onErrorMessage?: (message: LoadMessage) => void) {
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
   * @param message 消息
   */
  async postSuccessMessage(message: SuccessMessage, onSuccessMessage?: (message: SuccessMessage) => void) {
    try {
      let logTime = Date.now();
      message.data = await KdbxUtils.kdbxToArrayBuffer(message.data as Kdbx);
      hilog.debug(DOMAIN, TAG, "Kdbx to array buffer time: %{public}d ms", Date.now() - logTime);
      workerPort.postMessage(message, [message.data]);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'postSuccessMessage error:%{public}s', error.message);
      this.postErrorMessage(error.message);
    }
  }
}


