import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BaseOAuth2Provider, OAuth2AuthRequest, OAuth2Config, OAuth2Error, OAuth2ErrorCodes, OAuth2RefreshRequest, OAuth2Token, OAuth2UserInfo } from '../../common/oauth2';
import { BaiduNetdiskConstants, BaiduNetdiskParser } from './BaiduNetdiskTypes';

const DOMAIN = 0x0000;
const TAG = 'BaiduNetdiskOAuth2Provider';

/**
 * 百度网盘 OAuth2 提供者实现
 * 百度 token 端点为 GET 查询参数风格（D9），覆写 authorize/refreshToken；
 * 用户信息走 xpan uinfo
 */
export class BaiduNetdiskOAuth2Provider extends BaseOAuth2Provider {

  constructor(config: OAuth2Config) {
    super(config);
  }

  /**
   * 获取提供者名称
   * @return string 提供者名称
   */
  public getProviderName(): string {
    return 'BaiduNetdisk';
  }

  /**
   * 使用授权码获取访问令牌（覆写：GET token 端点，D9）
   * @param authRequest 授权请求
   * @return Promise<OAuth2Token> 访问令牌
   */
  public async authorize(authRequest: OAuth2AuthRequest): Promise<OAuth2Token> {
    if (!authRequest.code || authRequest.code.trim().length === 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.INVALID_PARAMETERS, 'Authorization code is required');
    }
    if (this.config.state && authRequest.state !== this.config.state) {
      throw new OAuth2Error(OAuth2ErrorCodes.STATE_MISMATCH, 'State mismatch, possible CSRF attack');
    }
    const params: Record<string, string> = {
      'grant_type': 'authorization_code',
      'code': authRequest.code,
      'redirect_uri': this.config.redirectUri,
      'client_id': this.config.clientId,
      'client_secret': this.config.clientSecret
    };
    try {
      const response = await this.sendGetRequest(this.config.tokenEndpoint, params);
      return this.parseTokenResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Authorization failed: %{public}s', (error as Error).message);
      if (error instanceof OAuth2Error) {
        throw error;
      }
      throw new OAuth2Error(OAuth2ErrorCodes.AUTHORIZATION_FAILED, (error as Error).message);
    }
  }

  /**
   * 使用刷新令牌获取新的访问令牌（覆写：GET token 端点，D9）
   * 百度每次刷新返回新的 refresh_token，由 parseTokenResponse 提取、调用方负责落库
   * @param refreshRequest 刷新令牌请求
   * @return Promise<OAuth2Token> 新的令牌
   */
  public async refreshToken(refreshRequest: OAuth2RefreshRequest): Promise<OAuth2Token> {
    if (!refreshRequest.refreshToken || refreshRequest.refreshToken.trim().length === 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.INVALID_PARAMETERS, 'Refresh token is required');
    }
    const params: Record<string, string> = {
      'grant_type': 'refresh_token',
      'refresh_token': refreshRequest.refreshToken,
      'client_id': this.config.clientId,
      'client_secret': this.config.clientSecret
    };
    try {
      const response = await this.sendGetRequest(this.config.tokenEndpoint, params);
      return this.parseTokenResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Refresh token failed: %{public}s', (error as Error).message);
      if (error instanceof OAuth2Error) {
        throw error;
      }
      throw new OAuth2Error(OAuth2ErrorCodes.TOKEN_REFRESH_FAILED, (error as Error).message);
    }
  }

  /**
   * 获取用户信息（xpan uinfo）
   * @param accessToken 访问令牌
   * @return Promise<OAuth2UserInfo> 用户信息
   */
  public async getUserInfo(accessToken: string): Promise<OAuth2UserInfo> {
    if (!accessToken || accessToken.trim().length === 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.INVALID_PARAMETERS, 'Access token is required');
    }
    const params: Record<string, string> = {
      'method': 'uinfo',
      'access_token': accessToken
    };
    try {
      const response = await this.sendGetRequest(`${BaiduNetdiskConstants.PAN_BASE}/xpan/nas`, params);
      return this.parseUserInfo(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Get user info failed: %{public}s', (error as Error).message);
      if (error instanceof OAuth2Error) {
        throw error;
      }
      throw new OAuth2Error(OAuth2ErrorCodes.USER_INFO_FETCH_FAILED, (error as Error).message);
    }
  }

  /**
   * 获取用户信息端点URL
   * @return string 用户信息端点URL
   */
  protected getUserInfoEndpoint(): string {
    return `${BaiduNetdiskConstants.PAN_BASE}/xpan/nas?method=uinfo`;
  }

  /**
   * 获取撤销令牌的URL（百度无撤销端点）
   * @return string | undefined 撤销URL
   */
  protected getRevokeUrl(): string | undefined {
    return undefined;
  }

  /**
   * 发送 GET 查询参数请求（百度 token/uinfo 端点风格）
   * @param url 请求URL
   * @param params 查询参数
   * @return Promise<Record<string, Object>> 响应数据
   */
  private async sendGetRequest(url: string, params: Record<string, string>):
    Promise<Record<string, Object>> {
    const query = this.buildQuery(params);
    const requestUrl = query.length > 0 ? `${url}?${query}` : url;
    const httpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: this.requestTimeout,
        readTimeout: this.requestTimeout
      };
      const response = await httpRequest.request(requestUrl, options);
      const responseCode = response.responseCode as number;
      if (responseCode < 200 || responseCode >= 300) {
        throw new Error(`HTTP ${responseCode}: ${response.result}`);
      }
      const result = response.result;
      if (typeof result === 'string') {
        return JSON.parse(result);
      }
      return result as Record<string, Object>;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'GET request failed: %{public}s', (error as Error).message);
      throw new OAuth2Error(OAuth2ErrorCodes.NETWORK_ERROR, (error as Error).message);
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 拼装 URL 查询串（encodeURIComponent 编码）
   */
  private buildQuery(params: Record<string, string>): string {
    const pairs: string[] = [];
    const entries = Object.entries(params);
    for (let i = 0; i < entries.length; i++) {
      const key = entries[i][0];
      const value = entries[i][1];
      if (value === undefined || value === null) {
        continue;
      }
      pairs.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    }
    return pairs.join('&');
  }

  /**
   * 解析用户信息（uinfo 响应）
   * @param response 响应数据
   * @return OAuth2UserInfo 用户信息
   */
  private parseUserInfo(response: Record<string, Object>): OAuth2UserInfo {
    const errno = BaiduNetdiskParser.readNumber(response, 'errno');
    if (errno !== 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.USER_INFO_FETCH_FAILED,
        `uinfo errno=${errno}`);
    }
    const uk = BaiduNetdiskParser.readNumber(response, 'uk');
    const baiduName = BaiduNetdiskParser.readString(response, 'baidu_name');
    const netdiskName = BaiduNetdiskParser.readString(response, 'netdisk_name');
    const avatarUrl = BaiduNetdiskParser.readString(response, 'avatar_url');
    const vipType = BaiduNetdiskParser.readNumber(response, 'vip_type');
    if (uk === 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.USER_INFO_FETCH_FAILED, 'Invalid uinfo response');
    }
    const userInfo: OAuth2UserInfo = {
      userId: String(uk),
      userName: netdiskName || baiduName,
      avatarUrl: avatarUrl,
      extraInfo: {}
    };
    userInfo.extraInfo!['vipType'] = vipType;
    userInfo.extraInfo!['baiduName'] = baiduName;
    return userInfo;
  }
}

/**
 * 创建百度网盘 OAuth2 配置的工厂方法
 * @param clientId AppKey
 * @param clientSecret SecretKey
 * @param redirectUri 回调地址（主方案自定义 scheme；兜底方案传 oob）
 * @return OAuth2Config 百度 OAuth2 配置
 */
export function createBaiduNetdiskOAuth2Config(
  clientId: string,
  clientSecret: string,
  redirectUri: string
): OAuth2Config {
  return {
    clientId: clientId,
    clientSecret: clientSecret,
    authorizationEndpoint: 'https://openapi.baidu.com/oauth/2.0/authorize',
    tokenEndpoint: 'https://openapi.baidu.com/oauth/2.0/token',
    redirectUri: redirectUri,
    scope: 'basic,netdisk',
    authExtraParams: {
      'display': 'mobile'
    }
  } as OAuth2Config;
}
