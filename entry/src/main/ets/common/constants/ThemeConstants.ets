/**
 * 主题模式枚举
 */
export enum ThemeMode {
  SYSTEM = 'SYSTEM', // 跟随系统
  LIGHT = 'LIGHT', // 浅色主题
  DARK = 'DARK' // 深色主题
}

/**
 * 主题选项接口
 */
export interface ThemeOption {
  type: ThemeMode;
  value: Resource;
}

/**
 * 主题相关常量
 */
export class ThemeConstants {
  /**
   * 主题模式选项
   */
  static readonly THEME_OPTIONS: ThemeOption[] = [
    { value: $r('app.string.ThemeConstants_system'), type: ThemeMode.SYSTEM },
    { value: $r('app.string.ThemeConstants_light'), type: ThemeMode.LIGHT },
    { value: $r('app.string.ThemeConstants_dark'), type: ThemeMode.DARK }
  ];

  /**
   * 根据值获取排序选项
   * @param value 值
   * @returns 排序选项
   */
  public static getThemeOptionByType(type: ThemeMode): Resource {
    return ThemeConstants.THEME_OPTIONS.find((option) => option.type === type)?.value ?? ThemeConstants.THEME_OPTIONS[0].value;
  }
}
