import { PageConfig, StorageConfig } from '../StorageConfig';
import { PathChildDbSupport } from '../PathChildDbSupport';
import { Sm4Utils } from '../../common/utils/Sm4Utils';
import { StorageType } from '..';

export interface HuaweiDriveStorageConfigOptions {
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
 * 华为云盘存储配置类
 */
export class HuaweiDriveStorageConfig implements StorageConfig {
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
    options?: HuaweiDriveStorageConfigOptions
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
   * expiresAt 为 0/undefined 时视为已过期（保守策略，触发刷新，避免用过期 token 硬请求）
   * @returns 是否过期
   */
  public isTokenExpired(): boolean {
    if (!this.expiresAt) {
      return true;
    }
    // 提前5分钟认为令牌过期
    return Date.now() > this.expiresAt - 5 * 60 * 1000;
  }
}

/**
 * 华为云盘授权范围枚举
 */
export enum HuaweiDriveScope {
  /**
   * 完整访问云盘
   */
  FULL = 'openid https://www.huawei.com/auth/drive',

  /**
   * 仅访问应用文件
   */
  APP_FILE = 'openid https://www.huawei.com/auth/drive.file'
}

/**
 * 华为云盘页面配置类
 */
export const HuaweiDrivePageConfig: PageConfig = {
  icon: $r("app.media.ic_huawei_drive"),
  title: $r('app.string.huawei_drive_title'),
  selectDesc: $r('app.string.huawei_drive_select_file'),
  saveDesc: $r('app.string.huawei_drive_save_file'),
  pageUrl: 'storage/huawei/HuaweiDrivePage',
  storageType: StorageType.HUAWEI_DRIVE,
  childDb: new PathChildDbSupport(StorageType.HUAWEI_DRIVE, 'huawei-drive')
};
