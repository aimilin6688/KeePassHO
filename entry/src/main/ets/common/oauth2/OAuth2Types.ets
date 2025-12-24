/**
 * OAuth2 认证提供者类型
 */
export enum OAuth2Provider {
  /**
   * GitHub
   */
  GITHUB = 'GITHUB',
  /**
   * Google
   */
  GOOGLE = 'GOOGLE',
  /**
   * Microsoft OneDrive
   */
  ONEDRIVE = 'ONEDRIVE',
  /**
   * Dropbox
   */
  DROPBOX = 'DROPBOX'
}

/**
 * OAuth2 令牌信息
 */
export interface OAuth2Token {
  /**
   * 访问令牌
   */
  accessToken: string;
  /**
   * 令牌类型
   */
  tokenType: string;
  /**
   * 刷新令牌
   */
  refreshToken?: string;
  /**
   * 令牌过期时间（时间戳，毫秒）
   */
  expiresAt?: number;
  /**
   * 作用域
   */
  scope?: string;
  /**
   * 额外参数
   */
  extraParams?: Record<string, string>;
}

/**
 * OAuth2 配置接口
 */
export interface OAuth2Config {
  /**
   * 客户端ID
   */
  clientId: string;
  /**
   * 客户端密钥
   */
  clientSecret: string;
  /**
   * 授权端点URL
   */
  authorizationEndpoint: string;
  /**
   * 令牌端点URL
   */
  tokenEndpoint: string;
  /**
   * 重定向URI
   */
  redirectUri: string;
  /**
   * 授权作用域
   */
  scope?: string;
  /**
   * 状态参数（用于CSRF保护）
   */
  state?: string;
  /**
   * 额外授权参数
   */
  authExtraParams?: Record<string, string>;
}

/**
 * OAuth2 授权请求
 */
export interface OAuth2AuthRequest {
  /**
   * 授权码
   */
  code: string;
  /**
   * 状态参数
   */
  state: string;
}

/**
 * OAuth2 刷新令牌请求
 */
export interface OAuth2RefreshRequest {
  /**
   * 刷新令牌
   */
  refreshToken: string;
  /**
   * 作用域
   */
  scope?: string;
}

/**
 * OAuth2 响应基础接口
 */
export interface OAuth2Response {
  /**
   * 是否成功
   */
  success: boolean;
  /**
   * 错误消息
   */
  error?: string;
  /**
   * 错误描述
   */
  errorDescription?: string;
}

/**
 * OAuth2 授权响应
 */
export interface OAuth2AuthResponse extends OAuth2Response {
  /**
   * 令牌信息
   */
  token?: OAuth2Token;
}

/**
 * OAuth2 用户信息接口
 */
export interface OAuth2UserInfo {
  /**
   * 用户ID
   */
  userId: string;
  /**
   * 用户名
   */
  userName: string;
  /**
   * 邮箱
   */
  email?: string;
  /**
   * 头像URL
   */
  avatarUrl?: string;
  /**
   * 额外信息
   */
  extraInfo?: Record<string, Object>;
}

/**
 * OAuth2 存储配置
 */
export interface OAuth2StorageConfig {
  /**
   * OAuth2提供者
   */
  provider: OAuth2Provider;
  /**
   * OAuth2配置
   */
  oauth2Config: OAuth2Config;
}
