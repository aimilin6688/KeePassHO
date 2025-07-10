import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { StorageType } from '../services/kdbx/interfaces';
import { AuthType, AuthTypeInfo } from '../services/TypeDefined';
import { StorageConfig } from '../services/kdbx/interfaces/StorageConfig';
import { FileService } from '../services/FileService';
import { RecentFilesService } from '../services/RecentFilesService';

/**
 * 定义消息类型
 */
export enum MessageType {
  /**
   * 加载数据库
   */
  LOAD_DATABASE,
  /**
   * 加载消息
   */
  LOAD_MESSAGE,
  /**
   * 加载成功
   */
  SUCCESS
}

// 定义消息
export interface WorkerMessage {
  type: MessageType;
}

// 定义数据库加载请求
export interface LoadDatabase extends WorkerMessage {
  type: MessageType.LOAD_DATABASE;

  /**
   * 文件路径
   */
  filePath: string;

  /**
   * 文件名
   */
  fileName: string;

  /**
   * 密码
   */
  password: string;

  /**
   * 认证方式
   */
  authType: AuthTypeInfo;

  /**
   * 认证密码文件路径
   */
  keyFilePath?: string;

  /**
   * 存储类型
   */
  storageType: StorageType;

  /**
   * 存储配置信息
   */
  storageConfig: StorageConfig;
}

// 定义数据库加载结果
export interface LoadMessage extends WorkerMessage {
  type: MessageType.LOAD_MESSAGE;
  message: string;
}

// 成功消息
export interface SuccessMessage extends WorkerMessage {
  type: MessageType.SUCCESS;
}

// 初始化 worker
const workerPort:ThreadWorkerGlobalScope = worker.workerPort;

// 监听主线程消息
workerPort.onmessage = (event: MessageEvents) => {
  const message: WorkerMessage = event.data;
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
    // 尝试加载数据库（仅验证，不保留结果）
    let kdbx: Kdbx = await Kdbx.load(fileContent, credentials);
    // 处理数据库文件
    await handlerDatabase(request, kdbx);
    postMessage({} as SuccessMessage);
  } catch (error) {
    console.error('Worker error loading database:', error);
    postMessage({ message: error.message } as LoadMessage)
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
    postMessage({ message: "加载密钥文件成功！" } as LoadMessage);
    credentials = new KdbxCredentials(ProtectedValue.fromString(request.password), keyFileContent);
  } else {
    // 仅使用密码
    credentials = new KdbxCredentials(ProtectedValue.fromString(request.password));
  }
  postMessage({ message: "创建认证方式成功！" } as LoadMessage);
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
  return new KdbxFileManager(request.storageType).loadKdbxFile(request.filePath);
}

/**
 * 发送消息给主线程
 * @param message 消息
 */
function postMessage(message: WorkerMessage) {
  workerPort.postMessage(message);
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

  // 添加到最近打开的文件列表，包含认证方式和认证文件信息
  RecentFilesService.getInstance().getRecentFile(request.filePath).then((recentFile) => {
    if (recentFile) {
      RecentFilesService.getInstance().addRecentFile({
        filePath: request.filePath,
        fileName: request.fileName,
        storageType: request.storageType,
        authType: request.authType,
        keyFilePath: request.keyFilePath,
        storageConfig: request.storageConfig
      });
    }
  })
}


