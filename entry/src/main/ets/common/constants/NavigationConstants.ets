/**
 * 导航相关常量
 *
 * 职责：管理导航组件的尺寸、阈值、根页面列表等配置
 */
export class NavigationConstants {
  /**
   * 导航栏宽度范围 [最小宽度, 最大宽度]
   * 用于 Navigation 组件的 navBarWidthRange 属性
   */
  static readonly NAV_BAR_WIDTH_RANGE: [number, number] = [240, 360];

  /**
   * 导航栏默认宽度（vp）
   */
  static readonly DEFAULT_NAV_BAR_WIDTH: number = 280;

  /**
   * 内容区最小宽度（vp）
   * 用于 Navigation 组件的 minContentWidth 属性
   */
  static readonly MIN_CONTENT_WIDTH: number = 400;

  /**
   * 分栏模式切换阈值（vp）
   * 屏幕宽度 >= 此值时自动切换为分栏模式
   * 用于 NavigationMode.Auto 的判断
   */
  static readonly SPLIT_MODE_THRESHOLD: number = 600;

  /**
   * 根页面列表
   * 这些页面会创建新的导航栈，决定导航模式
   */
  static readonly ROOT_PAGES: string[] = [
    'Index',         // 首页
    'DatabaseView',  // 数据库视图
    'Settings'       // 设置
  ];

  /**
   * 判断是否为根页面
   *
   * @param pageName 页面名称
   * @returns true 表示是根页面
   */
  static isRootPage(pageName: string): boolean {
    return this.ROOT_PAGES.includes(pageName);
  }
}