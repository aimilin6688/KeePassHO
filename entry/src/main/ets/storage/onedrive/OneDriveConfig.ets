import { PageConfig, StorageConfig } from '../StorageConfig';
import { Sm4Utils } from '../../common/utils/Sm4Utils';

/**
 * OneDrive存储配置类
 */
export class OneDriveStorageConfig implements StorageConfig {
  /**
   * 访问令牌, 加密后的Base64字符串
   */
  accessToken: string;
  /**
   * 刷新令牌, 加密后的Base64字符串
   */
  refreshToken: string;
  /**
   * 超时时间（毫秒，可选）
   */
  timeout?: number;
  /**
   * 令牌过期时间（时间戳）
   */
  expiresAt?: number;

  constructor(
    accessToken: string,
    refreshToken: string,
    timeout?: number,
    expiresAt?: number
  ) {
    this.accessToken = Sm4Utils.encryptWithPrefix(accessToken);
    this.refreshToken = Sm4Utils.encryptWithPrefix(refreshToken);
    this.timeout = timeout;
    this.expiresAt = expiresAt;
  }

  /**
   * 获取访问令牌文本
   * @returns 访问令牌
   */
  public getAccessTokenText(): string {
    return Sm4Utils.decryptWithPrefix(this.accessToken);
  }

  /**
   * 获取刷新令牌文本
   * @returns 刷新令牌
   */
  public getRefreshTokenText(): string {
    return Sm4Utils.decryptWithPrefix(this.refreshToken);
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
 * OneDrive页面配置类
 */
export const OneDrivePageConfig: PageConfig = {
  icon: $r("app.media.ic_onedrive"),
  title: 'OneDrive',
  selectDesc: 'Select a file from OneDrive',
  saveDesc: 'Save the file to OneDrive',
  pageUrl: 'storage/onedrive/OneDrivePage',
};
