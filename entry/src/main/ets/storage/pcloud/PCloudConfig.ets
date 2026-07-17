import { Sm4Utils } from '../../common/utils/Sm4Utils'
import { StorageConfig, PageConfig } from '../StorageConfig'
import { StorageType } from '../StorageType'

/**
 * pCloud 存储配置类
 * accessToken 使用 Sm4Utils 加密存储
 */
export class PCloudStorageConfig implements StorageConfig {
  private _accessToken: string = ''
  private _expireAt: number = 0
  private _lastActiveAt: number = Date.now()
  private _timeout: number = 30000

  get accessToken(): string {
    return Sm4Utils.decryptWithPrefix(this._accessToken)
  }

  set accessToken(val: string) {
    this._accessToken = Sm4Utils.encryptWithPrefix(val)
  }

  get expireAt(): number {
    return this._expireAt
  }

  set expireAt(val: number) {
    this._expireAt = val
  }

  get lastActiveAt(): number {
    return this._lastActiveAt
  }

  set lastActiveAt(val: number) {
    this._lastActiveAt = val
  }

  get timeout(): number {
    return this._timeout
  }

  set timeout(val: number) {
    this._timeout = val
  }

  /**
   * 检查 Token 是否已过期
   * pCloud 的 access_token 有 expire 绝对过期时间
   */
  isTokenExpired(): boolean {
    if (this._expireAt === 0) {
      return false
    }
    return Date.now() >= this._expireAt
  }

  /**
   * 更新活跃时间（每次成功 API 调用后调用）
   * pCloud 持续使用 token 会自动延长 expire_inactive
   */
  touchActive(): void {
    this._lastActiveAt = Date.now()
  }
}

/**
 * pCloud 页面配置
 */
export const PCloudPageConfig: PageConfig = {
  icon: $r('app.media.ic_pcloud'),
  title: 'pCloud',
  selectDesc: $r('app.string.pcloud_select_desc'),
  saveDesc: $r('app.string.pcloud_save_desc'),
  pageUrl: 'storage/pcloud/PCloudPage',
  storageType: StorageType.PCLOUD
}
