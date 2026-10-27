import { PageConfigManager } from './PageConfigManager';
import { PageConfig, NavigationModeType } from '../constants/PageConfig';
import { NavigationConstants } from '../constants/NavigationConstants';
import { PageConstants } from '../constants/PageConstants';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'NavigationManager';

type NavigationModeChangeListener = (mode: NavigationModeType) => void;
type RootPageChangeListener = (rootPage: string) => void;
type SystemBackHandler = () => boolean;

export class NavigationManager {
  private static instance: NavigationManager;
  private configManager: PageConfigManager = PageConfigManager.getInstance();

  private currentRootPage: string = 'Index';
  private previousRootPage: string = 'Index';
  private modeChangeListeners: NavigationModeChangeListener[] = [];
  private rootPageChangeListeners: RootPageChangeListener[] = [];

  /**
   * 系统返回键的上下文处理器。
   *
   * 当 Navigation 的路由栈为空（系统返回无法被 Navigation 消费）时，
   * UIAbility.onBackPressed 会回调到这里，由当前可见页面决定是否消费返回事件。
   * 例如 DatabaseView 处于子分组（栈内无路由页）时，用该处理器向上返回一层分组。
   */
  private systemBackHandler: SystemBackHandler | null = null;

  /**
   * 每个根页面独立的导航栈
   */
  private navPathStacks: Map<string, NavPathStack> = new Map();
  private currentNavPathStack: NavPathStack | null = null;

  private constructor() {}

  static getInstance(): NavigationManager {
    if (!NavigationManager.instance) {
      NavigationManager.instance = new NavigationManager();
    }
    return NavigationManager.instance;
  }

  /**
   * 获取或创建指定根页面的导航栈
   */
  getOrCreateNavPathStack(rootPage: string): NavPathStack {
    let stack = this.navPathStacks.get(rootPage);
    if (!stack) {
      stack = new NavPathStack();
      this.navPathStacks.set(rootPage, stack);
      hilog.info(DOMAIN, TAG, 'Created new NavPathStack for: %{public}s', rootPage);
    }
    return stack;
  }

  /**
   * 设置当前导航栈
   */
  setCurrentNavPathStack(rootPage: string): void {
    this.currentNavPathStack = this.getOrCreateNavPathStack(rootPage);
    hilog.info(DOMAIN, TAG, 'Set current NavPathStack for: %{public}s', rootPage);
  }

  /**
   * 获取当前导航栈
   */
  getNavPathStack(): NavPathStack | null {
    return this.currentNavPathStack;
  }

  /**
   * 获取指定根页面的导航栈
   */
  getNavPathStackByRoot(rootPage: string): NavPathStack | null {
    return this.navPathStacks.get(rootPage) || null;
  }

  addModeChangeListener(listener: NavigationModeChangeListener): void {
    this.modeChangeListeners.push(listener);
  }

  removeModeChangeListener(listener: NavigationModeChangeListener): void {
    const index = this.modeChangeListeners.indexOf(listener);
    if (index >= 0) {
      this.modeChangeListeners.splice(index, 1);
    }
  }

  addRootPageChangeListener(listener: RootPageChangeListener): void {
    this.rootPageChangeListeners.push(listener);
  }

  removeRootPageChangeListener(listener: RootPageChangeListener): void {
    const index = this.rootPageChangeListeners.indexOf(listener);
    if (index >= 0) {
      this.rootPageChangeListeners.splice(index, 1);
    }
  }

  /**
   * 注册/注销系统返回键的上下文处理器。
   * 由当前可见根页面（如 DatabaseView）在 aboutToAppear/aboutToDisappear 中维护。
   */
  setSystemBackHandler(handler: SystemBackHandler | null): void {
    this.systemBackHandler = handler;
  }

  /**
   * 处理系统返回键（UIAbility.onBackPressed 调用）。
   * @returns true 表示已消费返回事件（应用不退出）；false 表示未消费（走默认退出逻辑）。
   *
   * 处理顺序：
   * 1. 优先交给当前页面注册的上下文处理器消费（如 DatabaseView 子分组原位返回上一层）。
   * 2. 若未消费，且当前处于「次级根页面」（Settings/TotpView 等从主入口进入的根页面），
   *    则回到上一个根页面，避免系统返回直接退出应用。Index（首页）与 DatabaseView（主界面）
   *    不在此列：前者是应用入口，后者由其 systemBackHandler 自行处理、根分组时保持退出行为。
   */
  handleSystemBack(): boolean {
    if (this.systemBackHandler) {
      if (this.systemBackHandler()) {
        return true;
      }
    }
    if (this.currentRootPage !== PageConstants.PAGE_INDEX
      && this.currentRootPage !== PageConstants.PAGE_DATABASE_VIEW
      && this.previousRootPage !== this.currentRootPage) {
      this.navigateBackToPreviousRoot();
      return true;
    }
    return false;
  }

  private notifyModeChange(mode: NavigationModeType): void {
    for (const listener of this.modeChangeListeners) {
      listener(mode);
    }
  }

  private notifyRootPageChange(rootPage: string): void {
    for (const listener of this.rootPageChangeListeners) {
      listener(rootPage);
    }
  }

  getCurrentRootPage(): string {
    return this.currentRootPage;
  }

  getPreviousRootPage(): string {
    return this.previousRootPage;
  }

  /**
   * 导航到指定的根页面
   * 切换根页面时保持各自的导航栈状态
   */
  navigateBackToRoot(rootPage: string): void {
    const prevMode = this.getCurrentStackMode();
    const prevRoot = this.currentRootPage;

    this.previousRootPage = prevRoot;
    this.currentRootPage = rootPage;

    // 切换到目标根页面的导航栈
    this.setCurrentNavPathStack(rootPage);

    const rootConfig = this.configManager.getPageConfig(rootPage);
    if (rootConfig) {
      this.configManager.setNavigationStackConfig(rootPage, rootConfig);
    }

    const newMode = this.getCurrentStackMode();
    if (prevMode !== newMode) {
      this.notifyModeChange(newMode);
    }
    if (prevRoot !== rootPage) {
      this.notifyRootPageChange(rootPage);
    }

    hilog.info(DOMAIN, TAG, 'navigateBackToRoot: %{public}s', rootPage);
  }

  /**
   * 返回到上一个根页面
   */
  navigateBackToPreviousRoot(): void {
    hilog.info(DOMAIN, TAG, 'navigateBackToPreviousRoot: from %{public}s to %{public}s',
      this.currentRootPage, this.previousRootPage);
    this.navigateBackToRoot(this.previousRootPage);
  }

  getCurrentPageConfig(pageName?: string): PageConfig {
    const config = this.configManager.getPageConfig(this.currentRootPage);
    return config || {
      name: this.currentRootPage,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: 700,
      padding: 16
    };
  }

  getCurrentStackMode(): NavigationModeType {
    return this.getCurrentPageConfig().navigationMode;
  }

  getStackSize(): number {
    return this.currentNavPathStack ? this.currentNavPathStack.size() : 0;
  }

  /**
   * 导航到页面
   */
  navigateTo(pageName: string, params?: Object): void {
    if (!this.currentNavPathStack) {
      hilog.error(DOMAIN, TAG, 'NavPathStack not initialized');
      return;
    }
    this.currentNavPathStack.pushPathByName(pageName, params);
    hilog.info(DOMAIN, TAG, 'Navigated to: %{public}s', pageName);
  }

  /**
   * 返回上一页
   */
  pop(): void {
    if (this.currentNavPathStack && this.currentNavPathStack.size() > 0) {
      this.currentNavPathStack.pop();
      hilog.info(DOMAIN, TAG, 'Popped from stack');
    }
  }

  /**
   * 替换所有页面
   */
  replaceAll(pageName: string, params?: Object): void {
    if (!this.currentNavPathStack) {
      hilog.error(DOMAIN, TAG, 'NavPathStack not initialized');
      return;
    }
    this.currentNavPathStack.clear();
    this.currentNavPathStack.pushPathByName(pageName, params);
    hilog.info(DOMAIN, TAG, 'Replaced all with: %{public}s', pageName);
  }

  /**
   * 清除指定根页面的导航栈
   */
  clearNavPathStack(rootPage: string): void {
    const stack = this.navPathStacks.get(rootPage);
    if (stack) {
      stack.clear();
      hilog.info(DOMAIN, TAG, 'Cleared NavPathStack for: %{public}s', rootPage);
    }
  }

  /**
   * 删除指定根页面的导航栈
   */
  removeNavPathStack(rootPage: string): void {
    this.navPathStacks.delete(rootPage);
    hilog.info(DOMAIN, TAG, 'Removed NavPathStack for: %{public}s', rootPage);
  }

  /**
   * 清除当前导航栈引用（不删除栈注册表条目；测试套件收尾清理用，
   * 防止单例 currentNavPathStack 泄漏到后续套件）
   */
  clearCurrentNavPathStack(): void {
    this.currentNavPathStack = null;
  }
}
