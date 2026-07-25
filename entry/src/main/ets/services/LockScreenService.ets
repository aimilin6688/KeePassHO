import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EventBus } from './EventBus';

const DOMAIN = 0x0000;
const TAG = 'LockScreenService';

/**
 * 锁屏管理服务
 * 职责：管理锁屏状态，通过 EventBus 通知 UI 层显示/隐藏锁屏遮罩
 */
export class LockScreenService {
  /** 解锁动作事件名 */
  static readonly EVENT_LOCK_ACTION = 'lock_screen_action';
  private static onActionCallback: ((action: string) => void) | null = null;

  /**
   * 初始化锁屏服务
   * @param windowStage WindowStage 实例
   * @param onAction 动作回调（用于处理 unlock/close_database）
   */
  static init(windowStage: window.WindowStage, onAction: (action: string) => void): void {
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
    LockScreenService.onActionCallback = null;
    EventBus.off(LockScreenService.EVENT_LOCK_ACTION);
    hilog.info(DOMAIN, TAG, 'LockScreenService destroyed');
  }

  /**
   * 展示锁屏
   * @param isManual 是否为手动锁定
   */
  static async showLockWindow(isManual: boolean): Promise<void> {
    hilog.info(DOMAIN, TAG, 'showLockWindow called, isManual: ' + isManual);
    // 保存锁定状态到 AppStorage
    AppStorage.setOrCreate('lockIsManual', isManual);
    // 发送锁屏事件，通知 AppNavigation 显示锁屏遮罩
    EventBus.emit<boolean>('lock_screen', isManual);
    hilog.info(DOMAIN, TAG, 'lock_screen event emitted');
  }

  /**
   * 处理锁屏动作
   */
  private static handleAction(action: string): void {
    hilog.info(DOMAIN, TAG, 'handleAction: ' + action);

    // 发送解锁事件，通知 AppNavigation 隐藏锁屏遮罩
    if (action === 'unlock' || action === 'close_database') {
      EventBus.emit<void>('unlock_screen');
    }

    // 清理状态
    AppStorage.delete('lockIsManual');

    // 通知回调处理后续动作
    if (LockScreenService.onActionCallback) {
      LockScreenService.onActionCallback(action);
    }
  }
}
