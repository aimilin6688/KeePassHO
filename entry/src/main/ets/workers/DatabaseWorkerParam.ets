import { StorageConfig, StorageType } from "../services/kdbx/interfaces";
import { AuthTypeInfo } from "../services/TypeDefined";

/**
 * 定义消息类型
 */

export enum MessageType {
  /**
   * 加载数据库
   */
  LOAD_DATABASE = 'LOAD_DATABASE',
  /**
   * 加载消息
   */
  LOAD_MESSAGE = 'LOAD_MESSAGE',
  /**
   * 加载成功
   */
  SUCCESS = 'SUCCESS',
  LOAD_SUCCESS = "LOAD_SUCCESS"
}

// 定义消息
export interface WorkerMessage {
  type: MessageType;
}

// 定义数据库加载请求
export interface LoadDatabase extends WorkerMessage {
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
  message: string;
}

// 成功消息
export interface SuccessMessage extends WorkerMessage {
  data: ArrayBuffer;
}


export function toLoadMessage(message: string): LoadMessage {
  return {
    type: MessageType.LOAD_MESSAGE,
    message
  }
}