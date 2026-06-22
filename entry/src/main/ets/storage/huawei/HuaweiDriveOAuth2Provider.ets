import { OAuth2Config, OAuth2Provider, OAuth2UserInfo } from '../../common/oauth2/OAuth2Types';
import { BaseOAuth2Provider } from '../../common/oauth2/BaseOAuth2Provider';
import BuildProfile from 'BuildProfile';

/**
 * 华为云盘OAuth2配置接口
 */
export interface HuaweiDriveOAuth2Config extends OAuth2Config {
  /**
   * 客户端ID
   */
  clientId: string;

  /**
   * 客户端密钥
   */
  clientSecret?: string;

  /**
   * 授权端点
   */
  authorizationEndpoint: string;

  /**
   * 令牌端点
   */
  tokenEndpoint: string;

  /**
   * 重定向URI
   */
  redirectUri: string;

  /**
   * 作用域
   */
  scope: string;
}

/**
 * 华为云盘OAuth2提供者
 */
export class HuaweiDriveOAuth2Provider extends BaseOAuth2Provider {
  /**
   * 构造函数
   * @param config OAuth2配置
   */
  constructor(config: HuaweiDriveOAuth2Config) {
    super(config);
  }

  /**
   * 获取华为云盘OAuth2配置
   * @param scope 授权范围
   * @returns HuaweiDriveOAuth2Config
   */
  public static getConfig(scope: string): HuaweiDriveOAuth2Config {
    return {
      provider: OAuth2Provider.HUAWEI_DRIVE,
      clientId: BuildProfile.HUAWEI_DRIVE_CLIENT_ID,
      clientSecret: BuildProfile.HUAWEI_DRIVE_CLIENT_SECRET,
      authorizationEndpoint: 'https://oauth-login.cloud.huawei.com/oauth2/v3/authorize',
      tokenEndpoint: 'https://oauth-login.cloud.huawei.com/oauth2/v3/token',
      redirectUri: BuildProfile.HUAWEI_DRIVE_REDIRECT_URI,
      scope: scope
    };
  }

  /**
   * 获取用户信息
   * @param accessToken 访问令牌
   * @returns Promise<OAuth2UserInfo> 用户信息
   */
  public async getUserInfo(accessToken: string): Promise<OAuth2UserInfo> {
    // 华为云盘API暂不提供用户信息接口，返回基本信息
    return {
      userId: 'huawei_drive_user',
      userName: 'Huawei Drive User'
    };
  }

  /**
   * 获取提供者名称
   * @returns string 提供者名称
   */
  public getProviderName(): string {
    return 'HuaweiDrive';
  }

  /**
   * 获取用户信息端点URL
   * @returns string 用户信息端点URL
   */
  protected getUserInfoEndpoint(): string {
    return '';
  }
}
