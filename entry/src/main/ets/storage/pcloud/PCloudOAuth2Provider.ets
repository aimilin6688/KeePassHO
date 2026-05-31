import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BaseOAuth2Provider,
  OAuth2Config,
  OAuth2Token,
  OAuth2Error,
  OAuth2ErrorCodes,
  OAuth2UserInfo,
  OAuth2AuthRequest
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
 * 根据 pCloud 官方文档（https://docs.pcloud.com/methods/oauth_2.0/）：
 *
 * 与标准 OAuth2 的差异：
 * 1. oauth2_token 只需要 client_id、client_secret、code 三个参数
 *    - 不需要 grant_type
 *    - 不需要 redirect_uri
 * 2. 响应只返回 access_token、token_type、uid，带有 result 字段
 *    - 不返回 refresh_token
 *    - 不返回 expires_in
 * 3. 无标准 scope 参数（权限在应用控制台配置）
 * 4. redirect_uri 在 authorize 阶段是可选参数
 * 5. authorize 回调的 query 中还返回 locationid 和 hostname
 */
export class PCloudOAuth2Provider extends BaseOAuth2Provider {
  /**
   * pCloud API基础URL
   */
  private readonly apiBaseUrl: string;

  /**
   * 构造函数
   * @param config OAuth2配置
   */
  constructor(config: PCloudOAuth2Config) {
    super(config);
    this.apiBaseUrl = config.apiBaseUrl || 'https://api.pcloud.com';
  }

  /**
   * 获取提供者名称
   * @return string 提供者名称
   */
  public getProviderName(): string {
    return 'PCloud';
  }

  /**
   * 获取用户信息端点URL
   * @return string 用户信息端点URL
   */
  protected getUserInfoEndpoint(): string {
    return `${this.apiBaseUrl}/userinfo`;
  }

  /**
   * 使用授权码获取访问令牌
   *
   * pCloud 的 oauth2_token 端点只接受三个参数：
   * client_id、client_secret、code
   * 不需要 grant_type 和 redirect_uri
   *
   * @param authRequest 授权请求
   * @return Promise<OAuth2Token> 访问令牌
   */
  public async authorize(authRequest: OAuth2AuthRequest): Promise<OAuth2Token> {
    if (!authRequest.code || authRequest.code.trim().length === 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.INVALID_PARAMETERS, 'Authorization code is required');
    }

    // 验证 state 参数，防止 CSRF 攻击
    // 参考 pCloud 官方文档：state 参数在重定向时会原样返回
    if (this.config.state && authRequest.state !== this.config.state) {
      throw new OAuth2Error(OAuth2ErrorCodes.STATE_MISMATCH, 'State mismatch, possible CSRF attack');
    }

    // pCloud 的 oauth2_token 只需要 client_id、client_secret、code
    // 不需要 grant_type、redirect_uri
    const requestBody: Record<string, string> = {};
    requestBody['client_id'] = this.config.clientId;
    requestBody['client_secret'] = this.config.clientSecret;
    requestBody['code'] = authRequest.code;

    try {
      const response = await this.sendHttpRequest(
        this.config.tokenEndpoint,
        http.RequestMethod.POST,
        requestBody
      );
      return this.parsePCloudTokenResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Authorization failed: %{public}s', (error as Error).message);
      throw new OAuth2Error(OAuth2ErrorCodes.AUTHORIZATION_FAILED, (error as Error).message);
    }
  }

  /**
   * 解析 pCloud 令牌响应
   *
   * pCloud 响应格式：
   * { "result": 0, "access_token": "dghdghdj", "token_type": "bearer", "uid": 34535 }
   *
   * 与标准 OAuth2 的差异：
   * - 包含 result 字段（0 表示成功）
   * - 不包含 refresh_token
   * - 不包含 expires_in
   * - 不包含 scope
   * - 包含 uid（pCloud 用户 ID）
   *
   * @param response pCloud API 响应
   * @return OAuth2Token 令牌信息
   */
  private parsePCloudTokenResponse(response: Record<string, Object>): OAuth2Token {
    // 检查 result 字段
    const resultValue = response['result'];
    if (resultValue !== undefined && typeof resultValue === 'number' && resultValue !== 0) {
      const error = this.extractStringFromObject(response, 'error', 'Unknown error');
      throw new OAuth2Error(OAuth2ErrorCodes.TOKEN_FETCH_FAILED, `pCloud error ${resultValue}: ${error}`);
    }

    const accessToken = this.extractStringFromObject(response, 'access_token');
    const tokenType = this.extractStringFromObject(response, 'token_type', 'Bearer');

    if (!accessToken || accessToken.trim().length === 0) {
      throw new OAuth2Error(OAuth2ErrorCodes.TOKEN_FETCH_FAILED, 'No access_token in response');
    }

    const token: OAuth2Token = {
      accessToken: accessToken,
      tokenType: tokenType
    };

    hilog.info(DOMAIN, TAG, `Token obtained successfully`);
    return token;
  }

  /**
   * 获取用户信息
   * @param accessToken 访问令牌
   * @return Promise<OAuth2UserInfo> 用户信息
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
   * pCloud /userinfo 返回字段示例：
   * { "result": 0, "email": "user@example.com", "uid": 12345, "plan": "free" }
   */
  private parseUserInfo(response: Record<string, Object>): OAuth2UserInfo {
    // 检查 result 字段
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
 *
 * @param clientId 客户端ID
 * @param clientSecret 客户端密钥
 * @param redirectUri 重定向URI（pCloud 的 authorize 阶段可选，但建议提供）
 * @param apiBaseUrl pCloud API基础URL（可选，默认 https://api.pcloud.com）
 * @return PCloudOAuth2Config pCloud OAuth2配置
 */
export function createPCloudOAuth2Config(
  clientId: string,
  clientSecret: string,
  redirectUri: string,
  apiBaseUrl?: string
): PCloudOAuth2Config {
  return {
    clientId: clientId,
    clientSecret: clientSecret,
    authorizationEndpoint: 'https://my.pcloud.com/oauth2/authorize',
    tokenEndpoint: 'https://api.pcloud.com/oauth2_token',
    redirectUri: redirectUri,
    scope: undefined,
    apiBaseUrl: apiBaseUrl || 'https://api.pcloud.com'
  };
}
