import { StorageConfig, StorageType } from '../services/kdbx/interfaces';
import { AuthTypeInfo, CredentialsParam } from '../services/TypeDefined';
import { MessageType, WorkerMessage } from './WorkerParam';

// 定义数据库加载请求
export class LoadDatabase implements WorkerMessage, CredentialsParam {
  type: MessageType;
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

  constructor(filePath: string, fileName: string, password: string, authType: AuthTypeInfo,
    keyFilePath?: string, storageType?: StorageType | null, storageConfig?: StorageConfig | null) {
    this.type = MessageType.LOAD_DATABASE;
    this.filePath = filePath;
    this.fileName = fileName;
    this.password = password;
    this.authType = authType;
    this.keyFilePath = keyFilePath;
    this.storageType = storageType ?? StorageType.LOCAL;
    this.storageConfig = storageConfig ?? {};
  }
}

// 定义数据库加载结果
export class LoadMessage implements WorkerMessage {
  type: MessageType;
  message: string | number;

  constructor(type: MessageType, message: string | number) {
    this.type = type;
    this.message = message;
  }
}

// 成功消息
export class SuccessMessage implements WorkerMessage {
  type: MessageType;
  data: ArrayBuffer;
  /**
   * 最后修改时间,单位为毫秒
   */
  modifiedTime: number;


  constructor(data: ArrayBuffer, modifiedTime: number) {
    this.type = MessageType.SUCCESS;
    this.data = data;
    this.modifiedTime = modifiedTime;
  }
}


export function toLoadMessage(message: string | Resource): LoadMessage {
  if (typeof message === 'string') {
    return new LoadMessage(MessageType.MESSAGE, message);
  }
  return new LoadMessage(MessageType.MESSAGE, message.id);
}

export function toErrorMessage(message: string): LoadMessage {
  return new LoadMessage(MessageType.ERROR, message);
}