import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { EventBus } from './EventBus';
import { ClipboardUtils } from '../common/utils/ClipboardUtils';

const DOMAIN = 0x0000;
const TAG = 'LockScreenService';
const LOCK_WINDOW_NAME = 'lockWindow';

/**
 * 锁屏管理服务
 * 职责：管理锁屏子窗口的创建/销毁、处理解锁动作事件
 *
 * 锁屏以应用子窗口实现：窗口级覆盖，位于主窗口所有内容之上
 * （页面、分栏、自定义弹窗 CustomDialog/AlertDialog 等均在其下）；
 * 主窗口状态完全不动，解锁销毁子窗口后原样恢复锁屏前的界面状态。
 */
export class LockScreenService {
  /** 解锁动作事件名 */
  static readonly EVENT_LOCK_ACTION = 'lock_screen_action';
  /** 锁屏显示事件名（SessionManager 等监听） */
  static readonly EVENT_LOCK_SCREEN = 'lock_screen';
  private static windowStage: window.WindowStage | null = null;
  private static onActionCallback: ((action: string) => void) | null = null;
  private static lockWindow: window.Window | null = null;

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
    LockScreenService.lockWindow = null;
    EventBus.off(LockScreenService.EVENT_LOCK_ACTION);
    hilog.info(DOMAIN, TAG, 'LockScreenService destroyed');
  }

  /**
   * 展示锁屏子窗口
   * @param isManual 是否为手动锁定
   */
  static async showLockWindow(isManual: boolean): Promise<void> {
    if (!LockScreenService.windowStage) {
      hilog.warn(DOMAIN, TAG, 'showLockWindow: windowStage is null');
      return;
    }
    // 已锁屏（子窗口存在），不重复创建
    if (LockScreenService.lockWindow) {
      hilog.info(DOMAIN, TAG, 'showLockWindow: lock window already exists');
      return;
    }
    hilog.info(DOMAIN, TAG, 'showLockWindow called, isManual: ' + isManual);

    // 锁库即净：立即清除剪贴板并取消未执行的清除任务
    ClipboardUtils.forceClearNow();
    // 保存锁定状态
    AppStorage.setOrCreate('lockIsManual', isManual);
    AppStorage.setOrCreate('isLocked', true);

    try {
      // 清理可能残留的僵尸锁屏窗口（防止重名创建失败）
      await LockScreenService.destroyStaleWindow();

      const mainWindow = LockScreenService.windowStage.getMainWindowSync();
      const rect = mainWindow.getWindowProperties().windowRect;
      const lockWindow = await LockScreenService.windowStage.createSubWindow(LOCK_WINDOW_NAME);
      LockScreenService.lockWindow = lockWindow;
      // 子窗口大小与主窗口一致（不能用屏幕尺寸：PC 自由窗口下应用窗口 ≠ 整屏）
      await lockWindow.resize(rect.width, rect.height);
      // 非自由窗口模式：子窗口相对主窗口定位，(0,0) 即主窗口左上角
      await lockWindow.moveWindowTo(0, 0);
      // 自由窗口模式（PC/平板）：子窗口左上角跟随主窗口左上角（须在 moveWindowTo 之后调用）
      try {
        await lockWindow.setRelativePositionToParentWindowEnabled(true, window.WindowAnchor.TOP_START, 0, 0);
      } catch (error) {
        // 非自由窗口模式不支持该能力，moveWindowTo(0,0) 已完成对齐
        hilog.info(DOMAIN, TAG, 'setRelativePositionToParentWindowEnabled skip: %{public}s', `${error}`);
      }
      await lockWindow.setUIContent('pages/UnLockDatabase');
      await lockWindow.showWindow();
      hilog.info(DOMAIN, TAG, 'lock window shown');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'showLockWindow failed: %{public}s', `${error}`);
      LockScreenService.lockWindow = null;
    }

    // 发送锁库事件（SessionManager 等监听）
    EventBus.emit<boolean>(LockScreenService.EVENT_LOCK_SCREEN, isManual);
  }

  /**
   * 关闭锁屏子窗口（解锁、关闭数据库、新意图打开其他数据库时调用）
   */
  static closeLockWindow(): void {
    AppStorage.setOrCreate('isLocked', false);
    const lockWindow = LockScreenService.lockWindow;
    LockScreenService.lockWindow = null;
    if (lockWindow) {
      lockWindow.destroyWindow().catch((error: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'destroy lock window failed: %{public}s', error.message);
      });
      hilog.info(DOMAIN, TAG, 'lock window destroyed');
      return;
    }
    // 无引用时兜底清理（如服务重建后的残留窗口）
    LockScreenService.destroyStaleWindow().catch(() => {
    });
  }

  /**
   * 按名称销毁残留锁屏窗口
   */
  private static async destroyStaleWindow(): Promise<void> {
    try {
      const stale = window.findWindow(LOCK_WINDOW_NAME);
      await stale.destroyWindow();
      hilog.info(DOMAIN, TAG, 'stale lock window destroyed');
    } catch {
      // 无残留窗口
    }
  }

  /**
   * 处理锁屏动作
   */
  private static handleAction(action: string): void {
    hilog.info(DOMAIN, TAG, 'handleAction: ' + action);

    // 关闭数据库即净：立即清除剪贴板
    if (action === 'close_database') {
      ClipboardUtils.forceClearNow();
    }

    // 解锁/关库：销毁锁屏子窗口，恢复锁屏前的主窗口状态
    if (action === 'unlock' || action === 'close_database') {
      LockScreenService.closeLockWindow();
    }

    // 清理状态
    AppStorage.delete('lockIsManual');

    // 通知回调处理后续动作
    if (LockScreenService.onActionCallback) {
      LockScreenService.onActionCallback(action);
    }
  }
}
