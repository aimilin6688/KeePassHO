import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MessageType, SuccessMessage, toErrorMessage, toLoadMessage, WorkerMessage } from './WorkerParam';
import { SaveDatabaseMessage } from './DatabaseSaveWorkerParam';
import { DatabaseSave } from './DatabaseSave';
import { SaveDatabaseCallback } from './callback/SaveDatabaseCallback';

const DOMAIN = 0x0000;
const TAG = 'DatabaseSaveWorker';
// 初始化 worker
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// 监听主线程消息
workerPort.onmessage = (event: MessageEvents) => {
  const message = event.data as WorkerMessage;
  hilog.debug(DOMAIN, TAG, 'Save worker receive message type:%{public}s', message.type);
  if (message.type === MessageType.SAVE_DATABASE) {
    const request = message as SaveDatabaseMessage;
    new DatabaseSaveWorker().handleSaveDatabase(request);
  }
};

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
    workerPort.postMessage(toLoadMessage(message));
  }

  /**
   * 发送加载消息
   * @param message 消息
   */
  postErrorMessage(message: string) {
    workerPort.postMessage(toErrorMessage(message));
  }

  /**
   * 发送成功消息
   * @param message
   */
  postSuccessMessage(message: SuccessMessage) {
    workerPort.postMessage(message);
  }
}




