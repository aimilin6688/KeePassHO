import { SuccessMessage } from "../WorkerParam";

export interface SaveDatabaseCallback {
  /**
   * 保存成功
   */
  onSuccess?: (message: SuccessMessage) => void;

  /**
   * 保存失败
   * @param message 异常消息
   */
  onError?: (message: string) => void;

  /**
   * 过程消息
   * @param message
   */
  onMessage?: (message: string) => void;
}
