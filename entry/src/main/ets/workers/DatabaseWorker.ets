import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { Kdbx, KdbxCredentials } from 'kdbxweb';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { LoadDatabase, MessageType, SuccessMessage, toErrorMessage, toLoadMessage, WorkerMessage } from './DatabaseWorkerParam';
import KdbxUtils from '../common/utils/KdbxUtils';
import { CredentialsService } from '../services/CredentialsService';

// 初始化 worker
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// 监听主线程消息
workerPort.onmessage = (event: MessageEvents) => {
  console.log('Worker receive message:', event.data)
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
    postMessage('创建密钥...');
    // 创建凭证
    let credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
    postMessage('加载密钥...');
    // 加载文件内容
    let fileContent: ArrayBuffer = await loadKdbxFileContent(request);
    postMessage('正在验证...');
    // 尝试加载数据库（仅验证，不保留结果）
    let kdbx: Kdbx = await Kdbx.load(fileContent, credentials);
    let kdbxContent = await KdbxUtils.kdbxToArrayBuffer(kdbx);
    postMessage('加载完成...');
    workerPort.postMessage(new SuccessMessage(kdbxContent), [kdbxContent]);
  } catch (error) {
    console.error('Worker error loading database:', error);
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
    throw new Error('请选择数据库文件');
  }
  let result = new KdbxFileManager(request.storageType).loadKdbxFile(request.filePath);
  postMessage("加载文件内容成功！");
  return result;
}

/**
 * 发送加载消息给主线程
 * @param message 消息
 */
function postMessage(message: string) {
  workerPort.postMessage(toLoadMessage(message));
}

/**
 * 发送加载消息给主线程
 * @param message 消息
 */
function postErrorMessage(message: string) {
  workerPort.postMessage(toErrorMessage(message));
}


