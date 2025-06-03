/**
 * 主题模式枚举
 */
export enum ThemeMode {
  SYSTEM = '跟随系统',  // 跟随系统
  LIGHT = '浅色',   // 浅色主题
  DARK = '深色'      // 深色主题
}

/**
 * 主题选项接口
 */
export interface ThemeOption {
  name: string;
  value: ThemeMode;
}

/**
 * 主题相关常量
 */
export class ThemeConstants {
  /**
   * 主题模式选项
   */
  static readonly THEME_OPTIONS: ThemeOption[] = [
    { name: '跟随系统', value: ThemeMode.SYSTEM },
    { name: '浅色', value: ThemeMode.LIGHT },
    { name: '深色', value: ThemeMode.DARK }
  ];
}
