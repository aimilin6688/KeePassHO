import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { Kdbx, KdbxCredentials } from 'kdbxweb';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { LoadDatabase } from './DatabaseLoadWorkerParam';
import KdbxUtils from '../common/utils/KdbxUtils';
import { CredentialsService } from '../services/CredentialsService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileContentInfo } from '../services/kdbx/interfaces';
import { MessageType, WorkerMessage, SuccessMessage, toErrorMessage, toLoadMessage } from './WorkerParam';

const DOMAIN = 0x0000;
const TAG = 'DatabaseLoadWorker';
// 初始化 worker
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;
let logTime:number = 0;

// 监听主线程消息
workerPort.onmessage = (event: MessageEvents) => {
  const message = JSON.parse(event.data) as WorkerMessage;
  hilog.debug(DOMAIN, TAG, 'Load worker receive message type:%{public}s', message.type);
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
    hilog.debug(DOMAIN, TAG, "LoadWorker 1: %{public}d", Date.now() - logTime, logTime = Date.now());
    // 创建凭证
    let credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
    postMessage($r('app.string.loading_key'));
    // 加载文件内容
    hilog.debug(DOMAIN, TAG, "LoadWorker 2: %{public}d", Date.now() - logTime, logTime = Date.now());
    let fileContent: FileContentInfo = await loadKdbxFileContent(request);
    postMessage($r('app.string.validating'));
    // 加载数据库
    hilog.debug(DOMAIN, TAG, "LoadWorker 3: %{public}d", Date.now() - logTime, logTime = Date.now());
    let kdbx: Kdbx = await Kdbx.load(fileContent.content, credentials);
    hilog.debug(DOMAIN, TAG, "LoadWorker 4: %{public}d", Date.now() - logTime, logTime = Date.now());
    let kdbxContent = await KdbxUtils.kdbxToArrayBuffer(kdbx);
    hilog.debug(DOMAIN, TAG, "LoadWorker 5: %{public}d", Date.now() - logTime, logTime = Date.now());
    postMessage($r('app.string.loading_complete'));
    workerPort.postMessage(new SuccessMessage(kdbxContent, fileContent.modifiedTime), [kdbxContent]);
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'Worker error loading database:%{public}s, stack:%{public}s', error.message, error.stack);
    postErrorMessage(error.message);
  }
}

/**
 * 加载文件内容
 * @param request 请求
 * @return Promise<ArrayBuffer> 文件内容
 */
async function loadKdbxFileContent(request: LoadDatabase): Promise<FileContentInfo> {
  if (!request.filePath) {
    hilog.error(DOMAIN, TAG, 'Worker error loading database: file path is empty');
    throw new Error();
  }
  let result = await new KdbxFileManager(request.storageType, request.storageConfig).loadKdbxFile(request.filePath);
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


