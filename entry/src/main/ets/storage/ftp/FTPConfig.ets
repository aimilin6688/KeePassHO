import { ProtectedValue } from 'kdbxweb';
import { PageConfig, StorageConfig } from '../StorageConfig';
import { Sm4Utils } from '../../common/utils/Sm4Utils';

/**
 * FTP存储配置选项类
 */
export interface FTPStorageConfigOptions {
  rootPath?: string;
  timeout?: number;
  secure?: boolean | "implicit";
  port?: number;
}

/**
 * FTP存储配置类
 */
export class FTPStorageConfig implements StorageConfig {
  /**
   * 服务器地址
   */
  host: string;
  /**
   * 端口号，默认21
   */
  port: number;
  /**
   * 用户名, 加密后的Base64字符串
   */
  username: string;
  /**
   * 密码, 加密后的Base64字符串
   */
  password: string;
  /**
   * 根路径（可选）
   */
  rootPath?: string;
  /**
   * 超时时间（毫秒，可选）
   */
  timeout?: number;
  /**
   * 是否使用FTP over TLS (可选)
   */
  secure?: boolean | "implicit";

  constructor(host: string, username: string, password: string, options?: FTPStorageConfigOptions) {
    this.host = host;
    this.port = options?.port || 21;
    this.username = Sm4Utils.encryptWithPrefix(username);
    this.password = Sm4Utils.encryptWithPrefix(password);
    this.rootPath = options?.rootPath;
    this.timeout = options?.timeout || 30000;
    this.secure = options?.secure;
  }

  public getUserNameText(): string {
    return Sm4Utils.decryptWithPrefix(this.username);
  }

  public getPasswordText(): string {
    return Sm4Utils.decryptWithPrefix(this.password);
  }
}

/**
 * FTP页面配置类
 */
export const FTPPageConfig = {
  icon: $r("app.media.ic_ftp"),
  title: $r('app.string.ftp_button_title'),
  selectDesc: $r('app.string.location_ftp_desc_select'),
  saveDesc: $r('app.string.location_ftp_desc_save'),
  pageUrl: 'storage/ftp/FTPPage',
} as PageConfig;