import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { ThemeMode } from '../common/constants/ThemeConstants';
import ThemeManager from '../common/utils/ThemeManager';
import common from '@ohos.app.ability.common';
import { SortMode } from '../common/constants/SortConstants';

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'SettingsService';

export enum UnlockAuthType {
  FACE = "FACE",
  FINGERPRINT = "FINGERPRINT",
  PASSWORD = "PASSWORD"
}

export class SettingsService {
  private static instance: SettingsService = new SettingsService();
  private preferences: preferences.Preferences | null = null;
  private static readonly PREFERENCES_NAME = 'settings';
  // 设置键名
  public static readonly KEY_THEME_MODE = 'themeMode';
  public static readonly KEY_DARK_MODE = 'darkMode'; // 保留向后兼容
  public static readonly KEY_SORT_BY = 'sortBy';
  // 安全设置
  public static readonly KEY_SECURITY_PULL_REFRESH = 'Security_PullRefresh';
  public static readonly KEY_SECURITY_PULL_REFRESH_DEFAULT = true;
  public static readonly KEY_SECURITY_CLEAR_PASTEBOARD_TIME = 'Security_clear_pasteboard_time';
  public static readonly KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT = 30;
  public static readonly KEY_SECURITY_AUTO_LOCK_TIME = 'Security_auto_lock_time';
  public static readonly KEY_SECURITY_AUTO_LOCK_TIME_DEFAULT = 30;
  public static readonly KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH = 'Security_quick_lock_password_length';
  public static readonly KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH_DEFAULT = 4;
  // 数据设置
  public static readonly KEY_DATABASE_FINGERPRINT_LOGIN = 'Database_fingerprint_login';
  public static readonly KEY_DATABASE_FINGERPRINT_LOGIN_DEFAULT = false;
  public static readonly KEY_DATABASE_FACE_LOGIN = 'Database_face_login';
  public static readonly KEY_DATABASE_FACE_LOGIN_DEFAULT = false;
  public static readonly KEY_DATABASE_AUTH_DEFAULT_TYPE = 'Database_auth_default_type';
  public static readonly KEY_DATABASE_AUTH_DEFAULT_TYPE_DEFAULT = UnlockAuthType.PASSWORD;
  // 显示TOTP设置
  public static readonly KEY_SECURITY_LIST_SHOW_TOTP = "Security_list_show_totp";
  public static readonly KEY_SECURITY_LIST_SHOW_TOTP_DEFAULT = false;
  public static readonly KEY_SECURITY_ITEM_SHOW_TOTP = "Security_item_show_totp";
  public static readonly KEY_SECURITY_ITEM_SHOW_TOTP_DEFAULT = false;
  // 观察者列表
  private observers: ((key: string) => void)[] = [];

  private constructor() {
  }

  public static getInstance(): SettingsService {
    return SettingsService.instance;
  }

  /**
   * 初始化首选项存储
   * @param context UIAbilityContext
   */
  public async init(context: common.UIAbilityContext): Promise<void> {
    try {
      this.preferences = await preferences.getPreferences(context, SettingsService.PREFERENCES_NAME);

      // 初始化主题
      const themeMode = await this.getThemeMode();
      await ThemeManager.getInstance().setThemeMode(themeMode);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to get preferences: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
    }
  }

  /**
   * 设置主题模式
   * @param mode 主题模式
   */
  public async setThemeMode(mode: ThemeMode): Promise<void> {
    if (!this.preferences) {
      return;
    }
    try {
      await this.preferences.put(SettingsService.KEY_THEME_MODE, mode);
      await this.preferences.flush();
      // 应用新的主题模式
      await ThemeManager.getInstance().setThemeMode(mode);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to set theme mode: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
    }
  }

  /**
   * 获取主题模式
   */
  public async getThemeMode(): Promise<ThemeMode> {
    if (!this.preferences) {
      return ThemeMode.SYSTEM;
    }
    try {
      // 尝试获取新的主题模式设置
      const mode = await this.preferences.get(SettingsService.KEY_THEME_MODE, ThemeMode.SYSTEM) as ThemeMode;
      if (mode) {
        return mode;
      }

      // 向后兼容：如果没有新的主题模式设置，检查旧的深色模式设置
      const isDark = await this.preferences.get(SettingsService.KEY_DARK_MODE, false) as boolean;
      return isDark ? ThemeMode.DARK : ThemeMode.LIGHT;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to get theme mode: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
      return ThemeMode.SYSTEM;
    }
  }

  /**
   * @deprecated 使用 setThemeMode 代替
   * 设置深色模式
   * @param enabled 是否启用深色模式
   */
  public async setDarkMode(enabled: boolean): Promise<void> {
    await this.setThemeMode(enabled ? ThemeMode.DARK : ThemeMode.LIGHT);
  }

  /**
   * @deprecated 使用 getThemeMode 代替
   * 获取深色模式状态
   */
  public async isDarkMode(): Promise<boolean> {
    const mode = await this.getThemeMode();
    return mode === ThemeMode.DARK;
  }


  /**
   * 设置排序方式
   * @param sortBy 排序方式 ('default' | 'name' | 'modified' | 'created')
   */
  public async setSortBy(sortBy: SortMode): Promise<void> {
    return this.put(SettingsService.KEY_SORT_BY, sortBy);
  }

  /**
   * 获取排序方式
   */
  public async getSortBy(): Promise<SortMode> {
    return this.get(SettingsService.KEY_SORT_BY, SortMode.DEFAULT);
  }


  // 写入数据并通知观察者
  public async put(key: string, value: preferences.ValueType): Promise<void> {
    if (!this.preferences) {
      return;
    }

    try {
      await this.preferences.put(key, value);
      await this.preferences.flush(); // 重要！确保数据持久化
      // 通知所有观察者
      this.observers.forEach(observer => observer(key));
      return Promise.resolve();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to set ${(err as BusinessError).code} by ${(err as BusinessError).message}`);
    }
  }

  // 读取数据
  public async get<T extends preferences.ValueType>(key: string, defValue: T): Promise<T> {
    if (!this.preferences) {
      return defValue;
    }

    try {
      return (this.preferences.get(key, defValue)) as T;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to get value. Code: ${(err as BusinessError).code}`);
      return defValue;
    }
  }

  // 读取数据
  public getSync<T extends preferences.ValueType>(key: string, defValue: T): T {
    if (!this.preferences) {
      return defValue;
    }
    try {
      return (this.preferences.getSync(key, defValue)) as T;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to get value. Code: ${(err as BusinessError).code}`);
      return defValue;
    }
  }

  // 读取数据
  public static get<T extends preferences.ValueType>(key: string, defValue: T, callback: (value: T) => void): void {
    SettingsService.getInstance().get(key, defValue).then(value => {
      callback(value);
    });
  }


  // 注册观察者
  public registerObserver(observer: (key: string) => void): void {
    this.observers.push(observer);
  }

  public static registerObserver(observer: (key: string) => void): void {
    SettingsService.getInstance().registerObserver(observer);
  }

  // 移除观察者
  public unregisterObserver(observer: (key: string) => void): void {
    const index = this.observers.indexOf(observer);
    if (index !== -1) {
      this.observers.splice(index, 1);
    }
  }

  public static unregisterObserver(observer: (key: string) => void): void {
    SettingsService.getInstance().unregisterObserver(observer);
  }

  static getFingerprintAuthEnable(): boolean {
    return SettingsService.getInstance().getSync(SettingsService.KEY_DATABASE_FINGERPRINT_LOGIN, SettingsService.KEY_DATABASE_FINGERPRINT_LOGIN_DEFAULT);
  }

  static getFaceAuthEnable(): boolean {
    return SettingsService.getInstance().getSync(SettingsService.KEY_DATABASE_FACE_LOGIN, SettingsService.KEY_DATABASE_FACE_LOGIN_DEFAULT);
  }
}
