import { Sm4Utils } from '../../common/utils/Sm4Utils'
import { StorageConfig, PageConfig, ChildDbScheme, ChildDbUrlKind } from '../StorageConfig'
import { StorageType } from '../StorageType'

/**
 * pCloud 存储配置类
 * accessToken 使用 Sm4Utils 加密存储
 */
export class PCloudStorageConfig implements StorageConfig {
  private static readonly DEFAULT_API_BASE_URL: string = 'https://api.pcloud.com'

  private _accessToken: string = ''
  private _expireAt: number = 0
  private _lastActiveAt: number = Date.now()
  private _timeout: number = 30000
  private _apiBaseUrl: string = PCloudStorageConfig.DEFAULT_API_BASE_URL

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
   * pCloud API 基地址
   * 官方要求登录后所有 API 调用必须使用 OAuth 回调返回的 hostname 对应端点：
   * US 数据中心: https://api.pcloud.com（默认）
   * EU 数据中心: https://eapi.pcloud.com（回调 hostname=eapi.pcloud.com 时由 PCloudPage 写入）
   */
  get apiBaseUrl(): string {
    return this._apiBaseUrl
  }

  set apiBaseUrl(val: string) {
    this._apiBaseUrl = val
  }

  /**
   * 检查 Token 是否已过期
   * pCloud 官方 OAuth2 不返回 expires_in，access_token 长期有效直至用户撤销；
   * expireAt 为 0 表示无过期时间（视为未过期），非 0 仅来自历史遗留数据
   */
  isTokenExpired(): boolean {
    if (this._expireAt === 0) {
      return false
    }
    return Date.now() >= this._expireAt
  }

  /**
   * 更新活跃时间（每次成功 API 调用后调用）
   * 仅用于本地会话管理记录，pCloud token 不存在"活跃自动延长"机制
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
  storageType: StorageType.PCLOUD,
  // M6 子库 scheme 声明（PATH 文法）；OAuth 型不声明 rebuilder——令牌不进 kdbx
  childDbSchemes: [new ChildDbScheme('pcloud', ChildDbUrlKind.PATH)]
}
