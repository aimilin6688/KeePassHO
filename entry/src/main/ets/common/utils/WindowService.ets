import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavigationConstants } from '../constants/NavigationConstants';

const DOMAIN = 0x0000;
const TAG = 'WindowService';

/**
 * 窗口信息（响应式断点的单一事实来源）
 *
 * 通过 @Observed 包装，供 UI 层通过 @State/@ObjectLink 订阅。
 * 字段变化（windowSizeChange 触发 refresh）时，会自动通知订阅方刷新布局。
 */
@Observed
export class WindowInfo {
  /** 窗口宽度（vp） */
  public windowWidthVp: number = 0;
  /** 窗口高度（vp） */
  public windowHeightVp: number = 0;
  /** 横向断点 */
  public widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_SM;
  /** 纵向断点（按高宽比） */
  public heightBp: HeightBreakpoint = HeightBreakpoint.HEIGHT_MD;
  /** 是否处于分栏模式（宽度 + 高宽比综合判定） */
  public isSplitMode: boolean = false;
}

/**
 * 窗口服务（单例）
 *
 * 职责：
 * 1. 统一监听窗口尺寸变化，维护 WindowInfo（断点 + 分栏判定）。
 * 2. 提供分栏判定的单一来源，避免各页面手写宽度阈值导致的不一致。
 */
export class WindowService {
  private static instance: WindowService;
  private windowClass: window.Window | undefined = undefined;
  private uiContext: UIContext | undefined = undefined;
  private inited: boolean = false;

  /** 响应式窗口信息（UI 层通过 @State 引用以订阅变化） */
  public info: WindowInfo = new WindowInfo();

  private constructor() {}

  static getInstance(): WindowService {
    if (!WindowService.instance) {
      WindowService.instance = new WindowService();
    }
    return WindowService.instance;
  }

  /**
   * 初始化：绑定窗口实例并注册尺寸监听，随后立即刷新一次。
   * 需在组件 aboutToAppear 中调用（此时才能获取到 UIContext）。
   */
  init(context: common.UIAbilityContext, uiContext: UIContext): void {
    this.uiContext = uiContext;
    if (this.inited) {
      return;
    }
    try {
      this.windowClass = context.windowStage.getMainWindowSync();
      if (this.windowClass) {
        this.windowClass.on('windowSizeChange', (size: window.Size) => {
          hilog.debug(DOMAIN, TAG, `windowSizeChange: ${size.width}x${size.height}`);
          this.refresh();
        });
        this.inited = true;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `init windowService failed: ${error?.code}, ${error?.message}`);
    }
    this.refresh();
  }

  /**
   * 刷新窗口尺寸、断点与分栏判定。
   */
  refresh(): void {
    try {
      if (!this.windowClass || !this.uiContext) {
        return;
      }
      const rect = this.windowClass.getWindowProperties().windowRect;
      this.info.windowWidthVp = this.uiContext.px2vp(rect.width);
      this.info.windowHeightVp = this.uiContext.px2vp(rect.height);
      this.info.widthBp = this.mapWidthBreakpoint(this.info.windowWidthVp);

      const aspect = rect.height > 0 ? rect.height / rect.width : 1;
      this.info.heightBp = this.mapHeightBreakpoint(aspect);
      this.info.isSplitMode = this._resolveSplitMode(this.info.windowWidthVp, aspect);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `refresh failed: ${error?.code}, ${error?.message}`);
    }
  }

  private mapWidthBreakpoint(vp: number): WidthBreakpoint {
    if (vp < 320) {
      return WidthBreakpoint.WIDTH_XS;
    }
    if (vp < 600) {
      return WidthBreakpoint.WIDTH_SM;
    }
    if (vp < 840) {
      return WidthBreakpoint.WIDTH_MD;
    }
    if (vp < 1440) {
      return WidthBreakpoint.WIDTH_LG;
    }
    return WidthBreakpoint.WIDTH_XL;
  }

  private mapHeightBreakpoint(aspect: number): HeightBreakpoint {
    if (aspect < 0.8) {
      return HeightBreakpoint.HEIGHT_SM;
    }
    if (aspect < 1.2) {
      return HeightBreakpoint.HEIGHT_MD;
    }
    return HeightBreakpoint.HEIGHT_LG;
  }

  private _resolveSplitMode(widthVp: number, aspect: number): boolean {
    // 宽度不足以容纳「导航栏最小宽 + 内容区最小宽」 → 单栏
    if (widthVp < NavigationConstants.SPLIT_MODE_THRESHOLD) {
      return false;
    }
    // 高宽比 > 1.2 的竖长窗口（如手机竖屏）按单栏展示，避免分栏被挤压。
    // 该语义与 NavigationMode.AUTO_WITH_ASPECT_RATIO 一致，但此处由应用侧显式判定
    // （AppNavigation 使用显式 NavigationMode.Split/Stack 驱动，未启用 Auto 模式）。
    if (aspect > NavigationConstants.SPLIT_ASPECT_RATIO_THRESHOLD) {
      return false;
    }
    return true;
  }
}