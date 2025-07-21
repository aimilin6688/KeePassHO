import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { ThemeMode } from '../common/constants/ThemeConstants';
import ThemeManager from '../common/utils/ThemeManager';
import common from '@ohos.app.ability.common';
import { SortMode } from '../common/constants/SortConstants';

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'SettingsService';

export class SettingsService {
  private static instance: SettingsService = new SettingsService();
  private preferences: preferences.Preferences | null = null;
  private static readonly PREFERENCES_NAME = 'settings';

  // 设置键名
  public static readonly KEY_THEME_MODE = 'themeMode';
  public static readonly KEY_DARK_MODE = 'darkMode'; // 保留向后兼容
  public static readonly KEY_SORT_BY = 'sortBy';

  // 观察者列表
  private observers: ((key: string) => void)[] = [];

  private constructor() {}

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
    if (!this.preferences) return;
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
    if (!this.preferences) return ThemeMode.SYSTEM;
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
    if (!this.preferences) return;

    try {
    await this.preferences.put(key, value);
    await this.preferences.flush(); // 重要！确保数据持久化
    // 通知所有观察者
    this.observers.forEach(observer => observer(key));
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to set ${(err as BusinessError).code} by ${(err as BusinessError).message}`);
    }
  }

  // 读取数据
  public async get<T extends preferences.ValueType>(key: string, defValue: T): Promise<T> {
    if (!this.preferences) return defValue;

    try {
      return (await this.preferences.get(key, defValue)) as T;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to get value. Code: ${(err as BusinessError).code}`);
      return defValue;
    }
  }

  // 注册观察者
  public registerObserver(observer: (key: string) => void): void {
    this.observers.push(observer);
  }

  // 移除观察者
  public unregisterObserver(observer: (key: string) => void): void {
    const index = this.observers.indexOf(observer);
    if (index !== -1) {
      this.observers.splice(index, 1);
    }
  }
}
