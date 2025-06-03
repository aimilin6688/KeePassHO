import { window } from '@kit.ArkUI';
import { ThemeMode } from '../constants/ThemeConstants';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';

/**
 * 主题变更监听器类型
 */
type ThemeChangeListener = (isDarkMode: boolean) => void;

/**
 * 主题管理器
 */
export default class ThemeManager {
  private static instance: ThemeManager;
  private currentThemeMode: ThemeMode = ThemeMode.SYSTEM;
  private systemDarkMode: boolean = false;
  private themeChangeListeners: ThemeChangeListener[] = [];
  private context: common.UIAbilityContext | null = null;

  private constructor() {
    // 系统暗色模式变化监听将在初始化时设置
  }

  /**
   * 初始化主题管理器
   * @param context UIAbilityContext
   */
  public init(context: common.UIAbilityContext): void {
    this.context = context;
    // 监听系统暗色模式变化
    if (this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK)  {
      this.systemDarkMode = true;
      this.applyTheme();
      this.notifyThemeChangeListeners();
    }
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): ThemeManager {
    if (!ThemeManager.instance) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }

  /**
   * 设置主题模式
   * @param mode 主题模式
   */
  public async setThemeMode(mode: ThemeMode): Promise<void> {
    this.currentThemeMode = mode;
    await this.applyTheme();
    this.notifyThemeChangeListeners();
  }

  /**
   * 获取当前主题模式
   */
  public getThemeMode(): ThemeMode {
    return this.currentThemeMode;
  }

  /**
   * 获取当前是否为深色模式
   */
  public isDarkMode(): boolean {
    switch (this.currentThemeMode) {
      case ThemeMode.SYSTEM:
        return this.systemDarkMode;
      case ThemeMode.DARK:
        return true;
      case ThemeMode.LIGHT:
        return false;
      default:
        return false;
    }
  }

  /**
   * 应用主题
   */
  private async applyTheme(): Promise<void> {
    if (!this.context) {
      console.error('ThemeManager not initialized with context');
      return;
    }

    try {
      const isDark = this.isDarkMode();
      const mainWindow = await window.getLastWindow(this.context);

      // 使用更新后的API和属性名
      await mainWindow.setWindowSystemBarProperties({
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
        navigationBarContentColor: isDark ? '#FFFFFF' : '#000000'
      });
    } catch (err) {
      console.error(`Failed to apply theme: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
    }
  }

  /**
   * 添加主题变更监听器
   * @param listener 监听器函数
   */
  public addThemeChangeListener(listener: ThemeChangeListener): void {
    if (!this.themeChangeListeners.includes(listener)) {
      this.themeChangeListeners.push(listener);
    }
  }

  public removeThemeChangeListenerAll(): void{
    this.themeChangeListeners.splice(0, this.themeChangeListeners.length);
  }

  /**
   * 移除主题变更监听器
   * @param listener 监听器函数
   */
  public removeThemeChangeListener(listener: ThemeChangeListener): void {
    const index = this.themeChangeListeners.indexOf(listener);
    if (index !== -1) {
      this.themeChangeListeners.splice(index, 1);
    }
  }

  /**
   * 通知所有主题变更监听器
   */
  private notifyThemeChangeListeners(): void {
    const isDark = this.isDarkMode();
    for (const listener of this.themeChangeListeners) {
      listener(isDark);
    }
  }
}
