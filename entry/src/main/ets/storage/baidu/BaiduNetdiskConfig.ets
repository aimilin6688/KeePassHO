import { PageConfig, StorageConfig } from '../StorageConfig';
import { PathChildDbSupport } from '../PathChildDbSupport';
import { Sm4Utils } from '../../common/utils/Sm4Utils';
import { StorageType } from '..';

export interface BaiduNetdiskStorageConfigOptions {
  /**
   * 超时时间（毫秒，可选）
   */
  timeout?: number;
  /**
   * 令牌类型
   */
  tokenType?: string;
  /**
   * 作用域
   */
  scope?: string;
}

/**
 * 百度网盘存储配置类
 */
export class BaiduNetdiskStorageConfig implements StorageConfig {
  /**
   * 访问令牌, 加密后的Base64字符串
   */
  accessToken: string;
  /**
   * 刷新令牌, 加密后的Base64字符串
   */
  refreshToken: string;
  /**
   * 令牌过期时间（时间戳）
   */
  expiresAt: number;

  /**
   * 超时时间（毫秒，可选）
   */
  timeout?: number;
  /**
   * 令牌类型
   */
  tokenType?: string;
  /**
   * 作用域
   */
  scope?: string;

  constructor(
    accessToken: string,
    refreshToken: string,
    expiresAt: number,
    options?: BaiduNetdiskStorageConfigOptions
  ) {
    this.accessToken = Sm4Utils.encryptWithPrefix(accessToken);
    this.refreshToken = Sm4Utils.encryptWithPrefix(refreshToken);
    this.expiresAt = expiresAt;
    this.timeout = options?.timeout;
    this.tokenType = options?.tokenType;
    this.scope = options?.scope;
  }

  /**
   * 获取访问令牌文本
   * @returns 访问令牌
   */
  public getAccessTokenText(): string {
    return Sm4Utils.tryDecryptWithPrefix(this.accessToken);
  }

  /**
   * 获取刷新令牌文本
   * @returns 刷新令牌
   */
  public getRefreshTokenText(): string {
    return Sm4Utils.tryDecryptWithPrefix(this.refreshToken);
  }

  /**
   * 设置访问令牌
   * @param accessToken 访问令牌
   */
  public setAccessToken(accessToken: string): void {
    this.accessToken = Sm4Utils.encryptWithPrefix(accessToken);
  }

  /**
   * 设置刷新令牌
   * @param refreshToken 刷新令牌
   */
  public setRefreshToken(refreshToken: string): void {
    this.refreshToken = Sm4Utils.encryptWithPrefix(refreshToken);
  }

  /**
   * 设置令牌过期时间
   * @param expiresAt 过期时间（时间戳）
   */
  public setExpiresAt(expiresAt: number): void {
    this.expiresAt = expiresAt;
  }

  /**
   * 检查令牌是否过期
   * @returns 是否过期
   */
  public isTokenExpired(): boolean {
    if (!this.expiresAt) {
      return false;
    }
    // 提前5分钟认为令牌过期
    return Date.now() > this.expiresAt - 5 * 60 * 1000;
  }
}

/**
 * 百度网盘页面配置类
 */
export const BaiduNetdiskPageConfig: PageConfig = {
  icon: $r('app.media.ic_baidu'),
  title: '百度网盘',
  selectDesc: $r('app.string.baidu_netdisk_select_file'),
  saveDesc: $r('app.string.baidu_netdisk_save_file'),
  pageUrl: 'storage/baidu/BaiduNetdiskPage',
  storageType: StorageType.BAIDU_NETDISK,
  childDb: new PathChildDbSupport(StorageType.BAIDU_NETDISK, 'baidu')
};
