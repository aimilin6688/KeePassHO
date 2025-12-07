import { ProtectedValue } from 'kdbxweb';
import { PageConfig, StorageConfig } from '../StorageConfig';

/**
 * WebDAV存储配置选项类
 */
export interface WebDAVStorageConfigOptions {
  rootPath?: string;
  timeout?: number;
}

/**
 * WebDAV存储配置类
 */
export class WebDAVStorageConfig implements StorageConfig {
  /**
   * 服务器URL
   */
  url: string;
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

  constructor(url: string, username: string, password: string, options?: WebDAVStorageConfigOptions, isProtected?: boolean) {
    this.url = url;
    if (!isProtected) {
      this.username = ProtectedValue.fromString(username).toBase64();
      this.password = ProtectedValue.fromString(password).toBase64();
    } else {
      this.username = username;
      this.password = password;
    }
    this.rootPath = options?.rootPath;
    this.timeout = options?.timeout;
  }

  public getUserNameText(): string {
    return ProtectedValue.fromBase64(this.username).getText();
  }

  public getPasswordText(): string {
    return ProtectedValue.fromBase64(this.password).getText();
  }

  public static getText(value: string): string {
    return ProtectedValue.fromBase64(value).getText();
  }
}

/**
 * WebDAV页面配置类
 */
export const WebDAVPageConfig = {
  icon: $r("app.media.ic_webdav"),
  title: $r('app.string.webdav_button_title'),
  selectDesc: $r('app.string.location_webdav_desc_select'),
  saveDesc: $r('app.string.location_webdav_desc_save'),
  pageUrl: 'storage/webdav/WebDAVPage',
} as PageConfig;