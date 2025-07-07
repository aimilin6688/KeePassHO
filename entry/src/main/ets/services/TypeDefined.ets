import { Kdbx, KdbxGroup } from 'kdbxweb';
import { StorageType } from './kdbx/interfaces';

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

  /**
   * 存储类型
   */
  storageType: StorageType;
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
   * 认证方式
   */
  authType: AuthTypeInfo;

  /**
   * 存储类型
   */
  storageType: StorageType;

  /**
   * 认证密码文件路径
   */
  keyFilePath?: string;
}

/**
 * 认证方式接口
 */
export interface AuthTypeInfo {
  /**
   * 认证方式的唯一标识
   */
  type: string;
  
  /**
   * 认证方式的描述，用于UI显示
   */
  description: string;
}

/**
 * 认证方式
 */
export class AuthType {
  /**
   * 仅使用密码认证
   */
  public static readonly PASSWORD: AuthTypeInfo = {
    type: 'password',
    description: '仅密码'
  };
  
  /**
   * 密码 + 密钥文件
   */
  public static readonly PASSWORD_KEYFILE: AuthTypeInfo = {
    type: 'password_keyfile',
    description: '密码 + 密钥文件'
  };
  
  /**
   * 密码 + 一次性密码
   */
  public static readonly PASSWORD_OTP: AuthTypeInfo = {
    type: 'password_otp',
    description: '密码 + 一次性密码'
  };
  
  /**
   * 密码 + 一次密码（恢复模式）
   */
  public static readonly PASSWORD_OTP_RECOVERY: AuthTypeInfo = {
    type: 'password_otp_recovery',
    description: '密码 + 一次性密码（恢复模式）'
  };
  
  /**
   * 密码 + 挑战-响应
   */
  public static readonly PASSWORD_CHALLENGE_RESPONSE: AuthTypeInfo = {
    type: 'password_challenge_response',
    description: '密码 + 挑战-响应'
  };
  
  /**
   * 密码 + 挑战-响应（恢复模式）
   */
  public static readonly PASSWORD_CHALLENGE_RESPONSE_RECOVERY: AuthTypeInfo = {
    type: 'password_challenge_response_recovery',
    description: '密码 + 挑战-响应（恢复模式）'
  };
  
  /**
   * 密码 + 挑战-应答（Keepass XC）
   */
  public static readonly PASSWORD_CHALLENGE_RESPONSE_XC: AuthTypeInfo = {
    type: 'password_challenge_response_xc',
    description: '密码 + 挑战-应答（Keepass XC）'
  };
  
  /**
   * 密码 + 密钥文件 + 挑战应答（Keepass XC）
   */
  public static readonly PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC: AuthTypeInfo = {
    type: 'password_keyfile_challenge_response_xc',
    description: '密码 + 密钥文件 + 挑战应答（Keepass XC）'
  };
  
  /**
   * 获取所有认证方式
   */
  public static getAllTypes(): AuthTypeInfo[] {
    return [
      AuthType.PASSWORD,
      AuthType.PASSWORD_KEYFILE,
      AuthType.PASSWORD_OTP,
      AuthType.PASSWORD_OTP_RECOVERY,
      AuthType.PASSWORD_CHALLENGE_RESPONSE,
      AuthType.PASSWORD_CHALLENGE_RESPONSE_RECOVERY,
      AuthType.PASSWORD_CHALLENGE_RESPONSE_XC,
      AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC
    ];
  }
  
  /**
   * 根据类型获取认证方式信息
   * @param type 认证方式类型
   * @returns 认证方式信息，如果未找到则返回null
   */
  public static getByType(type: string): AuthTypeInfo | null {
    return AuthType.getAllTypes().find(item => item.type === type) || null;
  }
}

/**
 * 最近打开文件定义
 */
export interface RecentFile {
  /**
   * 文件路径
   */
  filePath: string;

  /**
   * 文件名
   */
  fileName: string;

  /**
   * 存储类型
   */
  storageType: StorageType;
  
  /**
   * 认证方式
   */
  authType?: AuthTypeInfo;
  
  /**
   * 认证密钥文件路径
   */
  keyFilePath?: string;
}

/**
 * 数据库显示参数定义
 */
export interface DatabaseShowParam{
  groupId?: string;
}

/**
 * 数据库显示参数定义
 */
export interface EntryParam{
  groupId?: string;
  entryId?: string;
}