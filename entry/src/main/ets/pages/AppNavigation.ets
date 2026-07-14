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
  private navPathStack: NavPathStack = new NavPathStack();
  private navManager: NavigationManager = NavigationManager.getInstance();

  @State currentMode: NavigationMode = NavigationMode.Stack;
  @State currentRootPage: string = 'Index';

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
    this.navManager.setNavPathStack(this.navPathStack);
    this.navManager.addModeChangeListener(this.modeChangeListener);
    this.navManager.addRootPageChangeListener(this.rootPageChangeListener);
    this.modeChangeListener(this.navManager.getCurrentStackMode());
    this.currentRootPage = this.navManager.getCurrentRootPage();
  }

  aboutToDisappear() {
    this.navManager.removeModeChangeListener(this.modeChangeListener);
    this.navManager.removeRootPageChangeListener(this.rootPageChangeListener);
  }

  @Builder
  NavBarContent() {
    if (this.currentRootPage === 'Settings') {
      Settings({ navPathStack: this.navPathStack })
    } else if (this.currentRootPage === 'DatabaseView') {
      DatabaseView({ navPathStack: this.navPathStack, databaseShowParam: undefined })
    } else {
      Index()
    }
  }

  build() {
    Navigation(this.navPathStack) {
      this.NavBarContent()
    }
    .mode(this.currentMode)
    .navBarWidthRange(NavigationConstants.NAV_BAR_WIDTH_RANGE)
    .minContentWidth(NavigationConstants.MIN_CONTENT_WIDTH)
    .enableDragBar(false)
    .hideTitleBar(true)
    .hideBackButton(true)
    .width('100%')
    .height('100%')
  }
}
