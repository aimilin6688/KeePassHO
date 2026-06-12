import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { CommonUtils } from '../../common/utils/CommonUtils';
import { OAuth2Provider, OAuth2Token } from '../../common/oauth2/OAuth2Types';
import { OAuth2TokenStorageService, OAuth2TokenStorageConfig } from '../../common/oauth2/OAuth2TokenStorageService';

const PREFERENCES_NAME: string = 'baidu_netdisk_config';
const KEY_APP_KEY: string = 'baidu_app_key';
const KEY_APP_SECRET: string = 'baidu_app_secret';
const KEY_REDIRECT_URI: string = 'baidu_redirect_uri';
const KEY_ROOT_PATH: string = 'baidu_root_path';

/**
 * 百度网盘配置类
 * 页面配置存 Preferences，Token 通过 OAuth2TokenStorageService 加密存储
 */
export class BaiduNetdiskConfig {
  appKey: string = '';
  appSecret: string = '';
  redirectUri: string = 'https://localhost/callback';
  rootPath: string = '/apps/kee-pass-ho/';

  private prefs: preferences.Preferences | null = null;
  private tokenStorage: OAuth2TokenStorageService = OAuth2TokenStorageService.getInstance();

  /**
   * 从持久化存储加载配置
   */
  static async load(): Promise<BaiduNetdiskConfig> {
    const config: BaiduNetdiskConfig = new BaiduNetdiskConfig();
    await config.initPreferences();

    if (config.prefs !== null) {
      // await get() 因为该版本 SDK 中 get 是异步的
      const ak: Object = await config.prefs.get(KEY_APP_KEY, '');
      const as: Object = await config.prefs.get(KEY_APP_SECRET, '');
      const ru: Object = await config.prefs.get(KEY_REDIRECT_URI, 'https://localhost/callback');
      const rp: Object = await config.prefs.get(KEY_ROOT_PATH, '/apps/kee-pass-ho/');
      config.appKey = (ak as string);
      config.appSecret = (as as string);
      config.redirectUri = (ru as string);
      config.rootPath = (rp as string);
    }

    return config;
  }

  /**
   * 保存页面配置到 Preferences（不含令牌）
   */
  async save(): Promise<void> {
    await this.initPreferences();
    if (this.prefs === null) {
      return;
    }
    this.prefs.put(KEY_APP_KEY, this.appKey);
    this.prefs.put(KEY_APP_SECRET, this.appSecret);
    this.prefs.put(KEY_REDIRECT_URI, this.redirectUri);
    this.prefs.put(KEY_ROOT_PATH, this.rootPath);
    await this.prefs.flush();
  }

  /**
   * 保存令牌（通过 OAuth2TokenStorageService 加密存储）
   */
  async saveTokens(accessToken: string, refreshToken: string, expiresInSeconds: number): Promise<void> {
    const token: OAuth2Token = {
      accessToken: accessToken,
      tokenType: 'Bearer',
      refreshToken: refreshToken,
      expiresAt: Date.now() + expiresInSeconds * 1000,
      scope: 'basic netdisk'
    };
    const storageConfig: OAuth2TokenStorageConfig = {
      provider: OAuth2Provider.BAIDU_NETDISK,
      encrypt: true
    };
    await this.tokenStorage.saveToken(token, storageConfig);
  }

  /**
   * 加载令牌
   */
  async loadTokens(): Promise<OAuth2Token | null> {
    const storageConfig: OAuth2TokenStorageConfig = {
      provider: OAuth2Provider.BAIDU_NETDISK,
      encrypt: true
    };
    return this.tokenStorage.loadToken(storageConfig);
  }

  /**
   * 获取有效访问令牌
   */
  async getAccessToken(): Promise<string> {
    const token: OAuth2Token | null = await this.loadTokens();
    if (token === null || token.accessToken === '') {
      throw new Error('No token available, please re-authorize');
    }
    // 提前 1 天刷新
    if (token.expiresAt !== undefined && token.expiresAt < Date.now() + 24 * 60 * 60 * 1000) {
      if (token.refreshToken !== undefined && token.refreshToken !== '') {
        throw new Error('Token expired, please re-authorize');
      }
    }
    return token.accessToken;
  }

  /**
   * 清除所有凭证
   */
  async clear(): Promise<void> {
    await this.initPreferences();
    if (this.prefs !== null) {
      this.prefs.clearSync();
      await this.prefs.flush();
    }
    const storageConfig: OAuth2TokenStorageConfig = {
      provider: OAuth2Provider.BAIDU_NETDISK,
      encrypt: true
    };
    await this.tokenStorage.deleteToken(storageConfig);
  }

  /**
   * 检查是否已配置
   */
  async isConfigured(): Promise<boolean> {
    if (this.appKey === '') {
      return false;
    }
    const token: OAuth2Token | null = await this.loadTokens();
    return token !== null && token.accessToken !== '';
  }

  /**
   * 初始化 Preferences 实例
   */
  private async initPreferences(): Promise<void> {
    if (this.prefs !== null) {
      return;
    }
    const ctx: common.Context = CommonUtils.getContext();
    const options: preferences.Options = { name: PREFERENCES_NAME };
    this.prefs = await preferences.getPreferences(ctx, options);
  }
}
