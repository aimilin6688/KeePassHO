import { PageConfig, StorageConfig } from '../StorageConfig';
import { Sm4Utils } from '../../common/utils/Sm4Utils';
import { WebDAVChildDbSupport } from './WebDAVChildDbSupport';
import { StorageType } from '..';

/**
 * SSL 证书验证模式
 */
export enum CertValidationMode {
  /** 使用系统 CA 验证（默认） */
  SYSTEM = 'system',
  /** 跳过证书验证（不安全） */
  SKIP = 'skip',
  /** 使用自定义 CA 证书 */
  CUSTOM_CA = 'custom_ca'
}

/**
 * WebDAV存储配置选项类
 */
export interface WebDAVStorageConfigOptions {
  rootPath?: string;
  timeout?: number;
  /** SSL 证书验证模式 */
  certValidationMode?: CertValidationMode;
  /** 自定义 CA 证书内容（PEM 格式） */
  customCaCertContent?: string;
  /** 自定义 User-Agent（条目 IocUserAgent 重建，可选） */
  userAgent?: string;
  /** 预先发送 Basic 认证（条目 IocPreAuth 重建，可选） */
  preAuth?: boolean;
  /** 上传请求体前协商 100-continue（条目 IocExpect100Continue 重建，可选） */
  expect100Continue?: boolean;
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
  /**
   * SSL 证书验证模式
   */
  certValidationMode?: CertValidationMode;
  /**
   * 自定义 CA 证书内容（PEM 格式）
   */
  customCaCertContent?: string;
  /**
   * 自定义 User-Agent（IocUserAgent）
   */
  userAgent?: string;
  /**
   * 预先发送 Basic 认证（IocPreAuth）
   */
  preAuth?: boolean;
  /**
   * 上传请求体前协商 100-continue（IocExpect100Continue）
   */
  expect100Continue?: boolean;

  constructor(url: string, username: string, password: string, options?: WebDAVStorageConfigOptions) {
    this.url = url;
    this.username = Sm4Utils.encryptWithPrefix(username);
    this.password = Sm4Utils.encryptWithPrefix(password);
    this.rootPath = options?.rootPath;
    this.timeout = options?.timeout;
    this.certValidationMode = options?.certValidationMode;
    this.customCaCertContent = options?.customCaCertContent;
    this.userAgent = options?.userAgent;
    this.preAuth = options?.preAuth;
    this.expect100Continue = options?.expect100Continue;
  }

  public getUserNameText(): string {
    return Sm4Utils.tryDecryptWithPrefix(this.username);
  }

  public getPasswordText(): string {
    return Sm4Utils.tryDecryptWithPrefix(this.password);
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
  storageType: StorageType.WEBDAV,
  childDb: new WebDAVChildDbSupport()
} as PageConfig;