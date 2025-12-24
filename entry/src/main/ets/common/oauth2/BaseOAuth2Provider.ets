import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IOAuth2Provider } from './IOAuth2Provider';
import { OAuth2Config, OAuth2Token, OAuth2UserInfo, OAuth2AuthRequest, OAuth2RefreshRequest } from './OAuth2Types';
import { OAuth2Error, OAuth2ErrorCodes } from './OAuth2Error';

const DOMAIN = 0x0000;
const TAG = 'BaseOAuth2Provider';

/**
 * OAuth2 提供者抽象基类
 * 实现OAuth2认证的公共方法和逻辑
 */
export abstract class BaseOAuth2Provider implements IOAuth2Provider {
  /**
   * OAuth2配置
   */
  protected config: OAuth2Config;

  /**
   * HTTP请求超时时间（毫秒）
   */
  protected requestTimeout: number = 30000;

  /**
   * 构造函数
   * @param config OAuth2配置
   */
  constructor(config: OAuth2Config) {
    this.config = config;
  }

  /**
   * 获取授权URL
   * @return string 授权URL
   */
  public getAuthorizationUrl(): string {
    const params: string[] = [];
    params.push(`client_id=${encodeURIComponent(this.config.clientId)}`);
    params.push(`redirect_uri=${encodeURIComponent(this.config.redirectUri)}`);
    params.push(`response_type=code`);

    if (this.config.scope) {
      params.push(`scope=${encodeURIComponent(this.config.scope)}`);
    }

    if (this.config.state) {
      params.push(`state=${encodeURIComponent(this.config.state)}`);
    }

    if (this.config.authExtraParams) {
      const entries = Object.entries(this.config.authExtraParams);
      for (let i = 0; i < entries.length; i++) {
        const key = entries[i][0];
        const value = entries[i][1];
        params.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
      }
    }

    const separator = this.config.authorizationEndpoint.includes('?') ? '&' : '?';
    return `${this.config.authorizationEndpoint}${separator}${params.join('&')}`;
  }

  /**
   * 使用授权码获取访问令牌
   * @param authRequest 授权请求
   * @return Promise<OAuth2Token> 访问令牌
   * @throws 如果获取令牌失败则抛出异常
   */
  public async authorize(authRequest: OAuth2AuthRequest): Promise<OAuth2Token> {
    if (!authRequest.code || authRequest.code.trim().length === 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.INVALID_PARAMETERS, 'Authorization code is required');
    }

    if (this.config.state && authRequest.state !== this.config.state) {
      throw new OAuth2Error(OAuth2ErrorCodes.STATE_MISMATCH, 'State mismatch, possible CSRF attack');
    }

    const requestBody: Record<string, string> = {};
    requestBody['grant_type'] = 'authorization_code';
    requestBody['code'] = authRequest.code;
    requestBody['redirect_uri'] = this.config.redirectUri;
    requestBody['client_id'] = this.config.clientId;
    requestBody['client_secret'] = this.config.clientSecret;

    try {
      const response = await this.sendHttpRequest(this.config.tokenEndpoint, http.RequestMethod.POST, requestBody);
      return this.parseTokenResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Authorization failed: %{public}s', (error as Error).message);
      throw new OAuth2Error(OAuth2ErrorCodes.AUTHORIZATION_FAILED, (error as Error).message);
    }
  }

  /**
   * 使用刷新令牌获取新的访问令牌
   * @param refreshRequest 刷新令牌请求
   * @return Promise<OAuth2Token> 新的访问令牌
   * @throws 如果刷新令牌失败则抛出异常
   */
  public async refreshToken(refreshRequest: OAuth2RefreshRequest): Promise<OAuth2Token> {
    if (!refreshRequest.refreshToken || refreshRequest.refreshToken.trim().length === 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.INVALID_PARAMETERS, 'Refresh token is required');
    }

    const requestBody: Record<string, string> = {};
    requestBody['grant_type'] = 'refresh_token';
    requestBody['refresh_token'] = refreshRequest.refreshToken;
    requestBody['client_id'] = this.config.clientId;
    requestBody['client_secret'] = this.config.clientSecret;

    if (refreshRequest.scope) {
      requestBody.scope = refreshRequest.scope;
    }

    try {
      const response = await this.sendHttpRequest(this.config.tokenEndpoint, http.RequestMethod.POST, requestBody);
      return this.parseTokenResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Refresh token failed: %{public}s', (error as Error).message);
      throw new OAuth2Error(OAuth2ErrorCodes.TOKEN_REFRESH_FAILED, (error as Error).message);
    }
  }

  /**
   * 获取用户信息（由子类实现）
   * @param accessToken 访问令牌
   * @return Promise<OAuth2UserInfo> 用户信息
   * @throws 如果获取用户信息失败则抛出异常
   */
  public abstract getUserInfo(accessToken: string): Promise<OAuth2UserInfo>;

  /**
   * 撤销访问令牌
   * @param accessToken 访问令牌
   * @return Promise<void>
   * @throws 如果撤销令牌失败则抛出异常
   */
  public async revokeToken(accessToken: string): Promise<void> {
    const revokeUrl = this.getRevokeUrl();
    if (!revokeUrl) {
      hilog.warn(DOMAIN, TAG, 'Revoke URL not configured, token revocation skipped');
      return;
    }

    try {
      const requestBody: Record<string, string> = {};
      requestBody['token'] = accessToken;
      requestBody['client_id'] = this.config.clientId;
      requestBody['client_secret'] = this.config.clientSecret;
      await this.sendHttpRequest(revokeUrl, http.RequestMethod.POST, requestBody);
      hilog.info(DOMAIN, TAG, 'Token revoked successfully');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Revoke token failed: %{public}s', (error as Error).message);
      throw new OAuth2Error(OAuth2ErrorCodes.TOKEN_REVOKE_FAILED, (error as Error).message);
    }
  }

  /**
   * 验证令牌是否有效
   * @param token 令牌信息
   * @return Promise<boolean> 令牌是否有效
   */
  public async validateToken(token: OAuth2Token): Promise<boolean> {
    if (!token.accessToken || token.accessToken.trim().length === 0) {
      return false;
    }

    if (token.expiresAt && token.expiresAt < Date.now()) {
      return false;
    }

    try {
      await this.getUserInfo(token.accessToken);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * 获取提供者名称（由子类实现）
   * @return string 提供者名称
   */
  public abstract getProviderName(): string;

  /**
   * 获取提供者配置
   * @return OAuth2Config OAuth2配置
   */
  public getConfig(): OAuth2Config {
    return this.config;
  }

  /**
   * 设置提供者配置
   * @param config OAuth2配置
   */
  public setConfig(config: OAuth2Config): void {
    this.config = config;
  }

  /**
   * 发送HTTP请求
   * @param url 请求URL
   * @param method 请求方法
   * @param body 请求体
   * @return Promise<Record<string, Object>> 响应数据
   * @throws 如果请求失败则抛出异常
   */
  protected async sendHttpRequest(url: string, method: http.RequestMethod, body?: Record<string, string>):
    Promise<Record<string, Object>> {
    const httpRequest = http.createHttp();

    try {
      const options: http.HttpRequestOptions = {
        method: method,
        connectTimeout: this.requestTimeout,
        readTimeout: this.requestTimeout
      };

      if (body) {
        options.header = {
          'Content-Type': 'application/x-www-form-urlencoded'
        };
        options.extraData = this.urlEncode(body);
      }

      const response = await httpRequest.request(url, options);
      const responseCode = response.responseCode as number;

      if (responseCode >= 200 && responseCode < 300) {
        const result = response.result;
        if (typeof result === 'string') {
          return JSON.parse(result);
        }
        return result as Record<string, Object>;
      } else if (responseCode >= 400 && responseCode < 500) {
        throw new Error(`HTTP ${responseCode}: ${response.result}`);
      } else {
        throw new Error(`HTTP ${responseCode}: ${response.result}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'HTTP request failed: %{public}s', (error as Error).message);
      throw new OAuth2Error(OAuth2ErrorCodes.NETWORK_ERROR, (error as Error).message);
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 解析令牌响应
   * @param response 响应数据
   * @return OAuth2Token 令牌信息
   * @throws 如果解析失败则抛出异常
   */
  protected parseTokenResponse(response: Record<string, Object>): OAuth2Token {
    const accessToken = this.extractStringFromObject(response, 'access_token');
    const tokenType = this.extractStringFromObject(response, 'token_type', 'Bearer');
    const refreshToken = this.extractOptionalStringFromObject(response, 'refresh_token');
    const expiresIn = this.extractOptionalNumberFromObject(response, 'expires_in');
    const scope = this.extractOptionalStringFromObject(response, 'scope');

    if (!accessToken || accessToken.trim().length === 0) {
      const error = this.extractStringFromObject(response, 'error', 'Unknown error');
      const errorDescription = this.extractStringFromObject(response, 'error_description', '');
      throw new OAuth2Error(OAuth2ErrorCodes.TOKEN_FETCH_FAILED, `${error}: ${errorDescription}`);
    }

    const token: OAuth2Token = {
      accessToken: accessToken,
      tokenType: tokenType,
      refreshToken: refreshToken,
      scope: scope
    };

    if (expiresIn && expiresIn > 0) {
      token.expiresAt = Date.now() + expiresIn * 1000;
    }

    hilog.info(DOMAIN, TAG, 'Token obtained successfully, expires at: %{public}s', token.expiresAt);
    return token;
  }

  /**
   * URL编码对象
   * @param data 数据对象
   * @return string URL编码字符串
   */
  protected urlEncode(data: Record<string, string>): string {
    const pairs: string[] = [];
    const entries = Object.entries(data);
    for (let i = 0; i < entries.length; i++) {
      const key = entries[i][0];
      const value = entries[i][1];
      pairs.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    }
    return pairs.join('&');
  }

  /**
   * 从对象中提取字符串值
   * @param obj 对象
   * @param key 键
   * @param defaultValue 默认值
   * @return string 字符串值
   */
  protected extractStringFromObject(obj: Record<string, Object>, key: string, defaultValue: string = ''): string {
    const value = obj[key];
    if (value === undefined || value === null) {
      return defaultValue;
    }
    return String(value);
  }

  /**
   * 从对象中提取可选字符串值
   * @param obj 对象
   * @param key 键
   * @return string | undefined 字符串值
   */
  protected extractOptionalStringFromObject(obj: Record<string, Object>, key: string): string | undefined {
    const value = obj[key];
    if (value === undefined || value === null) {
      return undefined;
    }
    return String(value);
  }

  /**
   * 从对象中提取可选数字值
   * @param obj 对象
   * @param key 键
   * @return number | undefined 数字值
   */
  protected extractOptionalNumberFromObject(obj: Record<string, Object>, key: string): number | undefined {
    const value = obj[key];
    if (value === undefined || value === null) {
      return undefined;
    }
    const num = Number(value);
    return isNaN(num) ? undefined : num;
  }

  /**
   * 获取撤销令牌的URL（由子类重写）
   * @return string | undefined 撤销URL
   */
  protected getRevokeUrl(): string | undefined {
    return undefined;
  }

  /**
   * 获取用户信息端点URL（由子类实现）
   * @return string 用户信息端点URL
   */
  protected abstract getUserInfoEndpoint(): string;
}
