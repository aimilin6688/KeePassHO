import { PageConfigManager } from './PageConfigManager';
import { PageConfig, NavigationModeType } from '../constants/PageConfig';
import { NavigationConstants } from '../constants/NavigationConstants';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'NavigationManager';

type NavigationModeChangeListener = (mode: NavigationModeType) => void;
type RootPageChangeListener = (rootPage: string) => void;

export class NavigationManager {
  private static instance: NavigationManager;
  private navPathStack: NavPathStack | null = null;
  private configManager: PageConfigManager = PageConfigManager.getInstance();

  private currentRootPage: string = 'Index';
  private previousRootPage: string = 'Index';
  private navigationHistory: string[] = [];
  private modeChangeListeners: NavigationModeChangeListener[] = [];
  private rootPageChangeListeners: RootPageChangeListener[] = [];

  private constructor() {}

  static getInstance(): NavigationManager {
    if (!NavigationManager.instance) {
      NavigationManager.instance = new NavigationManager();
    }
    return NavigationManager.instance;
  }

  setNavPathStack(stack: NavPathStack): void {
    this.navPathStack = stack;
  }

  getNavPathStack(): NavPathStack | null {
    return this.navPathStack;
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

  navigateTo(pageName: string, params?: Object): void {
    if (!this.navPathStack) {
      hilog.error(DOMAIN, TAG, 'NavPathStack not initialized');
      return;
    }

    const isRoot = this.configManager.isRootPage(pageName);

    if (isRoot) {
      const prevMode = this.getCurrentStackMode();
      const prevRoot = this.currentRootPage;
      this.previousRootPage = prevRoot;
      this.currentRootPage = pageName;

      const rootConfig = this.configManager.getPageConfig(pageName);
      if (rootConfig) {
        this.configManager.setNavigationStackConfig(pageName, rootConfig);
      }

      this.navPathStack.clear();
      this.navigationHistory = [pageName];

      const newMode = this.getCurrentStackMode();
      if (prevMode !== newMode) {
        this.notifyModeChange(newMode);
      }
      if (prevRoot !== pageName) {
        this.notifyRootPageChange(pageName);
      }
    } else {
      this.navigationHistory.push(pageName);
      this.navPathStack.pushPathByName(pageName, params);
    }

    hilog.info(DOMAIN, TAG, 'Navigated to: %{public}s, isRoot: %{public}s', pageName, isRoot.toString());
  }

  getCurrentPageConfig(pageName?: string): PageConfig {
    const currentPage = pageName || this.navigationHistory[this.navigationHistory.length - 1];
    return this.configManager.getEffectivePageConfig(currentPage, this.currentRootPage);
  }

  getCurrentRootPage(): string {
    return this.currentRootPage;
  }

  pop(): void {
    if (this.navPathStack && this.navPathStack.size() > 0) {
      this.navPathStack.pop();
      this.navigationHistory.pop();

      if (this.navigationHistory.length > 0) {
        const lastPage = this.navigationHistory[this.navigationHistory.length - 1];
        if (this.configManager.isRootPage(lastPage)) {
          this.currentRootPage = lastPage;
        }
      }

      hilog.info(DOMAIN, TAG, 'Popped, current root: %{public}s', this.currentRootPage);
    }
  }

  popToRoot(): void {
    if (this.navPathStack && this.navPathStack.size() > 0) {
      const rootPage = this.navigationHistory[0];
      this.navigationHistory = [rootPage];
      this.currentRootPage = rootPage;

      while (this.navPathStack.size() > 0) {
        this.navPathStack.pop();
      }

      hilog.info(DOMAIN, TAG, 'Popped to root: %{public}s', rootPage);
    }
  }

  navigateBackToRoot(rootPage: string): void {
    const prevMode = this.getCurrentStackMode();
    const prevRoot = this.currentRootPage;

    this.currentRootPage = rootPage;
    this.navigationHistory = [rootPage];

    const rootConfig = this.configManager.getPageConfig(rootPage);
    if (rootConfig) {
      this.configManager.setNavigationStackConfig(rootPage, rootConfig);
    }

    if (this.navPathStack) {
      this.navPathStack.clear();
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

  navigateBackToPreviousRoot(): void {
    this.navigateBackToRoot(this.previousRootPage);
  }

  replaceAll(pageName: string, params?: Object): void {
    if (!this.navPathStack) {
      hilog.error(DOMAIN, TAG, 'NavPathStack not initialized');
      return;
    }

    this.navPathStack.clear();
    this.navigationHistory = [];

    this.navigateTo(pageName, params);
  }

  getNavigationHistory(): string[] {
    return [...this.navigationHistory];
  }

  getCurrentStackMode(): NavigationModeType {
    return this.getCurrentPageConfig().navigationMode;
  }

  toNavigationMode(modeType: NavigationModeType): NavigationMode {
    return modeType === NavigationModeType.SPLIT
      ? NavigationMode.Auto
      : NavigationMode.Stack;
  }

  getStackSize(): number {
    return this.navPathStack ? this.navPathStack.size() : 0;
  }
}
