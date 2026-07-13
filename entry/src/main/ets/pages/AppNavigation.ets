import { NavigationManager } from '../common/utils/NavigationManager';
import { PageConfigManager } from '../common/utils/PageConfigManager';
import { NavigationModeType } from '../common/constants/PageConfig';
import { NavigationConstants } from '../common/constants/NavigationConstants';
import { PageConstants } from '../common/constants/PageConstants';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'AppNavigation';

/**
 * 应用根导航组件
 *
 * 职责：
 * 1. 作为应用的根容器
 * 2. 管理全局的 NavPathStack
 * 3. 根据当前根页面动态切换导航模式
 *
 * 注意：路由注册通过 @Builder 函数自动完成，在页面文件中定义并导出
 */
@Entry
@Component
struct AppNavigation {
  private navPathStack: NavPathStack = new NavPathStack();
  private navManager: NavigationManager = NavigationManager.getInstance();

  @State currentMode: NavigationMode = NavigationMode.Stack;

  aboutToAppear() {
    hilog.info(DOMAIN, TAG, 'AppNavigation aboutToAppear');

    // 设置导航栈到管理器
    this.navManager.setNavPathStack(this.navPathStack);

    // 导航到首页
    this.navManager.navigateTo(PageConstants.PAGE_INDEX);
  }

  build() {
    Navigation(this.navPathStack) {
      // 默认内容（不会被显示，因为路由会替换）
      Column() {
        Text('Loading...')
      }
    }
    .mode(this.currentMode)
    .navBarWidthRange(NavigationConstants.NAV_BAR_WIDTH_RANGE)
    .minContentWidth(NavigationConstants.MIN_CONTENT_WIDTH)
    .enableDragBar(true)
    .width('100%')
    .height('100%')
    .onAppear(() => {
      this.updateNavigationMode();
    })
  }

  /**
   * 更新导航模式
   * 根据当前根页面的配置动态切换
   */
  private updateNavigationMode(): void {
    const config = this.navManager.getCurrentPageConfig();
    const newMode = config.navigationMode === NavigationModeType.SPLIT
      ? NavigationMode.Auto
      : NavigationMode.Stack;

    if (this.currentMode !== newMode) {
      this.currentMode = newMode;
      hilog.info(DOMAIN, TAG, 'Navigation mode changed to: %{public}s',
        newMode === NavigationMode.Auto ? 'Auto(Split)' : 'Stack');
    }
  }
}
