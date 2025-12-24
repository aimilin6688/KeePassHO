/**
 * OAuth2 错误类
 */
export class OAuth2Error extends Error {
  public readonly code: string;

  constructor(code: string, message?: string) {
    super('OAuth2Error ' + code + (message ? ': ' + message : ''));

    this.name = 'OAuth2Error';
    this.code = code;
  }
}

/**
 * OAuth2 错误码
 */
export enum OAuth2ErrorCodes {
  /**
   * 配置错误
   */
  CONFIG_ERROR = 'CONFIG_ERROR',
  /**
   * 授权失败
   */
  AUTHORIZATION_FAILED = 'AUTHORIZATION_FAILED',
  /**
   * 令牌获取失败
   */
  TOKEN_FETCH_FAILED = 'TOKEN_FETCH_FAILED',
  /**
   * 令牌刷新失败
   */
  TOKEN_REFRESH_FAILED = 'TOKEN_REFRESH_FAILED',
  /**
   * 令牌无效
   */
  TOKEN_INVALID = 'TOKEN_INVALID',
  /**
   * 令牌过期
   */
  TOKEN_EXPIRED = 'TOKEN_EXPIRED',
  /**
   * 用户信息获取失败
   */
  USER_INFO_FETCH_FAILED = 'USER_INFO_FETCH_FAILED',
  /**
   * 令牌撤销失败
   */
  TOKEN_REVOKE_FAILED = 'TOKEN_REVOKE_FAILED',
  /**
   * 网络错误
   */
  NETWORK_ERROR = 'NETWORK_ERROR',
  /**
   * 提供者不支持
   */
  PROVIDER_NOT_SUPPORTED = 'PROVIDER_NOT_SUPPORTED',
  /**
   * 参数错误
   */
  INVALID_PARAMETERS = 'INVALID_PARAMETERS',
  /**
   * 状态校验失败
   */
  STATE_MISMATCH = 'STATE_MISMATCH',
  /**
   * 访问被拒绝
   */
  ACCESS_DENIED = 'ACCESS_DENIED'
}
