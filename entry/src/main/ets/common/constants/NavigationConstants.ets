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
  static readonly NAV_BAR_WIDTH_RANGE: [number, number] = [240, 700];

  /**
   * 导航栏默认宽度（vp）
   */
  static readonly DEFAULT_NAV_BAR_WIDTH: number = 360;

  /**
   * 内容区最小宽度（vp）
   * 用于 Navigation 组件的 minContentWidth 属性
   */
  static readonly MIN_CONTENT_WIDTH: number = 400;

  /**
   * 分栏模式切换阈值（vp）
   * 分栏时需同时容纳「实际导航栏默认宽 + 内容区最小宽」，故阈值 = DEFAULT_NAV_BAR_WIDTH + MIN_CONTENT_WIDTH。
   * 这样强制分栏时内容区不会小于 minContentWidth，避免「导航栏固定后内容被挤窄」的问题。
   * 注意：当前采用显式 NavigationMode.Split/Stack 驱动（而非 NavigationMode.Auto），
   * 因此该阈值由应用侧统一判定，避免与框架 Auto 的内部阈值不一致。
   */
  static readonly SPLIT_MODE_THRESHOLD: number = NavigationConstants.DEFAULT_NAV_BAR_WIDTH + NavigationConstants.MIN_CONTENT_WIDTH;

  /**
   * 分栏的高宽比阈值
   * 高宽比（height / width）高于该值的竖长窗口按单栏展示，语义与 AUTO_WITH_ASPECT_RATIO 保持一致。
   */
  static readonly SPLIT_ASPECT_RATIO_THRESHOLD: number = 1.2;

  /**
   * 根页面列表
   * 这些页面会创建新的导航栈，决定导航模式
   */
  static readonly ROOT_PAGES: string[] = [
    'Index',         // 首页
    'DatabaseView',  // 数据库视图
    'TotpView',      // TOTP 时间令牌视图
    'Settings'       // 设置
  ];

  /**
   * 判断是否为根页面
   *
   * @param pageName 页面名称
   * @returns true 表示是根页面
   */
  static isRootPage(pageName: string): boolean {
    return NavigationConstants.ROOT_PAGES.includes(pageName);
  }
}