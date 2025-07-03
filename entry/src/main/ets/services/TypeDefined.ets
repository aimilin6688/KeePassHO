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
   * 文件名
   */
  fileName: string;

  /**
   * 文件内容
   */
  fileContent: ArrayBuffer;
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

  /**
   * 认证密码文件路径
   */
  keyFilePath?: string;

  /**
   * 认证方式
   */
  authType?:AuthType;
}

/**
 * 认证方式
 */
export enum AuthType{
  PASSWORD = 'password',
  PASSWORD_KEYFILE = 'password_keyfile'
}