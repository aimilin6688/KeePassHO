import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { StorageType } from '../services/kdbx/interfaces';
import { AuthType } from '../services/TypeDefined';
import { LoadDatabase, MessageType, SuccessMessage, toLoadMessage, WorkerMessage } from './DatabaseWorkerParam';
import KdbxUtils from '../common/utils/KdbxUtils';

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
    // 创建凭证
    let credentials: KdbxCredentials = await createKdbxCredentials(request);
    // 加载文件内容
    let fileContent: ArrayBuffer = await loadKdbxFileContent(request);
    postMessage('正在解析...');
    // 尝试加载数据库（仅验证，不保留结果）
    let kdbx: Kdbx = await Kdbx.load(fileContent, credentials);
    postMessage('加载完成...');
    let kdbxContent = await KdbxUtils.kdbxToArrayBuffer(kdbx);
    workerPort.postMessage({ type: MessageType.LOAD_SUCCESS, data: kdbxContent } as SuccessMessage, [kdbxContent]);
  } catch (error) {
    console.error('Worker error loading database:', error);
    postMessage(error.message);
  }
}

/**
 * 创建凭证
 * @param request 请求
 * @return Promise<KdbxCredentials> 凭证
 */
async function createKdbxCredentials(request: LoadDatabase): Promise<KdbxCredentials> {
  // 创建凭证
  let credentials: KdbxCredentials;
  if (AuthType.useKeyAuth(request.authType)) {
    if (request.keyFilePath === undefined) {
      throw new Error('请选择密钥文件');
    }
    // 使用密码和密钥文件
    let keyFileContent = await new KdbxFileManager(StorageType.LOCAL).loadKdbxFile(request.keyFilePath);
    console.log('Load key file content success, keyFilePath: ', request.keyFilePath);
    postMessage('加载密钥文件成功！');
    credentials = new KdbxCredentials(ProtectedValue.fromString(request.password), keyFileContent);
  } else {
    // 仅使用密码
    credentials = new KdbxCredentials(ProtectedValue.fromString(request.password));
  }
  postMessage('创建凭证成功！');
  return Promise.resolve(credentials);
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
  workerPort.postMessage(JSON.stringify(toLoadMessage(message)));
}


