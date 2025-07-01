import { Kdbx } from 'kdbxweb';

/**
 * kdbx文件定义
 */
export interface FileParam {
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
}

/**
 * kdbx文件定义
 */
export interface DbFileParam {
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
   * 已解密的数据库对象
   */
  database: Kdbx;
}