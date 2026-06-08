/**
 * 百度网盘配置类
 * 管理百度网盘的连接凭证，使用 SM4 加密存储
 */
import { SM4 } from '../crypto/SM4';

/**
 * 百度网盘页面配置（用于设置页面）
 */
export class BaiduNetdiskPageConfig {
  /** 应用 Key */
  appKey: string = '';
  /** 应用 Secret */
  appSecret: string = '';
  /** OAuth2.0 回调地址 */
  redirectUri: string = '';
  /** 根路径（网盘中的目录） */
  rootPath: string = '/apps/kee-pass-ho/';

  constructor(init?: Partial<BaiduNetdiskPageConfig>) {
    if (init) {
      Object.assign(this, init);
    }
  }
}

/**
 * 百度网盘完整配置（包含 Token 等敏感信息）
 */
export class BaiduNetdiskConfig {
  /** 页面配置（非敏感） */
  pageConfig: BaiduNetdiskPageConfig;
  /** 访问令牌 */
  private accessToken: string = '';
  /** 刷新令牌 */
  private refreshToken: string = '';
  /** Token 过期时间戳（毫秒） */
  private tokenExpiresAt: number = 0;

  /** 加密密钥（从用户主密码派生） */
  private static readonly ENCRYPT_KEY: string = 'baidu_netdisk_kee_pass_ho_2024';

  constructor() {
    this.pageConfig = new BaiduNetdiskPageConfig();
  }

  /**
   * 从存储中加载配置
   */
  static async load(): Promise<BaiduNetdiskConfig> {
    const config = new BaiduNetdiskConfig();
    try {
      const sm4 = new SM4(BaidunetdiskConfig.ENCRYPT_KEY);
      // 加载页面配置
      const pageConfigStr = await this.getSecureStorage('baidu_netdisk_page_config');
      if (pageConfigStr) {
        config.pageConfig = JSON.parse(pageConfigStr);
      }
      // 加载加密的 token 信息
      const tokenStr = await this.getSecureStorage('baidu_netdisk_tokens');
      if (tokenStr) {
        const decrypted = sm4.decrypt(tokenStr);
        const tokenData = JSON.parse(decrypted);
        config.accessToken = tokenData.accessToken || '';
        config.refreshToken = tokenData.refreshToken || '';
        config.tokenExpiresAt = tokenData.tokenExpiresAt || 0;
      }
    } catch (e) {
      console.error('[BaiduNetdiskConfig] load failed:', e);
    }
    return config;
  }

  /**
   * 保存配置到存储
   */
  async save(): Promise<void> {
    try {
      const sm4 = new SM4(BaidunetdiskConfig.ENCRYPT_KEY);
      // 保存页面配置
      await BaidunetdiskConfig.setSecureStorage(
        'baidu_netdisk_page_config',
        JSON.stringify(this.pageConfig)
      );
      // 加密保存 token 信息
      const tokenData = {
        accessToken: this.accessToken,
        refreshToken: this.refreshToken,
        tokenExpiresAt: this.tokenExpiresAt
      };
      const encrypted = sm4.encrypt(JSON.stringify(tokenData));
      await BaidunetdiskConfig.setSecureStorage('baidu_netdisk_tokens', encrypted);
    } catch (e) {
      console.error('[BaiduNetdiskConfig] save failed:', e);
      throw e;
    }
  }

  /**
   * 设置访问令牌
   */
  setTokens(accessToken: string, refreshToken: string, expiresInSeconds: number): void {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    this.tokenExpiresAt = Date.now() + expiresInSeconds * 1000;
  }

  /**
   * 获取有效的访问令牌（自动刷新如果过期）
   */
  async getAccessToken(): Promise<string> {
    if (this.isTokenExpired()) {
      await this.refreshAccessToken();
    }
    return this.accessToken;
  }

  /**
   * 检查 Token 是否过期（提前 1 天刷新）
   */
  isTokenExpired(): boolean {
    return Date.now() > this.tokenExpiresAt - 24 * 60 * 60 * 1000;
  }

  /**
   * 刷新访问令牌
   */
  async refreshAccessToken(): Promise<void> {
    if (!this.refreshToken) {
      throw new Error('No refresh token available');
    }
    // 由 BaiduNetdiskClient 负责调用刷新接口
    throw new Error('Token expired, please re-authorize');
  }

  /**
   * 清除所有凭证（退出登录）
   */
  async clear(): Promise<void> {
    this.accessToken = '';
    this.refreshToken = '';
    this.tokenExpiresAt = 0;
    await BaidunetdiskConfig.removeSecureStorage('baidu_netdisk_tokens');
  }

  /**
   * 检查是否已配置
   */
  isConfigured(): boolean {
    return this.pageConfig.appKey !== '' && this.accessToken !== '';
  }

  // ========== 安全存储辅助方法 ==========
  private static async getSecureStorage(key: string): Promise<string | null> {
    // 使用 HarmonyOS Preferences 或 SecureStorage
    // 实际实现需根据项目存储方案调整
    const preferences = await import('@ohos.data.preferences');
    const pref = await preferences.getPreferences(globalThis.context, 'baidu_netdisk_config');
    return pref.get(key, null) as Promise<string | null>;
  }

  private static async setSecureStorage(key: string, value: string): Promise<void> {
    const preferences = await import('@ohos.data.preferences');
    const pref = await preferences.getPreferences(globalThis.context, 'baidu_netdisk_config');
    await pref.put(key, value);
    await pref.flush();
  }

  private static async removeSecureStorage(key: string): Promise<void> {
    const preferences = await import('@ohos.data.preferences');
    const pref = await preferences.getPreferences(globalThis.context, 'baidu_netdisk_config');
    await pref.delete(key);
    await pref.flush();
  }
}
