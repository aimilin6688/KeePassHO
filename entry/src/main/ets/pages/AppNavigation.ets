import { NavigationManager } from '../common/utils/NavigationManager';
import { NavigationModeType } from '../common/constants/PageConfig';
import { NavigationConstants } from '../common/constants/NavigationConstants';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Index } from './Index';

const DOMAIN = 0x0000;
const TAG = 'AppNavigation';

/**
 * 应用根导航组件
 */
@Entry
@Component
struct AppNavigation {
  private navPathStack: NavPathStack = new NavPathStack();
  private navManager: NavigationManager = NavigationManager.getInstance();

  @State currentMode: NavigationMode = NavigationMode.Stack;

  aboutToAppear() {
    hilog.info(DOMAIN, TAG, 'AppNavigation aboutToAppear');
    this.navManager.setNavPathStack(this.navPathStack);
    this.updateNavigationMode();
  }

  build() {
    Navigation(this.navPathStack) {
      Index()
    }
    .mode(this.currentMode)
    .navBarWidthRange(NavigationConstants.NAV_BAR_WIDTH_RANGE)
    .minContentWidth(NavigationConstants.MIN_CONTENT_WIDTH)
    .enableDragBar(false)
    .width('100%')
    .height('100%')
  }

  private updateNavigationMode(): void {
    const config = this.navManager.getCurrentPageConfig();
    this.currentMode = config.navigationMode === NavigationModeType.SPLIT
      ? NavigationMode.Auto
      : NavigationMode.Stack;
  }
}
