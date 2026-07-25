import { NavigationManager } from '../common/utils/NavigationManager';
import { NavigationModeType } from '../common/constants/PageConfig';
import { NavigationConstants } from '../common/constants/NavigationConstants';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
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

  @State currentMode: NavigationMode = NavigationMode.Stack;
  @State currentRootPage: string = 'Index';
  @StorageLink("navBarWidth") navBarWidth: number = NavigationConstants.DEFAULT_NAV_BAR_WIDTH; // 导航栏宽度
  @StorageLink('isLocked') isLocked: boolean = false; // 锁屏状态

  private modeChangeListener = (mode: NavigationModeType): void => {
    this.currentMode = mode === NavigationModeType.SPLIT
      ? NavigationMode.Auto
      : NavigationMode.Stack;
  };

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
    // 设置初始导航栈
    this.navManager.setCurrentNavPathStack('Index');

    this.navManager.addModeChangeListener(this.modeChangeListener);
    this.navManager.addRootPageChangeListener(this.rootPageChangeListener);
    this.modeChangeListener(this.navManager.getCurrentStackMode());
    this.currentRootPage = this.navManager.getCurrentRootPage();

    // 注册锁屏/解锁事件监听
    EventBus.on('lock_screen', this.lockEventListener);
    EventBus.on('unlock_screen', this.unlockEventListener);
  }

  aboutToDisappear() {
    this.navManager.removeModeChangeListener(this.modeChangeListener);
    this.navManager.removeRootPageChangeListener(this.rootPageChangeListener);
    EventBus.off('lock_screen', this.lockEventListener);
    EventBus.off('unlock_screen', this.unlockEventListener);
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
      .mode(this.currentMode)
      .navBarWidth(NavigationConstants.DEFAULT_NAV_BAR_WIDTH)
      .navBarWidthRange(NavigationConstants.NAV_BAR_WIDTH_RANGE)
      .minContentWidth(NavigationConstants.MIN_CONTENT_WIDTH)
      .enableDragBar(false)
      .hideTitleBar(true)
      .hideBackButton(true)
      .width('100%')
      .height('100%')
      .visibility(this.currentRootPage === 'DatabaseView' ? Visibility.Visible : Visibility.None)

      // TotpView 页面
      Navigation(this.totpNavPathStack) {
        TotpView()
      }
      .mode(this.currentMode)
      .navBarWidth(NavigationConstants.DEFAULT_NAV_BAR_WIDTH)
      .navBarWidthRange(NavigationConstants.NAV_BAR_WIDTH_RANGE)
      .minContentWidth(NavigationConstants.MIN_CONTENT_WIDTH)
      .enableDragBar(false)
      .hideTitleBar(true)
      .hideBackButton(true)
      .width('100%')
      .height('100%')
      .visibility(this.currentRootPage === 'TotpView' ? Visibility.Visible : Visibility.None)

      // Settings 页面
      Navigation(this.settingsNavPathStack) {
        Settings()
      }
      .mode(this.currentMode)
      .navBarWidth(NavigationConstants.DEFAULT_NAV_BAR_WIDTH)
      .navBarWidthRange(NavigationConstants.NAV_BAR_WIDTH_RANGE)
      .minContentWidth(NavigationConstants.MIN_CONTENT_WIDTH)
      .enableDragBar(false)
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
