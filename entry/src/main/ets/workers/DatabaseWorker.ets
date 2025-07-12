import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { StorageType } from '../services/kdbx/interfaces';
import { AuthType } from '../services/TypeDefined';
import { FileService } from '../services/FileService';
import { LoadDatabase, MessageType, toLoadMessage, toSuccessMessage, WorkerMessage } from './DatabaseWorkerParam';

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
    postLoadMessage('正在解析数据库文件...');
    // 尝试加载数据库（仅验证，不保留结果）
    let kdbx: Kdbx = await Kdbx.load(fileContent, credentials);
    // 处理数据库文件
    await handlerDatabase(request, kdbx);
    postMessage(toSuccessMessage());
  } catch (error) {
    console.error('Worker error loading database:', error);
    postLoadMessage(error.message);
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
    postLoadMessage('加载密钥文件成功！');
    credentials = new KdbxCredentials(ProtectedValue.fromString(request.password), keyFileContent);
  } else {
    // 仅使用密码
    credentials = new KdbxCredentials(ProtectedValue.fromString(request.password));
  }
  postLoadMessage('创建凭证成功！');
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
  postLoadMessage("加载文件内容成功！");
  return result;
}

/**
 * 发送加载消息给主线程
 * @param message 消息
 */
function postLoadMessage(message: string) {
  workerPort.postMessage(JSON.stringify(toLoadMessage(message)));
}

/**
 * 发送消息给主线程
 * @param message 消息
 */
function postMessage(message: WorkerMessage) {
  workerPort.postMessage(JSON.stringify(message));
}

/**
 * 处理数据库文件
 * @param request 请求
 * @param kdbx 数据
 */
async function handlerDatabase(request: LoadDatabase, kdbx: Kdbx) {
  // 设置数据库文件信息
  FileService.getInstance().setDbFileParam({
    filePath: request.filePath,
    password: request.password,
    fileName: request.fileName,
    database: kdbx,
    keyFilePath: request.keyFilePath, // 添加密钥文件路径，以便后续保存时使用
    authType: request.authType, // 添加认证类型
    storageType: request.storageType,
    storageConfig: request.storageConfig
  })
}


