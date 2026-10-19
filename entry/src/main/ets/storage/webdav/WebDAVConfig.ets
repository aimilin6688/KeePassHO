import { ChildDbRebuildArgs, ChildDbScheme, ChildDbSupport, ChildDbUrlKind, ChildTarget,
  IocCredentials } from '../ChildDbSupport';
import { PageConfig, StorageConfig } from '../StorageConfig';
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
 * WebDAV 子库支持适配器（ChildDbSupport 端口，M6.9）：
 * URL 文法（webdav(s) 升格 https、http(s) 直连）；统一解析链②由条目
 * Ioc 凭据 + URL origin 重建 Config；写侧提取 username/password 加密字段。
 */
export class WebDAVChildDbSupport implements ChildDbSupport {
  readonly schemes: ChildDbScheme[] = [
    new ChildDbScheme('webdav', ChildDbUrlKind.URL, 'https'),
    new ChildDbScheme('webdavs', ChildDbUrlKind.URL, 'https'),
    new ChildDbScheme('http', ChildDbUrlKind.URL),
    new ChildDbScheme('https', ChildDbUrlKind.URL)
  ];

  /** 统一解析链②（Ioc 凭据 + URL origin → WebDAVStorageConfig）：
   *  filePath 为完整 http(s) URL，请求按绝对 URL 发出，config.url 取 origin 即可 */
  readonly rebuildConfig = (args: ChildDbRebuildArgs, target: ChildTarget): StorageConfig | undefined => {
    if (args.iocUserName.length === 0) {
      return undefined;
    }
    const origin: string = UrlUtils.getHost(target.filePath);
    if (origin.length === 0) {
      return undefined;
    }
    return new WebDAVStorageConfig(origin, args.iocUserName, args.iocPassword);
  };

  /** 写侧：从 storageConfig 解密提取连接凭据（类实例与 plain JSON 同名字段） */
  readonly extractCredentials = (config: StorageConfig): IocCredentials | undefined =>
    IocCredentials.fromEncryptedFields(config, 'username', 'password');
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
  // M6.9 子库支持适配器（URL 文法；凭据型：链②重建 + 写侧凭据提取）
  childDb: new WebDAVChildDbSupport()
} as PageConfig;