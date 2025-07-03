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
  authType?: AuthTypeInfo;
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
  
  /**
   * 国际化资源key
   */
  i18nKey: string;
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
    description: '仅密码',
    i18nKey: 'auth_type_password'
  };
  
  /**
   * 使用密码和密钥文件认证
   */
  public static readonly PASSWORD_KEYFILE: AuthTypeInfo = {
    type: 'password_keyfile',
    description: '密码和密钥文件',
    i18nKey: 'auth_type_password_keyfile'
  };
  
  /**
   * 获取所有认证方式
   */
  public static getAllTypes(): AuthTypeInfo[] {
    return [
      AuthType.PASSWORD,
      AuthType.PASSWORD_KEYFILE
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