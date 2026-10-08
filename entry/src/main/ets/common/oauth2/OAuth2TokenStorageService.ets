import { hilog } from '@kit.PerformanceAnalysisKit';
import preferences from '@ohos.data.preferences';
import { fileIo as fs } from '@kit.CoreFileKit';
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
 * 文件持久化数据
 */
interface TokenFileData {
  /** 数据格式版本 */
  v: number;
  /** 令牌表（key = tokenKey, value = 加密后的令牌 JSON 串） */
  tokens: Record<string, string>;
}

/**
 * JSON 反序列化的原始模型（严格校验前）
 */
interface TokenFileRaw {
  v?: Object;
  tokens?: Object;
}

/**
 * OAuth2令牌存储服务
 * 提供统一的OAuth2令牌存储、加载、更新和删除功能
 *
 * 持久化后端为 filesDir 下 JSON 文件（huks 加密令牌内容）：
 * - Worker 线程无 Context/preferences（设计文档 §11.1），文件后端经注入路径在主线程与 Worker 通用，
 *   修复 Worker 内令牌刷新后无法落盘、每个操作重复刷新的问题；
 * - 主线程首次访问时一次性迁移旧 preferences 数据（expiresAt 新者胜）；
 * - 写入串行化（进程内写链）+ 临时文件 rename 原子替换。
 */
export class OAuth2TokenStorageService {
  private static instance: OAuth2TokenStorageService = new OAuth2TokenStorageService();
  /** 内存令牌表（key = tokenKey, value = 加密串），懒加载自文件 */
  private tokens: Map<string, string> = new Map();
  /** 初始化完成标记（含失败 fail-open，避免每次调用重复探测） */
  private initialized: boolean = false;
  /** 进行中的初始化 Promise（单飞去重） */
  private opening: Promise<void> | null = null;
  /** 写链：串行化文件写入，避免并发丢失更新 */
  private writeChain: Promise<void> = Promise.resolve();
  private static readonly FILE_NAME = 'oauth2_tokens.json';
  private static readonly FILE_VERSION = 1;
  private static readonly LEGACY_PREFERENCES_NAME = 'oauth2_tokens';

  /**
   * 获取单例实例
   */
  public static getInstance(): OAuth2TokenStorageService {
    return OAuth2TokenStorageService.instance;
  }

  /**
   * 供测试重置单例（模拟进程重启后从文件重新水合）
   * @internal 业务代码不得调用
   */
  public static resetForTest(): void {
    OAuth2TokenStorageService.instance = new OAuth2TokenStorageService();
  }

  /**
   * 令牌文件路径（filesDir：主线程取自 Context，Worker 取注入路径，两侧一致）
   */
  private get filePath(): string {
    return CommonUtils.getAppFilesDir() + '/' + OAuth2TokenStorageService.FILE_NAME;
  }

  /**
   * 幂等单飞初始化：加载文件 + 主线程一次性迁移旧 preferences 数据
   */
  private ensureInit(): Promise<void> {
    if (this.initialized) {
      return Promise.resolve();
    }
    if (this.opening) {
      return this.opening;
    }
    this.opening = this.doInit();
    return this.opening;
  }

  private async doInit(): Promise<void> {
    try {
      await this.loadFromFile();
      // 主线程：迁移旧 preferences 数据（Worker 无 Context，跳过；文件侧已有同 key 数据时 expiresAt 新者胜）
      if (CommonUtils.hasContext()) {
        await this.migrateFromLegacyPreferences();
      }
      this.initialized = true;
    } catch (error) {
      // fail-open：初始化失败时以空表降级，后续读写走内存（与旧版 Worker 内行为一致，不阻塞业务）
      hilog.warn(DOMAIN, TAG, 'Init token store failed (degrade to empty): %{public}s', (error as Error).message);
      this.initialized = true;
    } finally {
      this.opening = null;
    }
  }

  /**
   * 从文件加载令牌表到内存
   */
  private async loadFromFile(): Promise<void> {
    if (!fs.accessSync(this.filePath, fs.AccessModeType.EXIST)) {
      return;
    }
    const text: string = fs.readTextSync(this.filePath);
    if (!text) {
      return;
    }
    const raw = JSON.parse(text) as TokenFileRaw;
    const tokensObj = raw.tokens;
    if (tokensObj && typeof tokensObj === 'object' && !Array.isArray(tokensObj)) {
      const record = tokensObj as Record<string, string>;
      const keys: string[] = Object.keys(record);
      for (const key of keys) {
        const value: Object | undefined = record[key];
        if (typeof value === 'string' && value.length > 0) {
          this.tokens.set(key, value);
        }
      }
    }
    hilog.info(DOMAIN, TAG, 'Token store loaded: %{public}d entries', this.tokens.size);
  }

  /**
   * 迁移旧 preferences 后端数据（仅主线程；Worker 由文件侧直接接管）
   * 同 key 双侧都有时解密比较 expiresAt，新者胜；解密失败保留文件侧
   */
  private async migrateFromLegacyPreferences(): Promise<void> {
    let legacy: preferences.Preferences | null = null;
    try {
      legacy = await preferences.getPreferences(CommonUtils.getContext(),
        OAuth2TokenStorageService.LEGACY_PREFERENCES_NAME);
    } catch (error) {
      // 旧数据不存在或读取失败：无需迁移
      return;
    }
    let changed: boolean = false;
    const providers: OAuth2Provider[] = [OAuth2Provider.GITHUB, OAuth2Provider.GOOGLE,
      OAuth2Provider.ONEDRIVE, OAuth2Provider.DROPBOX, OAuth2Provider.PCLOUD,
      OAuth2Provider.HUAWEI_DRIVE, OAuth2Provider.BAIDU_NETDISK];
    for (const provider of providers) {
      const key: string = this.getDefaultTokenKey(provider);
      try {
        const legacyValue = await legacy.get(key, '') as string;
        if (!legacyValue) {
          continue;
        }
        const fileValue: string | undefined = this.tokens.get(key);
        if (fileValue === undefined) {
          this.tokens.set(key, legacyValue);
          changed = true;
          continue;
        }
        // 双侧都有：解密比较 expiresAt，新者胜（加密串无法直接比较）
        const legacyToken: OAuth2Token | null = await this.tryDecryptToken(legacyValue);
        const fileToken: OAuth2Token | null = await this.tryDecryptToken(fileValue);
        if (legacyToken && fileToken && (legacyToken.expiresAt ?? 0) > (fileToken.expiresAt ?? 0)) {
          this.tokens.set(key, legacyValue);
          changed = true;
        }
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Migrate legacy token %{public}s failed: %{public}s',
          key, (error as Error).message);
      }
    }
    if (changed) {
      await this.persist();
      hilog.info(DOMAIN, TAG, 'Legacy preferences tokens migrated to file store');
    }
  }

  /**
   * 解密令牌串，失败返回 null
   */
  private async tryDecryptToken(encrypted: string): Promise<OAuth2Token | null> {
    try {
      const plain: string = await CryptoUtils.decryptText(encrypted);
      if (!plain) {
        return null;
      }
      return JSON.parse(plain) as OAuth2Token;
    } catch {
      return null;
    }
  }

  /**
   * 序列化内存令牌表并原子落盘（临时文件 + rename），经写链串行执行
   */
  private persist(): Promise<void> {
    const write: () => Promise<void> = async (): Promise<void> => {
      const record: Record<string, string> = {};
      this.tokens.forEach((value: string, key: string) => {
        record[key] = value;
      });
      const data: TokenFileData = { v: OAuth2TokenStorageService.FILE_VERSION, tokens: record };
      const json: string = JSON.stringify(data);
      const tmpPath: string = this.filePath + '.tmp';
      const file = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        await fs.write(file.fd, json);
        await fs.fsync(file.fd);
      } finally {
        await fs.close(file.fd);
      }
      await fs.rename(tmpPath, this.filePath);
    };
    this.writeChain = this.writeChain.then(write).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Persist token store failed: %{public}s', error.message);
    });
    return this.writeChain;
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
    await this.ensureInit();
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

      // 保存到内存表并落盘
      this.tokens.set(tokenKey, tokenToSave);
      await this.persist();

      hilog.info(DOMAIN, TAG, `Token saved successfully for provider: ${config.provider}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to save token for provider ${config.provider}: %{public}s`, (error as Error).message);
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(String(error));
    }
  }

  /**
   * 加载OAuth2令牌
   * @param config 存储配置
   */
  public async loadToken(config: OAuth2TokenStorageConfig): Promise<OAuth2Token | null> {
    await this.ensureInit();
    try {
      // 生成令牌键名
      const tokenKey = config.tokenKey || this.getDefaultTokenKey(config.provider);
      const tokenString = this.tokens.get(tokenKey);
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
          tokenJson = tokenString;
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
    await this.ensureInit();
    try {
      // 生成令牌键名
      const tokenKey = config.tokenKey || this.getDefaultTokenKey(config.provider);

      // 从内存表删除并落盘
      this.tokens.delete(tokenKey);
      await this.persist();
      hilog.info(DOMAIN, TAG, `Token deleted for provider: ${config.provider}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to delete token for provider ${config.provider}: %{public}s`, (error as Error).message);
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(String(error));
    }
  }

  /**
   * 检查是否存在令牌
   * @param config 存储配置
   */
  public async hasToken(config: OAuth2TokenStorageConfig): Promise<boolean> {
    await this.ensureInit();
    const tokenKey = config.tokenKey || this.getDefaultTokenKey(config.provider);
    return !!this.tokens.get(tokenKey);
  }

  /**
   * 清除所有OAuth2令牌
   */
  public async clearAllTokens(): Promise<void> {
    await this.ensureInit();
    try {
      this.tokens.clear();
      await this.persist();
      hilog.info(DOMAIN, TAG, 'All OAuth2 tokens cleared');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to clear all tokens: %{public}s', (error as Error).message);
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(String(error));
    }
  }
}
