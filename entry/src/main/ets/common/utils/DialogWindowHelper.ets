import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'DialogWindowHelper';

/**
 * 弹框窗口大小变化监听回调
 */
export type WindowSizeChangeCallback = (width: number, height: number) => void;

/**
 * 弹框窗口助手类
 * 用于管理弹框的窗口大小监听
 */
export class DialogWindowHelper {
  private windowClass: window.Window | undefined = undefined;
  private callback: WindowSizeChangeCallback | undefined = undefined;
  private currentWindowWidth: number = 0;

  /**
   * 获取当前窗口宽度（px）
   */
  get windowWidth(): number {
    return this.currentWindowWidth;
  }

  /**
   * 注册窗口大小变化监听
   *
   * @param context UIContext 的 HostContext
   * @param callback 窗口大小变化回调
   * @returns 是否注册成功
   */
  register(context: UIContext, callback: WindowSizeChangeCallback): boolean {
    try {
      const abilityContext = context.getHostContext() as common.UIAbilityContext;
      this.windowClass = abilityContext.windowStage.getMainWindowSync();

      if (this.windowClass) {
        // 获取当前窗口宽度
        const windowSize = this.windowClass.getWindowProperties().windowRect;
        this.currentWindowWidth = windowSize.width;
        // 保存回调
        this.callback = callback;
        // 注册窗口大小变化监听
        this.windowClass.on('windowSizeChange', (size: window.Size) => {
          this.currentWindowWidth = size.width;
          if (this.callback) {
            this.callback(size.width, size.height);
          }
        });

        return true;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'register error: %{public}s', String(error));
    }
    return false;
  }

  /**
   * 取消窗口大小变化监听
   */
  unregister(): void {
    if (this.windowClass) {
      try {
        this.windowClass.off('windowSizeChange');
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'unregister error: %{public}s', String(error));
      }
      this.windowClass = undefined;
      this.callback = undefined;
      this.currentWindowWidth = 0;
    }
  }
}
