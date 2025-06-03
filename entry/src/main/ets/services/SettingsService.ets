import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';

export class SettingsService {
  private static instance: SettingsService;
  private preferences: preferences.Preferences | null = null;
  private static readonly PREFERENCES_NAME = 'settings';

  // 设置键名
  private static readonly KEY_DARK_MODE = 'darkMode';
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
   */
  public async init(): Promise<void> {
    try {
      this.preferences = await preferences.getPreferences(globalThis.context, SettingsService.PREFERENCES_NAME);
    } catch (err) {
      console.error(`Failed to get preferences: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
    }
  }

  /**
   * 设置深色模式
   * @param enabled 是否启用深色模式
   */
  public async setDarkMode(enabled: boolean): Promise<void> {
    if (!this.preferences) return;
    try {
      await this.preferences.put(SettingsService.KEY_DARK_MODE, enabled);
      await this.preferences.flush();
    } catch (err) {
      console.error(`Failed to set dark mode: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
    }
  }

  /**
   * 获取深色模式状态
   */
  public async isDarkMode(): Promise<boolean> {
    if (!this.preferences) return false;
    try {
      return await this.preferences.get(SettingsService.KEY_DARK_MODE, false) as boolean;
    } catch (err) {
      console.error(`Failed to get dark mode: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
      return false;
    }
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
