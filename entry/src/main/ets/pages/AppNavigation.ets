import { NavigationManager } from '../common/utils/NavigationManager';
import { NavigationModeType } from '../common/constants/PageConfig';
import { NavigationConstants } from '../common/constants/NavigationConstants';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Index } from './Index';
import { Settings } from './setting/Settings';
import { DatabaseView } from './DatabaseView';

const DOMAIN = 0x0000;
const TAG = 'AppNavigation';

@Entry
@Component
struct AppNavigation {
  private navManager: NavigationManager = NavigationManager.getInstance();

  // 使用 NavigationManager 中的导航栈
  private indexNavPathStack: NavPathStack = NavigationManager.getInstance().getOrCreateNavPathStack('Index');
  private databaseNavPathStack: NavPathStack = NavigationManager.getInstance().getOrCreateNavPathStack('DatabaseView');
  private settingsNavPathStack: NavPathStack = NavigationManager.getInstance().getOrCreateNavPathStack('Settings');

  @State currentMode: NavigationMode = NavigationMode.Stack;
  @State currentRootPage: string = 'Index';
  @StorageLink("navBarWidth") navBarWidth: number = NavigationConstants.DEFAULT_NAV_BAR_WIDTH; // 导航栏宽度

  private modeChangeListener = (mode: NavigationModeType): void => {
    this.currentMode = mode === NavigationModeType.SPLIT
      ? NavigationMode.Auto
      : NavigationMode.Stack;
  };

  private rootPageChangeListener = (rootPage: string): void => {
    this.currentRootPage = rootPage;
  };

  aboutToAppear() {
    hilog.info(DOMAIN, TAG, 'AppNavigation aboutToAppear');
    // 设置初始导航栈
    this.navManager.setCurrentNavPathStack('Index');

    this.navManager.addModeChangeListener(this.modeChangeListener);
    this.navManager.addRootPageChangeListener(this.rootPageChangeListener);
    this.modeChangeListener(this.navManager.getCurrentStackMode());
    this.currentRootPage = this.navManager.getCurrentRootPage();
  }

  aboutToDisappear() {
    this.navManager.removeModeChangeListener(this.modeChangeListener);
    this.navManager.removeRootPageChangeListener(this.rootPageChangeListener);
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
    }
    .width('100%')
    .height('100%')
  }
}
