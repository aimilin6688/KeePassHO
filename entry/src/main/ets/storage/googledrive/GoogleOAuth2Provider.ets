import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BaseOAuth2Provider } from '../oauth2/BaseOAuth2Provider';
import { OAuth2Config, OAuth2Token, OAuth2UserInfo } from '../oauth2/OAuth2Types';
import { OAuth2Error, OAuth2ErrorCodes } from '../oauth2/OAuth2Error';

const DOMAIN = 0x0000;
const TAG = 'GoogleOAuth2Provider';

/**
 * Google OAuth2 配置
 */
export interface GoogleOAuth2Config extends OAuth2Config {
  /**
   * Google API基础URL
   */
  apiBaseUrl?: string;
}

/**
 * Google OAuth2 提供者实现
 */
export class GoogleOAuth2Provider extends BaseOAuth2Provider {
  /**
   * Google API基础URL
   */
  private readonly apiBaseUrl: string;

  /**
   * 构造函数
   * @param config OAuth2配置
   */
  constructor(config: GoogleOAuth2Config) {
    super(config);
    this.apiBaseUrl = config.apiBaseUrl || 'https://www.googleapis.com';
  }

  /**
   * 获取提供者名称
   * @return string 提供者名称
   */
  public getProviderName(): string {
    return 'Google';
  }

  /**
   * 获取用户信息
   * @param accessToken 访问令牌
   * @return Promise<OAuth2UserInfo> 用户信息
   * @throws 如果获取用户信息失败则抛出异常
   */
  public async getUserInfo(accessToken: string): Promise<OAuth2UserInfo> {
    if (!accessToken || accessToken.trim().length === 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.INVALID_PARAMETERS, 'Access token is required');
    }

    try {
      const response = await this.sendHttpRequestWithAuth(this.getUserInfoEndpoint(), http.RequestMethod.GET, accessToken);
      return this.parseUserInfo(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Get user info failed: %{public}s', (error as Error).message);
      throw new OAuth2Error(OAuth2ErrorCodes.USER_INFO_FETCH_FAILED, (error as Error).message);
    }
  }

  /**
   * 获取用户信息端点URL
   * @return string 用户信息端点URL
   */
  protected getUserInfoEndpoint(): string {
    return `${this.apiBaseUrl}/oauth2/v2/userinfo`;
  }

  /**
   * 获取撤销令牌的URL
   * @return string | undefined 撤销URL
   */
  protected getRevokeUrl(): string | undefined {
    return 'https://oauth2.googleapis.com/revoke';
  }

  /**
   * 发送带有认证的HTTP请求
   * @param url 请求URL
   * @param method 请求方法
   * @param accessToken 访问令牌
   * @return Promise<Record<string, Object>> 响应数据
   * @throws 如果请求失败则抛出异常
   */
  private async sendHttpRequestWithAuth(url: string, method: http.RequestMethod, accessToken: string):
    Promise<Record<string, Object>> {
    const httpRequest = http.createHttp();

    try {
      const options: http.HttpRequestOptions = {
        method: method,
        connectTimeout: this.requestTimeout,
        readTimeout: this.requestTimeout,
        header: {
          'Authorization': `Bearer ${accessToken}`
        }
      };

      const response = await httpRequest.request(url, options);
      const responseCode = response.responseCode as number;

      if (responseCode >= 200 && responseCode < 300) {
        const result = response.result;
        if (typeof result === 'string') {
          return JSON.parse(result);
        }
        return result as Record<string, Object>;
      } else if (responseCode === 401) {
        throw new OAuth2Error(OAuth2ErrorCodes.TOKEN_INVALID, 'Invalid access token');
      } else if (responseCode === 403) {
        throw new OAuth2Error(OAuth2ErrorCodes.ACCESS_DENIED, 'Access forbidden');
      } else {
        throw new Error(`HTTP ${responseCode}: ${response.result}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'HTTP request with auth failed: %{public}s', (error as Error).message);
      throw new Error((error as Error).message);
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 解析用户信息
   * @param response 响应数据
   * @return OAuth2UserInfo 用户信息
   */
  private parseUserInfo(response: Record<string, Object>): OAuth2UserInfo {
    const userId = this.extractStringFromObject(response, 'id');
    const userName = this.extractStringFromObject(response, 'email');
    const email = this.extractOptionalStringFromObject(response, 'email');
    const name = this.extractOptionalStringFromObject(response, 'name');
    const givenName = this.extractOptionalStringFromObject(response, 'given_name');
    const familyName = this.extractOptionalStringFromObject(response, 'family_name');
    const picture = this.extractOptionalStringFromObject(response, 'picture');
    const locale = this.extractOptionalStringFromObject(response, 'locale');

    if (!userId || !userName) {
      throw new OAuth2Error(OAuth2ErrorCodes.USER_INFO_FETCH_FAILED, 'Invalid user info response');
    }

    const userInfo: OAuth2UserInfo = {
      userId: userId,
      userName: userName,
      email: email,
      avatarUrl: picture,
      extraInfo: {}
    };

    if (name) {
      userInfo.extraInfo!['name'] = name;
    }
    if (givenName) {
      userInfo.extraInfo!['given_name'] = givenName;
    }
    if (familyName) {
      userInfo.extraInfo!['family_name'] = familyName;
    }
    if (locale) {
      userInfo.extraInfo!['locale'] = locale;
    }

    return userInfo;
  }
}

/**
 * 创建Google OAuth2配置的工厂方法
 * @param clientId 客户端ID
 * @param clientSecret 客户端密钥
 * @param redirectUri 重定向URI
 * @param scope 授权作用域
 * @return GoogleOAuth2Config Google OAuth2配置
 */
export function createGoogleOAuth2Config(
  clientId: string,
  clientSecret: string,
  redirectUri: string,
  scope?: string
): GoogleOAuth2Config {
  return {
    clientId: clientId,
    clientSecret: clientSecret,
    authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenEndpoint: 'https://oauth2.googleapis.com/token',
    redirectUri: redirectUri,
    scope: scope || 'openid email profile',
    apiBaseUrl: 'https://www.googleapis.com'
  };
}
