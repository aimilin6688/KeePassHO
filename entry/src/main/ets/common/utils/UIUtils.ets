import { display } from '@kit.ArkUI';
import { UIConstants } from '../constants/UIConstants';

/**
 * 宽度计算结果接口
 */
export interface WidthResult {
  width: string | number;
  isPercentage: boolean;
}

/**
 * UI 工具类
 */
export class UIUtils {
  /**
   * 计算内容最大宽度
   *
   * 规则：
   * - 屏幕宽度 > 700vp：使用固定宽度 700vp
   * - 屏幕宽度 ≤ 700vp：使用 100% 宽度
   *
   * @param context UIContext
   * @param windowWidth 可选的窗口宽度（px），如果不传则使用屏幕宽度
   */
  static calculateMaxWidth(context: UIContext, windowWidth?: number): WidthResult {
    try {
      let widthVp: number;
      if (windowWidth !== undefined) {
        // 使用传入的窗口宽度
        widthVp = context.px2vp(windowWidth);
      } else {
        // 使用屏幕宽度
        const displayInfo = display.getDefaultDisplaySync();
        widthVp = context.px2vp(displayInfo.width);
      }

      if (widthVp > UIConstants.CONTENT_MAX_WIDTH_THRESHOLD) {
        const result: WidthResult = { width: UIConstants.CONTENT_MAX_WIDTH_THRESHOLD, isPercentage: false };
        return result;
      } else {
        const result: WidthResult = { width: '100%', isPercentage: true };
        return result;
      }
    } catch (error) {
      const result: WidthResult = { width: UIConstants.CONTENT_MAX_WIDTH_THRESHOLD, isPercentage: false };
      return result;
    }
  }

  /**
   * 计算弹框宽度（自适应）
   * 复用 calculateMaxWidth 逻辑
   *
   * @param context UIContext
   * @param windowWidth 可选的窗口宽度（px），如果不传则使用屏幕宽度
   */
  static calculateDialogWidth(context: UIContext, windowWidth?: number): WidthResult {
    return UIUtils.calculateMaxWidth(context, windowWidth);
  }

  /**
   * 判断是否使用百分比宽度
   */
  static usePercentageWidth(context: UIContext): boolean {
    const result = UIUtils.calculateMaxWidth(context);
    return result.isPercentage;
  }

  /**
   * 获取最大宽度常量
   */
  static getMaxWidth(): number {
    return UIConstants.CONTENT_MAX_WIDTH_THRESHOLD;
  }
}
