import { hilog } from '@kit.PerformanceAnalysisKit';
import preferences from '@ohos.data.preferences';
import { CryptoUtils } from '../utils/CryptoUtils';
import { OAuth2Provider, OAuth2Token } from './OAuth2Types';
import { CommonUtils } from '../utils';

const DOMAIN = 0x0000;
const TAG = 'OAuth2TokenStorageService';

/**
 * OAuth2令牌存储配置
 */
export interface OAuth2TokenStorageConfig {
  /**
   * OAuth2提供者
   */
  provider: OAuth2Provider;

  /**
   * 令牌键名（可选，默认根据provider生成）
   */
  tokenKey?: string;

  /**
   * 是否加密存储（默认true）
   */
  encrypt?: boolean;
}

/**
 * OAuth2令牌存储服务
 * 提供统一的OAuth2令牌存储、加载、更新和删除功能
 */
export class OAuth2TokenStorageService {
  private static instance: OAuth2TokenStorageService = new OAuth2TokenStorageService();
  private preferences: preferences.Preferences | null = null;
  private static readonly PREFERENCES_NAME = 'oauth2_tokens';

  /**
   * 获取单例实例
   */
  public static getInstance(): OAuth2TokenStorageService {
    return OAuth2TokenStorageService.instance;
  }

  /**
   * 初始化服务
   */
  private async init(): Promise<void> {
    if (!this.preferences) {
      try {
        this.preferences = await preferences.getPreferences(CommonUtils.getContext(), OAuth2TokenStorageService.PREFERENCES_NAME);
        hilog.info(DOMAIN, TAG, 'OAuth2TokenStorageService initialized successfully');
      } catch (err) {
        hilog.error(DOMAIN, TAG, `Failed to initialize OAuth2TokenStorageService: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
      }
    }
  }

  /**
   * 获取默认令牌键名
   * @param provider OAuth2提供者
   */
  private getDefaultTokenKey(provider: OAuth2Provider): string {
    return `${provider.toLowerCase()}_token`;
  }

  /**
   * 保存OAuth2令牌
   * @param token 令牌信息
   * @param config 存储配置
   */
  public async saveToken(token: OAuth2Token, config: OAuth2TokenStorageConfig): Promise<void> {
    this.init();
    if (!this.preferences) {
      throw new Error('OAuth2TokenStorageService not initialized');
    }

    try {
      // 生成令牌键名
      const tokenKey = config.tokenKey || this.getDefaultTokenKey(config.provider);

      // 将令牌转换为JSON字符串
      const tokenJson = JSON.stringify(token);

      let tokenToSave: string;
      if (config.encrypt !== false) {
        // 加密存储
        const encryptedToken = await CryptoUtils.encryptText(tokenJson);
        if (!encryptedToken) {
          throw new Error('Failed to encrypt token');
        }
        tokenToSave = encryptedToken;
        hilog.info(DOMAIN, TAG, `Token encrypted and saved for provider: ${config.provider}`);
      } else {
        // 明文存储
        tokenToSave = tokenJson;
        hilog.info(DOMAIN, TAG, `Token saved in plaintext for provider: ${config.provider}`);
      }

      // 保存到首选项
      await this.preferences.put(tokenKey, tokenToSave);
      await this.preferences.flush();

      hilog.info(DOMAIN, TAG, `Token saved successfully for provider: ${config.provider}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to save token for provider ${config.provider}: %{public}s`, (error as Error).message);
      CommonUtils.showToast(`${config.provider}: ${(error as BusinessError).message}`);
    }
  }

  /**
   * 加载OAuth2令牌
   * @param config 存储配置
   */
  public async loadToken(config: OAuth2TokenStorageConfig): Promise<OAuth2Token | null> {
    this.init();
    if (!this.preferences) {
      throw new Error('OAuth2TokenStorageService not initialized');
    }

    try {
      // 生成令牌键名
      const tokenKey = config.tokenKey || this.getDefaultTokenKey(config.provider);
      // 从首选项获取令牌字符串
      const tokenString = await this.preferences.get(tokenKey, '') as string;
      if (!tokenString) {
        hilog.debug(DOMAIN, TAG, `No token found for provider: ${config.provider}`);
        return null;
      }

      // 尝试解密（如果可能）并解析
      let tokenJson: string;
      if (config.encrypt !== false) {
        // 尝试解密
        const decryptedToken = await CryptoUtils.decryptText(tokenString);
        if (!decryptedToken) {
          // 可能不是加密的，尝试直接解析
          try {
            tokenJson = tokenString;
          } catch (parseError) {
            hilog.error(DOMAIN, TAG, `Failed to parse token for provider ${config.provider}: %{public}s`, (parseError as Error).message);
            return null;
          }
        } else {
          tokenJson = decryptedToken;
        }
      } else {
        tokenJson = tokenString;
      }

      // 解析JSON
      const token = JSON.parse(tokenJson) as OAuth2Token;
      hilog.info(DOMAIN, TAG, `Token loaded successfully for provider: ${config.provider}`);
      return token;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to load token for provider ${config.provider}: %{public}s`, (error as Error).message);
      return null;
    }
  }

  /**
   * 更新OAuth2令牌
   * @param token 新的令牌信息
   * @param config 存储配置
   */
  public async updateToken(token: OAuth2Token, config: OAuth2TokenStorageConfig): Promise<void> {
    await this.saveToken(token, config);
    hilog.info(DOMAIN, TAG, `Token updated for provider: ${config.provider}`);
  }

  /**
   * 删除OAuth2令牌
   * @param config 存储配置
   */
  public async deleteToken(config: OAuth2TokenStorageConfig): Promise<void> {
    this.init();
    if (!this.preferences) {
      throw new Error('OAuth2TokenStorageService not initialized');
    }

    try {
      // 生成令牌键名
      const tokenKey = config.tokenKey || this.getDefaultTokenKey(config.provider);

      // 从首选项删除
      await this.preferences.delete(tokenKey);
      await this.preferences.flush();
      hilog.info(DOMAIN, TAG, `Token deleted for provider: ${config.provider}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to delete token for provider ${config.provider}: %{public}s`, (error as Error).message);
      CommonUtils.showToast(`${config.provider}: ${(error as BusinessError).message}`);
    }
  }

  /**
   * 检查是否存在令牌
   * @param config 存储配置
   */
  public async hasToken(config: OAuth2TokenStorageConfig): Promise<boolean> {
    this.init();
    if (!this.preferences) {
      throw new Error('OAuth2TokenStorageService not initialized');
    }
    try {
      const tokenKey = config.tokenKey || this.getDefaultTokenKey(config.provider);
      const tokenString = await this.preferences.get(tokenKey, '') as string;
      return !!tokenString;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to check token existence for provider ${config.provider}: %{public}s`, (error as Error).message);
      return false;
    }
  }

  /**
   * 清除所有OAuth2令牌
   */
  public async clearAllTokens(): Promise<void> {
    this.init();
    if (!this.preferences) {
      throw new Error('OAuth2TokenStorageService not initialized');
    }
    try {
      await this.preferences.clear();
      await this.preferences.flush();
      hilog.info(DOMAIN, TAG, 'All OAuth2 tokens cleared');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to clear all tokens: %{public}s', (error as Error).message);
      CommonUtils.showToast(`${error?.message}`);
    }
  }
}