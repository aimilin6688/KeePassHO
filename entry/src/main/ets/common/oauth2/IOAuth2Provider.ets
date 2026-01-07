import { OAuth2Config, OAuth2Token, OAuth2UserInfo, OAuth2AuthRequest, OAuth2RefreshRequest } from './OAuth2Types';

/**
 * OAuth2 提供者接口
 * 定义OAuth2认证的基本行为，支持不同的OAuth2服务提供商
 */
export interface IOAuth2Provider {
  /**
   * 获取授权URL
   * @return string 授权URL
   */
  getAuthorizationUrl(): string;

  /**
   * 使用授权码获取访问令牌
   * @param authRequest 授权请求
   * @return Promise<OAuth2Token> 访问令牌
   * @throws 如果获取令牌失败则抛出异常
   */
  authorize(authRequest: OAuth2AuthRequest): Promise<OAuth2Token>;

  /**
   * 使用刷新令牌获取新的访问令牌
   * @param refreshRequest 刷新令牌请求
   * @return Promise<OAuth2Token> 新的访问令牌
   * @throws 如果刷新令牌失败则抛出异常
   */
  refreshToken(refreshRequest: OAuth2RefreshRequest): Promise<OAuth2Token>;

  /**
   * 获取用户信息
   * @param accessToken 访问令牌
   * @return Promise<OAuth2UserInfo> 用户信息
   * @throws 如果获取用户信息失败则抛出异常
   */
  getUserInfo(accessToken: string): Promise<OAuth2UserInfo>;

  /**
   * 撤销访问令牌
   * @param accessToken 访问令牌
   * @return Promise<void>
   * @throws 如果撤销令牌失败则抛出异常
   */
  revokeToken(accessToken: string): Promise<void>;

  /**
   * 验证令牌是否有效
   * @param token 令牌信息
   * @return Promise<boolean> 令牌是否有效
   */
  validateToken(token: OAuth2Token): Promise<boolean>;

  /**
   * 获取提供者名称
   * @return string 提供者名称
   */
  getProviderName(): string;

  /**
   * 获取提供者配置
   * @return OAuth2Config OAuth2配置
   */
  getConfig(): OAuth2Config;

  /**
   * 设置提供者配置
   * @param config OAuth2配置
   */
  setConfig(config: OAuth2Config): void;
}
