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
  value: string;
}

/**
 * 主题相关常量
 */
export class ThemeConstants {
  /**
   * 主题模式选项
   */
  static readonly THEME_OPTIONS: ThemeOption[] = [
    { value: '跟随系统', type: ThemeMode.SYSTEM },
    { value: '浅色', type: ThemeMode.LIGHT },
    { value: '深色', type: ThemeMode.DARK }
  ];

  /**
   * 根据值获取排序选项
   * @param value 值
   * @returns 排序选项
   */
  public static getThemeOptionByType(type: ThemeMode): string {
    return ThemeConstants.THEME_OPTIONS.find((option) => option.type === type)?.value ?? ThemeConstants.THEME_OPTIONS[0].value;
  }
}
