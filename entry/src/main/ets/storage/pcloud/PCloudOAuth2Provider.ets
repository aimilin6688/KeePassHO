import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BaseOAuth2Provider,
  OAuth2Config,
  OAuth2Token,
  OAuth2Error,
  OAuth2ErrorCodes,
  OAuth2UserInfo
} from '../../common/oauth2';

const DOMAIN = 0x0000;
const TAG = 'PCloudOAuth2Provider';

/**
 * pCloud OAuth2 配置
 */
export interface PCloudOAuth2Config extends OAuth2Config {
  /**
   * pCloud API基础URL
   */
  apiBaseUrl?: string;
}

/**
 * pCloud OAuth2 提供者实现
 *
 * 根据 pCloud 官方文档（https://docs.pcloud.com/methods/oauth_2.0/authorize.html）：
 *
 * 采用 Token Flow (Implicit) 认证方式：
 * 1. 授权 URL 使用 response_type=token
 * 2. 用户授权后，access_token 直接在回调 URL 的 fragment (#) 中返回
 * 3. 不需要 client_secret
 * 4. 不需要调用 oauth2_token 端点
 * 5. 回调 URL 格式：redirect_uri#access_token=XXXXX&token_type=bearer&uid=YYYYYY&state=ZZZZZZ&locationid=[1 or 2]&hostname=[api.pcloud.com or eapi.pcloud.com]
 *
 * Token Flow 适用于纯客户端应用（如移动设备应用）。
 */
export class PCloudOAuth2Provider extends BaseOAuth2Provider {
  private apiBaseUrl: string;

  constructor(config: PCloudOAuth2Config) {
    super(config);
    this.apiBaseUrl = config.apiBaseUrl || 'https://api.pcloud.com';
  }

  public getProviderName(): string {
    return 'PCloud';
  }

  protected getUserInfoEndpoint(): string {
    return `${this.apiBaseUrl}/userinfo`;
  }

  /**
   * 设置 API 基础 URL
   * 根据回调返回的 hostname 动态设置
   */
  public setApiBaseUrl(url: string): void {
    this.apiBaseUrl = url;
  }

  /**
   * 获取授权URL
   * Token Flow 使用 response_type=token
   */
  public getAuthorizationUrl(): string {
    const params: string[] = [];
    params.push(`client_id=${encodeURIComponent(this.config.clientId)}`);
    params.push(`response_type=token`);

    if (this.config.redirectUri) {
      params.push(`redirect_uri=${encodeURIComponent(this.config.redirectUri)}`);
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
   * 获取用户信息
   */
  public async getUserInfo(accessToken: string): Promise<OAuth2UserInfo> {
    if (!accessToken || accessToken.trim().length === 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.INVALID_PARAMETERS, 'Access token is required');
    }

    try {
      const url = `${this.getUserInfoEndpoint()}?access_token=${encodeURIComponent(accessToken)}`;
      const response = await this.sendHttpRequest(url, http.RequestMethod.GET);
      return this.parseUserInfo(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Get user info failed: %{public}s', (error as Error).message);
      throw new OAuth2Error(OAuth2ErrorCodes.USER_INFO_FETCH_FAILED, (error as Error).message);
    }
  }

  /**
   * 解析 pCloud 用户信息响应
   */
  private parseUserInfo(response: Record<string, Object>): OAuth2UserInfo {
    const resultValue = response['result'];
    if (resultValue !== undefined && typeof resultValue === 'number' && resultValue !== 0) {
      const error = this.extractStringFromObject(response, 'error', 'Unknown error');
      throw new OAuth2Error(OAuth2ErrorCodes.USER_INFO_FETCH_FAILED, `pCloud error ${resultValue}: ${error}`);
    }

    const email = this.extractOptionalStringFromObject(response, 'email');
    const uid = this.extractStringFromObject(response, 'uid');

    if (!uid) {
      throw new OAuth2Error(OAuth2ErrorCodes.USER_INFO_FETCH_FAILED, 'Invalid user info response');
    }

    const userInfo: OAuth2UserInfo = {
      userId: uid,
      userName: email || uid,
      email: email,
      extraInfo: {}
    };

    const plan = this.extractOptionalStringFromObject(response, 'plan');
    if (plan) {
      userInfo.extraInfo!['plan'] = plan;
    }

    return userInfo;
  }
}

/**
 * 创建 pCloud OAuth2 配置的工厂方法
 * Token Flow (Implicit) 不需要 client_secret
 */
export function createPCloudOAuth2Config(
  clientId: string,
  redirectUri: string,
  apiBaseUrl?: string
): PCloudOAuth2Config {
  const config: PCloudOAuth2Config = {
    clientId: clientId,
    clientSecret: '', // Token Flow 不需要 client_secret
    authorizationEndpoint: 'https://my.pcloud.com/oauth2/authorize',
    tokenEndpoint: '', // Token Flow 不需要 token endpoint
    redirectUri: redirectUri,
    scope: undefined,
    apiBaseUrl: apiBaseUrl || 'https://api.pcloud.com',
    isPublicClient: true
  };
  return config;
}
