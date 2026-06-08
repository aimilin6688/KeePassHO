import { BaiduNetdiskConfig } from './BaiduNetdiskConfig';
import { BaiduNetdiskClient } from './BaiduNetdiskClient';
import { StorageType } from '../StorageType';
import { BaiduNetdiskStorage } from './BaiduNetdiskStorage';
import { getStorageConfigManager } from '../StorageConfig';

/**
 * 百度网盘 OAuth2.0 授权提供者
 * 处理授权码获取和 Token 交换
 */
export class BaiduNetdiskOAuth2Provider {
  private config: BaiduNetdiskConfig;
  private client: BaiduNetdiskClient;
  private redirectUri: string = 'https://localhost:8080/callback';

  constructor(config: BaiduNetdiskConfig) {
    this.config = config;
    this.client = new BaiduNetdiskClient(config);
    this.redirectUri = config.pageConfig.redirectUri || this.redirectUri;
  }

  /**
   * 获取授权 URL（用于 WebView 加载）
   */
  getAuthorizationUrl(): string {
    return this.client.getAuthorizationUrl(this.redirectUri, this.generateState());
  }

  /**
   * 从 OAuth 回调 URL 中提取授权码
   * @param callbackUrl 回调 URL，如 https://localhost:8080/callback?code=XXX&state=YYY
   */
  extractAuthorizationCode(callbackUrl: string): string | null {
    try {
      const url = new URL(callbackUrl);
      return url.searchParams.get('code');
    } catch {
      // 可能是相对路径，尝试解析 query string
      const match = callbackUrl.match(/[?&]code=([^&]+)/);
      return match ? match[1] : null;
    }
  }

  /**
   * 用授权码交换 Token，并保存到配置
   */
  async handleAuthorizationCode(code: string): Promise<void> {
    const tokenResp = await this.client.exchangeCodeForToken(code, this.redirectUri);
    if (!tokenResp.access_token) {
      throw new Error('No access_token in response');
    }
    this.config.setTokens(
      tokenResp.access_token,
      tokenResp.refresh_token || '',
      tokenResp.expires_in || 2592000
    );
    await this.config.save();
  }

  /**
   * 刷新 Token
   */
  async refreshToken(): Promise<void> {
    const tokenResp = await this.client.refreshToken(this.config.refreshToken);
    this.config.setTokens(
      tokenResp.access_token,
      tokenResp.refresh_token || this.config.refreshToken,
      tokenResp.expires_in || 2592000
    );
    await this.config.save();
  }

  /**
   * 生成随机 state 参数（防 CSRF）
   */
  private generateState(): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < 16; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  /**
   * 创建百度网盘存储实例（用于保存到 StorageConfig）
   */
  static async createAndSaveStorage(config: BaiduNetdiskConfig): Promise<BaiduNetdiskStorage> {
    const storage = new BaiduNetdiskStorage(config);
    const manager = getStorageConfigManager();
    await manager.saveConfig(StorageType.BAIDU_NETDISK, {
      type: StorageType.BAIDU_NETDISK,
      displayName: '百度网盘',
      config: JSON.parse(JSON.stringify(config.pageConfig)),
    });
    return storage;
  }
}
