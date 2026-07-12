import { display } from '@kit.ArkUI';
import { UIConstants } from '../constants/UIConstants';

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
   */
  static calculateMaxWidth(context: UIContext): { width: string | number; isPercentage: boolean } {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      const screenWidthVp = context.px2vp(displayInfo.width);

      if (screenWidthVp > UIConstants.CONTENT_MAX_WIDTH_THRESHOLD) {
        return { width: UIConstants.CONTENT_MAX_WIDTH_THRESHOLD, isPercentage: false };
      } else {
        return { width: '100%', isPercentage: true };
      }
    } catch (error) {
      return { width: UIConstants.CONTENT_MAX_WIDTH_THRESHOLD, isPercentage: false };
    }
  }

  /**
   * 计算弹框宽度（自适应）
   * 复用 calculateMaxWidth 逻辑
   */
  static calculateDialogWidth(context: UIContext): { width: string | number; isPercentage: boolean } {
    return this.calculateMaxWidth(context);
  }

  /**
   * 判断是否使用百分比宽度
   */
  static usePercentageWidth(context: UIContext): boolean {
    const { isPercentage } = this.calculateMaxWidth(context);
    return isPercentage;
  }

  /**
   * 获取最大宽度常量
   */
  static getMaxWidth(): number {
    return UIConstants.CONTENT_MAX_WIDTH_THRESHOLD;
  }
}
