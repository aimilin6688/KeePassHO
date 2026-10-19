import { ChildDbCredentialKeys, ChildDbRebuildArgs, ChildDbScheme, ChildDbUrlKind, ChildTarget,
  PageConfig, StorageConfig } from '../StorageConfig';
import { Sm4Utils } from '../../common/utils/Sm4Utils';
import { UrlUtils } from '../../common/utils/UrlUtils';
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

  constructor(url: string, username: string, password: string, options?: WebDAVStorageConfigOptions) {
    this.url = url;
    this.username = Sm4Utils.encryptWithPrefix(username);
    this.password = Sm4Utils.encryptWithPrefix(password);
    this.rootPath = options?.rootPath;
    this.timeout = options?.timeout;
    this.certValidationMode = options?.certValidationMode;
    this.customCaCertContent = options?.customCaCertContent;
  }

  public getUserNameText(): string {
    return Sm4Utils.decryptWithPrefix(this.username);
  }

  public getPasswordText(): string {
    return Sm4Utils.decryptWithPrefix(this.password);
  }
}

/**
 * 子库打开时 storageConfig 重建（PageConfig.childDbConfigRebuilder 契约，M6.3）：
 * Ioc 凭据 + URL origin → WebDAVStorageConfig
 * （filePath 为完整 http(s) URL，请求按绝对 URL 发出，config.url 取 origin 即可）
 */
export function webdavChildDbConfigRebuilder(args: ChildDbRebuildArgs,
  target: ChildTarget): StorageConfig | undefined {
  if (args.iocUserName.length === 0) {
    return undefined;
  }
  const origin: string = UrlUtils.getHost(target.filePath);
  if (origin.length === 0) {
    return undefined;
  }
  return new WebDAVStorageConfig(origin, args.iocUserName, args.iocPassword);
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
  // M6 子库 scheme 声明（URL 文法）：webdav(s) 升格 https；http(s) 直连
  childDbSchemes: [
    new ChildDbScheme('webdav', ChildDbUrlKind.URL, 'https'),
    new ChildDbScheme('webdavs', ChildDbUrlKind.URL, 'https'),
    new ChildDbScheme('http', ChildDbUrlKind.URL),
    new ChildDbScheme('https', ChildDbUrlKind.URL)
  ],
  childDbCredentialKeys: new ChildDbCredentialKeys('username', 'password'),
  childDbConfigRebuilder: webdavChildDbConfigRebuilder
} as PageConfig;