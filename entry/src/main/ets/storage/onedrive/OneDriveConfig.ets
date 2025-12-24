import { PageConfig, StorageConfig } from '../StorageConfig';
import { Sm4Utils } from '../../common/utils/Sm4Utils';

/**
 * OneDrive存储配置选项接口
 */
export interface OneDriveStorageConfigOptions {
  /**
   * 根路径（可选）
   */
  rootPath?: string;

  /**
   * 超时时间（毫秒，可选）
   */
  timeout?: number;
}

/**
 * OneDrive存储配置类
 */
export class OneDriveStorageConfig implements StorageConfig {
  /**
   * 客户端ID, 加密后的Base64字符串
   */
  clientId: string;
  /**
   * 客户端密钥, 加密后的Base64字符串
   */
  clientSecret: string;
  /**
   * 租户ID, 加密后的Base64字符串
   */
  tenantId: string;
  /**
   * 重定向URI, 加密后的Base64字符串
   */
  redirectUri: string;
  /**
   * 访问令牌, 加密后的Base64字符串
   */
  accessToken: string;
  /**
   * 刷新令牌, 加密后的Base64字符串
   */
  refreshToken: string;
  /**
   * 根路径（可选）
   */
  rootPath?: string;
  /**
   * 超时时间（毫秒，可选）
   */
  timeout?: number;
  /**
   * 令牌过期时间（时间戳）
   */
  expiresAt?: number;

  constructor(
    clientId: string,
    clientSecret: string,
    tenantId: string,
    redirectUri: string,
    accessToken: string,
    refreshToken: string,
    options?: OneDriveStorageConfigOptions
  ) {
    this.clientId = Sm4Utils.encryptWithPrefix(clientId);
    this.clientSecret = Sm4Utils.encryptWithPrefix(clientSecret);
    this.tenantId = Sm4Utils.encryptWithPrefix(tenantId);
    this.redirectUri = Sm4Utils.encryptWithPrefix(redirectUri);
    this.accessToken = Sm4Utils.encryptWithPrefix(accessToken);
    this.refreshToken = Sm4Utils.encryptWithPrefix(refreshToken);
    this.rootPath = options?.rootPath;
    this.timeout = options?.timeout;
  }

  /**
   * 获取客户端ID文本
   * @returns 客户端ID
   */
  public getClientIdText(): string {
    return Sm4Utils.decryptWithPrefix(this.clientId);
  }

  /**
   * 获取客户端密钥文本
   * @returns 客户端密钥
   */
  public getClientSecretText(): string {
    return Sm4Utils.decryptWithPrefix(this.clientSecret);
  }

  /**
   * 获取租户ID文本
   * @returns 租户ID
   */
  public getTenantIdText(): string {
    return Sm4Utils.decryptWithPrefix(this.tenantId);
  }

  /**
   * 获取重定向URI文本
   * @returns 重定向URI
   */
  public getRedirectUriText(): string {
    return Sm4Utils.decryptWithPrefix(this.redirectUri);
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
   * 获取令牌过期时间
   * @returns 过期时间
   */
  public getExpiresAt(): number | undefined {
    return this.expiresAt;
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
  icon: $r("app.media.C02_Warning"),
  title: 'OneDrive',
  selectDesc: 'Select a file from OneDrive',
  saveDesc: 'Save the file to OneDrive',
  pageUrl: 'storage/onedrive/OneDrivePage',
};
