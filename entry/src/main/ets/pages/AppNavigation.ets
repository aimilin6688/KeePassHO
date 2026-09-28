import { NavigationManager, WindowService, WindowInfo } from '../common/utils';
import { NavigationModeType } from '../common/constants/PageConfig';
import { NavigationConstants } from '../common/constants/NavigationConstants';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { Index } from './Index';
import { Settings } from './setting/Settings';
import { DatabaseView } from './DatabaseView';
import { TotpView } from './TotpView';
import { UnLockDatabase } from './UnLockDatabase';
import { EventBus } from '../services/EventBus';
import { LockScreenService } from '../services/LockScreenService';

const DOMAIN = 0x0000;
const TAG = 'AppNavigation';

@Entry
@Component
struct AppNavigation {
  private navManager: NavigationManager = NavigationManager.getInstance();

  // 使用 NavigationManager 中的导航栈
  private indexNavPathStack: NavPathStack = NavigationManager.getInstance().getOrCreateNavPathStack('Index');
  private databaseNavPathStack: NavPathStack = NavigationManager.getInstance().getOrCreateNavPathStack('DatabaseView');
  private totpNavPathStack: NavPathStack = NavigationManager.getInstance().getOrCreateNavPathStack('TotpView');
  private settingsNavPathStack: NavPathStack = NavigationManager.getInstance().getOrCreateNavPathStack('Settings');

  @State currentRootPage: string = 'Index';
  @StorageLink("navBarWidth") navBarWidth: number = NavigationConstants.DEFAULT_NAV_BAR_WIDTH; // 导航栏宽度
  @StorageLink('isLocked') isLocked: boolean = false; // 锁屏状态

  // 订阅响应式窗口信息：窗口尺寸变化时自动刷新、驱动分栏/单栏切换
  @State windowInfo: WindowInfo = WindowService.getInstance().info;

  private windowService: WindowService = WindowService.getInstance();

  private rootPageChangeListener = (rootPage: string): void => {
    this.currentRootPage = rootPage;
  };

  // 锁屏事件监听
  private lockEventListener = (eventData: emitter.EventData): void => {
    hilog.info(DOMAIN, TAG, 'Lock event received');
    this.isLocked = true;
  };

  // 解锁事件监听
  private unlockEventListener = (): void => {
    hilog.info(DOMAIN, TAG, 'Unlock event received');
    this.isLocked = false;
  };

  aboutToAppear() {
    hilog.info(DOMAIN, TAG, 'AppNavigation aboutToAppear');
    // 初始化窗口服务（断点 + 分栏判定的单一来源）
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.windowService.init(context, this.getUIContext());

    // 设置初始导航栈
    this.navManager.setCurrentNavPathStack('Index');

    this.navManager.addRootPageChangeListener(this.rootPageChangeListener);
    this.currentRootPage = this.navManager.getCurrentRootPage();

    // 注册锁屏/解锁事件监听
    EventBus.on('lock_screen', this.lockEventListener);
    EventBus.on('unlock_screen', this.unlockEventListener);
  }

  aboutToDisappear() {
    this.navManager.removeRootPageChangeListener(this.rootPageChangeListener);
    EventBus.off('lock_screen', this.lockEventListener);
    EventBus.off('unlock_screen', this.unlockEventListener);
  }

  /**
   * 根据当前根页面的配置与窗口断点，计算 Navigation 实际显示模式。
   * 分栏页：宽窗口（宽度达阈值）且非竖长窗口时进入分栏，否则单栏。
   * 独占页（首页相关）：始终单栏。
   */
  private resolveNavigationMode(): NavigationMode {
    if (this.navManager.getCurrentStackMode() !== NavigationModeType.SPLIT) {
      return NavigationMode.Stack;
    }
    return this.windowInfo.isSplitMode ? NavigationMode.Split : NavigationMode.Stack;
  }

  build() {
    // 根据当前根页面选择对应的导航栈
    Stack() {
      // Index 页面
      Navigation(this.indexNavPathStack) {
        Index()
      }
      .mode(NavigationMode.Stack)
      .hideTitleBar(true)
      .hideBackButton(true)
      .width('100%')
      .height('100%')
      .visibility(this.currentRootPage === 'Index' ? Visibility.Visible : Visibility.None)

      // DatabaseView 页面
      Navigation(this.databaseNavPathStack) {
        DatabaseView({ navPathStack: this.databaseNavPathStack, databaseShowParam: undefined })
      }
      .mode(this.resolveNavigationMode())
      .navBarWidth(this.navBarWidth)
      .navBarWidthRange(NavigationConstants.NAV_BAR_WIDTH_RANGE)
      .minContentWidth(NavigationConstants.MIN_CONTENT_WIDTH)
      .enableDragBar(true)
      .hideTitleBar(true)
      .hideBackButton(true)
      .width('100%')
      .height('100%')
      .visibility(this.currentRootPage === 'DatabaseView' ? Visibility.Visible : Visibility.None)

      // TotpView 页面
      Navigation(this.totpNavPathStack) {
        TotpView()
      }
      .mode(this.resolveNavigationMode())
      .navBarWidth(this.navBarWidth)
      .navBarWidthRange(NavigationConstants.NAV_BAR_WIDTH_RANGE)
      .minContentWidth(NavigationConstants.MIN_CONTENT_WIDTH)
      .enableDragBar(true)
      .hideTitleBar(true)
      .hideBackButton(true)
      .width('100%')
      .height('100%')
      .visibility(this.currentRootPage === 'TotpView' ? Visibility.Visible : Visibility.None)

      // Settings 页面
      Navigation(this.settingsNavPathStack) {
        Settings()
      }
      .mode(this.resolveNavigationMode())
      .navBarWidth(this.navBarWidth)
      .navBarWidthRange(NavigationConstants.NAV_BAR_WIDTH_RANGE)
      .minContentWidth(NavigationConstants.MIN_CONTENT_WIDTH)
      .enableDragBar(true)
      .hideTitleBar(true)
      .hideBackButton(true)
      .width('100%')
      .height('100%')
      .visibility(this.currentRootPage === 'Settings' ? Visibility.Visible : Visibility.None)

      // 锁屏遮罩层
      if (this.isLocked) {
        UnLockDatabase()
          .width('100%')
          .height('100%')
          .zIndex(999)
      }
    }
    .width('100%')
    .height('100%')
  }
}
