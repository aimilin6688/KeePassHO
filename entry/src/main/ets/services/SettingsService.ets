import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { ThemeMode } from '../common/constants/ThemeConstants';
import { ThemeManager } from '../common/utils';
import common from '@ohos.app.ability.common';
import { SortMode } from '../common/constants/SortConstants';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { SyncSettingsService } from './store/SyncSettingsService';

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
  public static readonly KEY_SECURITY_SEARCH_HISTORY_ENABLE = 'Security_search_history';
  public static readonly KEY_SECURITY_SEARCH_HISTORY_ENABLE_DEFAULT = true;
  public static readonly KEY_SECURITY_CLEAR_PASTEBOARD_TIME = 'Security_clear_pasteboard_time';
  public static readonly KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT = 30;
  public static readonly KEY_SECURITY_AUTO_LOCK_TIME = 'Security_auto_lock_time';
  public static readonly KEY_SECURITY_AUTO_LOCK_TIME_DEFAULT = 30;
  public static readonly KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH = 'Security_quick_lock_password_length';
  public static readonly KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH_DEFAULT = 3;
  // 认证方式
  public static readonly KEY_SECURITY_FINGERPRINT_LOGIN = 'Database_fingerprint_login';
  public static readonly KEY_SECURITY_FINGERPRINT_LOGIN_DEFAULT = false;
  public static readonly KEY_SECURITY_FACE_LOGIN = 'Database_face_login';
  public static readonly KEY_SECURITY_FACE_LOGIN_DEFAULT = false;
  public static readonly KEY_SECURITY_AUTH_DEFAULT_TYPE = 'Database_auth_default_type';
  public static readonly KEY_SECURITY_AUTH_DEFAULT_TYPE_DEFAULT = UnlockAuthType.PASSWORD;
  // 显示TOTP设置
  public static readonly KEY_SECURITY_LIST_SHOW_TOTP = "Security_list_show_totp";
  public static readonly KEY_SECURITY_LIST_SHOW_TOTP_DEFAULT = true;
  public static readonly KEY_SECURITY_ITEM_SHOW_TOTP = "Security_item_show_totp";
  public static readonly KEY_SECURITY_ITEM_SHOW_TOTP_DEFAULT = true;

  // --------------- APP 设置信息 ---------------------
  // 支持弹框
  public static readonly KEY_SHOW_SUPPORT_TIME = "show_support_time";
  public static readonly KEY_SHOW_SUPPORT_DIALOG = "show_support_dialog";
  public static readonly KEY_SHOW_SUPPORT_DIALOG_DEFAULT = true;
  public static readonly KEY_APP_INSTALL_TIME = "app_install_time";
  // 限制数据库后缀
  public static readonly KEY_APP_LIMIT_DB_EXT = "app_limit_db_ext";
  public static readonly KEY_APP_LIMIT_DB_EXT_DEFAULT = true;
  // 跨设备同步设置
  public static readonly KEY_APP_SYNC_SETTING_ENABLE = "app_sync_setting_enable";
  public static readonly KEY_APP_SYNC_SETTING_ENABLE_DEFAULT = false;
  // 启用智感握姿
  public static readonly KEY_APP_HOLDING_HAND_ENABLE = "app_holding_hand_enable";
  public static readonly KEY_APP_HOLDING_HAND_ENABLE_DEFAULT = false;

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
    return new Promise(async (resolve, reject) => {
      try {
        this.preferences = await preferences.getPreferences(context, SettingsService.PREFERENCES_NAME);
        // 初始化主题
        const themeMode = await this.getThemeMode();
        await ThemeManager.getInstance().setThemeMode(themeMode);
        // 初始化同步服务
        await SyncSettingsService.init();
        return resolve();
      } catch (err) {
        hilog.error(DOMAIN, TAG, `Failed to get preferences: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
        return reject(err);
      }
    });
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
      this.put(SettingsService.KEY_THEME_MODE, mode);
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

      // 自动同步到远端设备
      SyncSettingsService.syncSetting(key, value);

      // 通知所有观察者
      this.observers.forEach(observer => observer(key));
      return Promise.resolve();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to set ${(err as BusinessError).code} by ${(err as BusinessError).message}`);
    }
  }

  /**
   * 写入数据并通知观察者
   * @param key 键
   * @param value 值
   */
  public static put(key: string, value: preferences.ValueType): Promise<void> {
    return SettingsService.getInstance().put(key, value);
  }

  // 读取数据
  public async get<T extends preferences.ValueType>(key: string, defValue: T): Promise<T> {
    if (!this.preferences) {
      return defValue;
    }

    try {
      return (this.preferences.get(key, defValue).catch(() => {
        return defValue;
      })) as T;
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

  /**
   * 读取数据
   * @param key 键
   * @param defValue 默认值
   */
  public static getSync<T extends preferences.ValueType>(key: string, defValue: T): T {
    return SettingsService.getInstance().getSync(key, defValue);
  }

  // 读取数据
  public static get<T extends preferences.ValueType>(key: string, defValue: T, callback: (value: T) => void): void {
    SettingsService.getInstance().get(key, defValue).then(value => {
      callback(value);
    });
  }

  /**
   * 删除数据
   * @param key
   */
  public deleteSync(key: string) {
    try {
      this.preferences?.deleteSync(key);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to delete ${key}. Code: ${error}`);
    }
    try {
      this.preferences?.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to flush ${key}. Code: ${error}`);
    }
  }

  /**
   * 删除数据
   * @param key
   */
  public static deleteSync(key: string) {
    SettingsService.getInstance().deleteSync(key);
  }

  /**
   * 删除数据
   * @param key
   */
  public delete(key: string): Promise<void> {
    return new Promise<void>(async resolve => {
      if (!this.preferences) {
        return resolve();
      }
      this.deleteSync(key);
      return resolve();
    });
  }

  /**
   * 删除数据
   * @param key
   */
  public static delete(key: string): Promise<void> {
    return SettingsService.getInstance().delete(key);
  }

  /**
   * 获取所有的数据
   * @returns
   */
  public static getAll(): Object {
    try {
      const pref = SettingsService.getInstance().preferences;
      if (!pref) {
        return new Object();
      }
      return pref.getAllSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get all. Code: ${error}`);
    }
    return new Object();
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

  public static isFingerprintAuthEnable(): boolean {
    return SettingsService.getInstance()
      .getSync(SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN, SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN_DEFAULT);
  }

  public static isFaceAuthEnable(): boolean {
    return SettingsService.getInstance().getSync(SettingsService.KEY_SECURITY_FACE_LOGIN, SettingsService.KEY_SECURITY_FACE_LOGIN_DEFAULT);
  }

  public static isSearchHistoryEnable(): boolean {
    return SettingsService.getInstance()
      .getSync(SettingsService.KEY_SECURITY_SEARCH_HISTORY_ENABLE, SettingsService.KEY_SECURITY_SEARCH_HISTORY_ENABLE_DEFAULT);
  }
}
