/**
 * 设置弹框样式常量
 *
 * 职责：管理设置弹框的尺寸、样式等配置
 */
export class SettingDialogConstants {
  /**
   * 弹框最大宽度（vp）
   */
  static readonly DIALOG_MAX_WIDTH: number = 700;

  /**
   * 弹框最大高度比例
   */
  static readonly DIALOG_MAX_HEIGHT_RATIO: string = '80%';

  /**
   * 标题栏高度（vp）
   */
  static readonly HEADER_HEIGHT: number = 56;

  /**
   * 关闭按钮大小（vp）
   */
  static readonly CLOSE_BUTTON_SIZE: number = 24;

  /**
   * 圆角大小（vp）
   */
  static readonly CORNER_RADIUS: number = 16;

  /**
   * 内边距 - 宽屏（vp）
   */
  static readonly PADDING_WIDE: number = 24;

  /**
   * 内边距 - 窄屏（vp）
   */
  static readonly PADDING_NARROW: number = 16;

  /**
   * 标题字体大小（fp）
   */
  static readonly TITLE_FONT_SIZE: number = 18;

  /**
   * 阴影半径（vp）
   */
  static readonly SHADOW_RADIUS: number = 20;

  /**
   * 阴影Y偏移（vp）
   */
  static readonly SHADOW_OFFSET_Y: number = 4;
}
