import { ConflictMessage, SuccessMessage } from "../WorkerParam";

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

  /**
   * 检测到远端数据库已被其他设备修改，等待上层决定处理策略（合并/覆盖/重载）
   * @param message 冲突信息
   */
  onConflict?: (message: ConflictMessage) => void;
}
