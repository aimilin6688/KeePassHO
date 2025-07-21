import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { Kdbx, KdbxCredentials } from 'kdbxweb';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { LoadDatabase, MessageType, SuccessMessage, toErrorMessage, toLoadMessage, WorkerMessage } from './DatabaseWorkerParam';
import KdbxUtils from '../common/utils/KdbxUtils';
import { CredentialsService } from '../services/CredentialsService';
import ResourceManager from '../common/utils/ResourceManager';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'DatabaseWorker';
// 初始化 worker
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// 监听主线程消息
workerPort.onmessage = (event: MessageEvents) => {
  hilog.info(DOMAIN, TAG, 'Worker receive message: %s', event.data)
  const message = JSON.parse(event.data) as WorkerMessage;
  if (message.type === MessageType.LOAD_DATABASE) {
    const request = message as LoadDatabase;
    handleLoadDatabase(request);
  }
};

/**
 * 处理数据库加载任务
 * @param request 请求
 */
async function handleLoadDatabase(request: LoadDatabase) {
  try {
    postMessage($r('app.string.creating_key'));
    // 创建凭证
    let credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
    postMessage($r('app.string.loading_key'));
    // 加载文件内容
    let fileContent: ArrayBuffer = await loadKdbxFileContent(request);
    postMessage($r('app.string.validating'));
    // 尝试加载数据库（仅验证，不保留结果）
    let kdbx: Kdbx = await Kdbx.load(fileContent, credentials);
    let kdbxContent = await KdbxUtils.kdbxToArrayBuffer(kdbx);
    postMessage($r('app.string.loading_complete'));
    workerPort.postMessage(new SuccessMessage(kdbxContent), [kdbxContent]);
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'Worker error loading database:%s, stack: %s', error.message, error.stack);
    postErrorMessage(error.message);
  }
}

/**
 * 加载文件内容
 * @param request 请求
 * @return Promise<ArrayBuffer> 文件内容
 */
async function loadKdbxFileContent(request: LoadDatabase): Promise<ArrayBuffer> {
  if (!request.filePath) {
    throw new Error(ResourceManager.getInstance().getString($r('app.string.select_database_file')));
  }
  let result = await new KdbxFileManager(request.storageType).loadKdbxFile(request.filePath);
  postMessage($r('app.string.load_file_success'));
  return result;
}

/**
 * 发送加载消息给主线程
 * @param message 消息
 */
function postMessage(message: string|Resource) {
  workerPort.postMessage(toLoadMessage(message));
}

/**
 * 发送加载消息给主线程
 * @param message 消息
 */
function postErrorMessage(message: string) {
  workerPort.postMessage(toErrorMessage(message));
}


