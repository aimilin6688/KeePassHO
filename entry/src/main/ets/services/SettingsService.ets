import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { ThemeMode } from '../common/constants/ThemeConstants';
import ThemeManager from '../common/utils/ThemeManager';
import common from '@ohos.app.ability.common';

export class SettingsService {
  private static instance: SettingsService;
  private preferences: preferences.Preferences | null = null;
  private static readonly PREFERENCES_NAME = 'settings';

  // 设置键名
  private static readonly KEY_THEME_MODE = 'themeMode';
  private static readonly KEY_DARK_MODE = 'darkMode'; // 保留向后兼容
  private static readonly KEY_GRID_VIEW = 'gridView';
  private static readonly KEY_SORT_BY = 'sortBy';

  private constructor() {}

  public static getInstance(): SettingsService {
    if (!SettingsService.instance) {
      SettingsService.instance = new SettingsService();
    }
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
      console.error(`Failed to get preferences: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
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
      console.error(`Failed to set theme mode: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
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
      console.error(`Failed to get theme mode: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
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
   * 设置网格视图
   * @param enabled 是否启用网格视图
   */
  public async setGridView(enabled: boolean): Promise<void> {
    if (!this.preferences) return;
    try {
      await this.preferences.put(SettingsService.KEY_GRID_VIEW, enabled);
      await this.preferences.flush();
    } catch (err) {
      console.error(`Failed to set grid view: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
    }
  }

  /**
   * 获取网格视图状态
   */
  public async isGridView(): Promise<boolean> {
    if (!this.preferences) return false;
    try {
      return await this.preferences.get(SettingsService.KEY_GRID_VIEW, false) as boolean;
    } catch (err) {
      console.error(`Failed to get grid view: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
      return false;
    }
  }

  /**
   * 设置排序方式
   * @param sortBy 排序方式 ('name' | 'time')
   */
  public async setSortBy(sortBy: string): Promise<void> {
    if (!this.preferences) return;
    try {
      await this.preferences.put(SettingsService.KEY_SORT_BY, sortBy);
      await this.preferences.flush();
    } catch (err) {
      console.error(`Failed to set sort by: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
    }
  }

  /**
   * 获取排序方式
   */
  public async getSortBy(): Promise<string> {
    if (!this.preferences) return 'name';
    try {
      return await this.preferences.get(SettingsService.KEY_SORT_BY, 'name') as string;
    } catch (err) {
      console.error(`Failed to get sort by: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
      return 'name';
    }
  }
}

export default SettingsService.getInstance();
