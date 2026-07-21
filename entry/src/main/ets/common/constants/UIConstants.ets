/**
 * UI通用常量
 *
 * 职责：管理UI通用尺寸、圆角、阴影、间距等配置
 */
export class UIConstants {
  // ==================== 宽度阈值 ====================

  /**
   * 内容最大宽度阈值（vp）
   * 屏幕宽度 > 此值时使用固定宽度，否则使用100%
   */
  static readonly CONTENT_MAX_WIDTH_THRESHOLD: number = 600;

  /**
   * 弹框最大宽度（vp）
   */
  static readonly DIALOG_MAX_WIDTH: number = 600;

  /**
   * 弹框最大高度比例
   */
  static readonly DIALOG_MAX_HEIGHT_RATIO: string = '80%';

  // ==================== 圆角大小 ====================

  /**
   * 圆角 - 小（vp）
   */
  static readonly CORNER_RADIUS_SMALL: number = 8;

  /**
   * 圆角 - 中（vp）
   */
  static readonly CORNER_RADIUS_MEDIUM: number = 12;

  /**
   * 圆角 - 大（vp）
   */
  static readonly CORNER_RADIUS_LARGE: number = 16;

  // ==================== 图标大小 ====================

  /**
   * 图标大小 - 小（vp）
   */
  static readonly ICON_SIZE_SMALL: number = 16;

  /**
   * 图标大小 - 中（vp）
   */
  static readonly ICON_SIZE_MEDIUM: number = 24;

  /**
   * 图标大小 - 大（vp）
   */
  static readonly ICON_SIZE_LARGE: number = 32;

  // ==================== 阴影参数 ====================

  /**
   * 阴影半径（vp）
   */
  static readonly SHADOW_RADIUS: number = 20;

  /**
   * 阴影X偏移（vp）
   */
  static readonly SHADOW_OFFSET_X: number = 0;

  /**
   * 阴影Y偏移（vp）
   */
  static readonly SHADOW_OFFSET_Y: number = 4;

  // ==================== 内边距 ====================

  /**
   * 宽屏内边距（vp）
   */
  static readonly PADDING_WIDE: number = 24;

  /**
   * 窄屏内边距（vp）
   */
  static readonly PADDING_NARROW: number = 16;

  // ==================== 组件高度 ====================

  /**
   * 列表项高度（vp）
   */
  static readonly LIST_ITEM_HEIGHT: number = 48;

  /**
   * 按钮高度（vp）
   */
  static readonly BUTTON_HEIGHT: number = 44;

  /**
   * 输入框高度（vp）
   */
  static readonly INPUT_HEIGHT: number = 44;

  /**
   * 分割线高度（vp）
   */
  static readonly DIVIDER_HEIGHT: number = 1;
}
