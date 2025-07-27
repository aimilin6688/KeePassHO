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