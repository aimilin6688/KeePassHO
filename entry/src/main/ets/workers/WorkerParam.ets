/**
 * 定义消息类型
 */

export enum MessageType {
  /**
   * 加载数据库
   */
  LOAD_DATABASE = 'LOAD_DATABASE',
  /**
   * 保存数据库
   */
  SAVE_DATABASE = 'SAVE_DATABASE',
  /**
   * 加载消息
   */
  MESSAGE = 'MESSAGE',
  /**
   * 加载成功
   */
  SUCCESS = "SUCCESS",

  /**
   * 加载失败
   */
  ERROR = "ERROR",
}

// 定义消息
export interface WorkerMessage {
  type: MessageType;
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