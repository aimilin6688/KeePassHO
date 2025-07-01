/**
 * kdbx文件定义
 */

export interface KdbxDbFile {
  /**
   * 文件路径
   */
  filePath: string;

  /**
   * 文件内容
   */
  fileContent: ArrayBuffer;

  /**
   * 文件名
   */
  fileName: string;

  /**
   * 密码
   */
  password?: string;
}