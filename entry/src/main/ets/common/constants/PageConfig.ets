/**
 * 导航模式类型
 */
export enum NavigationModeType {
  /**
   * 独占模式（不分栏）
   * - 使用 NavigationMode.Stack
   * - 页面全屏显示
   * - 可以限制内容最大宽度
   * - 适用于：首页相关页面
   */
  EXCLUSIVE = 'exclusive',

  /**
   * 分栏模式
   * - 使用 NavigationMode.Auto 或 NavigationMode.Split
   * - 页面在分栏中显示
   * - 通常不限制内容宽度
   * - 适用于：数据库页面、设置页面
   */
  SPLIT = 'split',
}

/**
 * 页面配置接口
 */
export interface PageConfig {
  /**
   * 页面名称
   */
  name: string;

  /**
   * 导航模式类型
   */
  navigationMode: NavigationModeType;

  /**
   * 是否限制内容最大宽度
   * - true: 在独占模式下限制内容最大宽度
   * - false: 不限制宽度（分栏模式通常不限制）
   */
  constrainMaxWidth: boolean;

  /**
   * 内容最大宽度（vp）
   * 仅当 constrainMaxWidth 为 true 时有效
   */
  maxWidth?: number;

  /**
   * 内容区内边距（vp）
   */
  padding?: number;
}
