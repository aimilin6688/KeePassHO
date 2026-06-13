import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EventBus } from './EventBus';

const DOMAIN = 0x0000;
const TAG = 'LockScreenService';

/**
 * 锁屏管理服务
 * 职责：管理锁屏 SubWindow 的创建/销毁、处理解锁动作事件
 * 通过 EventBus 与 UnLockDatabase 页面通信
 */
export class LockScreenService {
  /** 解锁动作事件名 */
  static readonly EVENT_LOCK_ACTION = 'lock_screen_action';
  private static windowStage: window.WindowStage | null = null;
  private static onActionCallback: ((action: string) => void) | null = null;

  /**
   * 初始化锁屏服务
   * @param windowStage WindowStage 实例
   * @param onAction 动作回调（用于处理 unlock/close_database）
   */
  static init(windowStage: window.WindowStage, onAction: (action: string) => void): void {
    LockScreenService.windowStage = windowStage;
    LockScreenService.onActionCallback = onAction;

    // 注册 EventBus 监听（接收来自 UnLockDatabase 的动作事件）
    EventBus.on(LockScreenService.EVENT_LOCK_ACTION, (eventData) => {
      const data = eventData?.data;
      if (typeof data === 'string') {
        LockScreenService.handleAction(data);
      }
    });

    hilog.info(DOMAIN, TAG, 'LockScreenService initialized');
  }

  /**
   * 销毁锁屏服务
   */
  static destroy(): void {
    LockScreenService.windowStage = null;
    LockScreenService.onActionCallback = null;
    EventBus.off(LockScreenService.EVENT_LOCK_ACTION);
    hilog.info(DOMAIN, TAG, 'LockScreenService destroyed');
  }

  /**
   * 展示锁屏 SubWindow
   * @param isManual 是否为手动锁定
   */
  static async showLockWindow(isManual: boolean): Promise<void> {
    if (!LockScreenService.windowStage) {
      hilog.warn(DOMAIN, TAG, 'showLockWindow: windowStage is null');
      return;
    }

    LockScreenService.closeLockWindow();

    try {
      AppStorage.setOrCreate('lockIsManual', isManual);
      const defaultDisplay = display.getDefaultDisplaySync();
      const screenWidth = defaultDisplay.width;
      const screenHeight = defaultDisplay.height;
      const lockWindow: window.Window = await LockScreenService.windowStage.createSubWindow('lockWindow');
      await lockWindow.setWindowLayoutFullScreen(true);
      await lockWindow.resize(screenWidth, screenHeight);
      await lockWindow.moveWindowTo(0, 0);
      await lockWindow.setUIContent('pages/UnLockDatabase');
      await lockWindow.showWindow();
      hilog.info(DOMAIN, TAG, 'lockWindow shown successfully');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'showLockWindow failed: ' + error?.message);
      AppStorage.setOrCreate('lockIsManual', isManual);
    }
  }

  static async closeLockWindow() {
    // 先销毁旧的锁屏窗口（防止僵尸窗口残留）
    try {
      const oldWindow = window.findWindow('lockWindow');
      oldWindow.destroyWindow().catch((error: Error) => {
        hilog.info(DOMAIN, TAG, 'destroyed existing lockWindow error:' + error?.message);
      });
      hilog.info(DOMAIN, TAG, 'destroyed existing lockWindow');
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'destroy lock window failed: ' + error?.message);
    }
  }

  /**
   * 处理锁屏动作
   * 从 Ability 层面销毁子窗口（比从子窗口内部自销毁更可靠）
   */
  private static handleAction(action: string): void {
    hilog.info(DOMAIN, TAG, 'handleAction: ' + action);

    LockScreenService.closeLockWindow();

    // 清理状态
    AppStorage.delete('lockIsManual');

    // 通知回调处理后续动作
    if (LockScreenService.onActionCallback) {
      LockScreenService.onActionCallback(action);
    }
  }
}
