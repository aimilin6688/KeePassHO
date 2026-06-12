import { BaiduNetdiskConfig } from './BaiduNetdiskConfig';
import { BaiduNetdiskClient } from './BaiduNetdiskClient';
import { BaiduNetdiskStorage } from './BaiduNetdiskStorage';
import { OAuth2Provider, OAuth2Token } from '../../common/oauth2/OAuth2Types';
import { OAuth2TokenStorageService, OAuth2TokenStorageConfig } from '../../common/oauth2/OAuth2TokenStorageService';
import { CommonUtils } from '../../common/utils/CommonUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'BaiduNetdiskOAuth2Provider';

/**
 * 百度网盘 OAuth2.0 授权提供者
 * 处理授权码获取和 Token 交换
 */
export class BaiduNetdiskOAuth2Provider {
  private config: BaiduNetdiskConfig;
  private client: BaiduNetdiskClient;
  private redirectUri: string = 'https://localhost/callback';
  private tokenStorage: OAuth2TokenStorageService = OAuth2TokenStorageService.getInstance();

  constructor(config: BaiduNetdiskConfig) {
    this.config = config;
    this.client = new BaiduNetdiskClient(config);
    this.redirectUri = config.redirectUri || this.redirectUri;
  }

  /**
   * 获取授权 URL（用于 WebView 加载）
   */
  getAuthorizationUrl(): string {
    return this.client.getAuthorizationUrl(this.redirectUri, this.generateState());
  }

  /**
   * 从 OAuth 回调 URL 中提取授权码（手动解析，ArkTS 不支持 URL 类）
   */
  extractAuthorizationCode(callbackUrl: string): string {
    const questionMark: number = callbackUrl.indexOf('?');
    if (questionMark < 0) {
      return '';
    }
    const queryStr: string = callbackUrl.substring(questionMark + 1);
    const params: Record<string, string> = this.parseQueryString(queryStr);
    return params['code'] || '';
  }

  /**
   * 用授权码交换 Token，并保存到配置
   */
  async handleAuthorizationCode(code: string): Promise<void> {
    const tokenResp: import('./BaiduNetdiskTypes').BaiduTokenResponse = await this.client.exchangeCodeForToken(code, this.redirectUri);
    if (!tokenResp || !tokenResp.access_token) {
      throw new Error('No access_token in response');
    }
    // 保存到配置（通过 OAuth2TokenStorageService 加密存储）
    await this.config.saveTokens(
      tokenResp.access_token,
      tokenResp.refresh_token || '',
      tokenResp.expires_in || 2592000
    );
    hilog.info(DOMAIN, TAG, 'Token saved successfully');
  }

  /**
   * 刷新 Token
   */
  async refreshTokenValue(): Promise<void> {
    const storageCfg: OAuth2TokenStorageConfig = {
      provider: OAuth2Provider.BAIDU_NETDISK,
      encrypt: true
    };
    const existingToken: OAuth2Token | null = await this.tokenStorage.loadToken(storageCfg);
    if (existingToken === null || !existingToken.refreshToken) {
      throw new Error('No refresh token available');
    }
    const tokenResp: import('./BaiduNetdiskTypes').BaiduTokenResponse = await this.client.refreshToken(existingToken.refreshToken);
    if (!tokenResp || !tokenResp.access_token) {
      throw new Error('Failed to refresh token');
    }
    await this.config.saveTokens(
      tokenResp.access_token,
      tokenResp.refresh_token || existingToken.refreshToken || '',
      tokenResp.expires_in || 2592000
    );
  }

  /**
   * 创建百度网盘存储实例
   */
  static createStorage(config: BaiduNetdiskConfig): BaiduNetdiskStorage {
    return new BaiduNetdiskStorage(config);
  }

  /**
   * 生成随机 state 参数（防 CSRF）
   */
  private generateState(): string {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result: string = '';
    for (let i: number = 0; i < 16; i++) {
      const idx: number = Math.floor(Math.random() * chars.length);
      result += chars.charAt(idx);
    }
    return result;
  }

  /**
   * 解析 query string 为 key-value 对象
   */
  private parseQueryString(queryStr: string): Record<string, string> {
    const result: Record<string, string> = {};
    if (queryStr === '') {
      return result;
    }
    const pairs: string[] = queryStr.split('&');
    for (let i: number = 0; i < pairs.length; i++) {
      const pair: string = pairs[i];
      const eqPos: number = pair.indexOf('=');
      if (eqPos >= 0) {
        const key: string = decodeURIComponent(pair.substring(0, eqPos));
        const val: string = decodeURIComponent(pair.substring(eqPos + 1));
        result[key] = val;
      } else {
        result[decodeURIComponent(pair)] = '';
      }
    }
    return result;
  }
}
