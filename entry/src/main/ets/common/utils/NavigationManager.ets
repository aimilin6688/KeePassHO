import { NavPathStack, NavigationMode } from '@kit.ArkUI';
import { PageConfigManager } from './PageConfigManager';
import { PageConfig, NavigationModeType } from '../constants/PageConfig';
import { NavigationConstants } from '../constants/NavigationConstants';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'NavigationManager';

/**
 * 导航管理器
 *
 * 职责：
 * 1. 管理导航栈
 * 2. 处理页面跳转
 * 3. 管理导航栈配置继承
 */
export class NavigationManager {
  private static instance: NavigationManager;
  private navPathStack: NavPathStack | null = null;
  private configManager: PageConfigManager = PageConfigManager.getInstance();

  /**
   * 当前导航栈的根页面
   */
  private currentRootPage: string = 'Index';

  /**
   * 导航历史
   */
  private navigationHistory: string[] = [];

  private constructor() {}

  static getInstance(): NavigationManager {
    if (!NavigationManager.instance) {
      NavigationManager.instance = new NavigationManager();
    }
    return NavigationManager.instance;
  }

  /**
   * 设置导航栈
   */
  setNavPathStack(stack: NavPathStack): void {
    this.navPathStack = stack;
  }

  /**
   * 导航到页面
   *
   * 关键逻辑：
   * 1. 判断是否是根页面
   * 2. 如果是根页面，设置导航栈配置
   * 3. 子页面自动继承导航栈配置
   */
  navigateTo(pageName: string, params?: Object): void {
    if (!this.navPathStack) {
      hilog.error(DOMAIN, TAG, 'NavPathStack not initialized');
      return;
    }

    const isRoot = this.configManager.isRootPage(pageName);

    if (isRoot) {
      // 设置新的导航栈根页面
      this.currentRootPage = pageName;

      // 获取根页面的配置
      const rootConfig = this.configManager.getPageConfig(pageName);
      if (rootConfig) {
        // 缓存导航栈配置
        this.configManager.setNavigationStackConfig(pageName, rootConfig);
      }

      // 重置导航历史
      this.navigationHistory = [pageName];
    } else {
      // 子页面：添加到导航历史
      this.navigationHistory.push(pageName);
    }

    // 执行导航
    this.navPathStack.pushPath({ name: pageName, param: params });
  }

  /**
   * 获取当前页面的有效配置（处理继承）
   */
  getCurrentPageConfig(pageName?: string): PageConfig {
    const currentPage = pageName || this.navigationHistory[this.navigationHistory.length - 1];
    return this.configManager.getEffectivePageConfig(currentPage, this.currentRootPage);
  }

  /**
   * 获取当前导航栈根页面
   */
  getCurrentRootPage(): string {
    return this.currentRootPage;
  }

  /**
   * 返回上一页
   */
  pop(): void {
    if (this.navPathStack && this.navPathStack.size() > 0) {
      this.navPathStack.pop();
      this.navigationHistory.pop();

      // 更新当前根页面
      if (this.navigationHistory.length > 0) {
        const lastPage = this.navigationHistory[this.navigationHistory.length - 1];
        if (this.configManager.isRootPage(lastPage)) {
          this.currentRootPage = lastPage;
        }
      }
    }
  }

  /**
   * 获取导航历史
   */
  getNavigationHistory(): string[] {
    return [...this.navigationHistory];
  }

  /**
   * 获取当前导航栈模式
   */
  getCurrentStackMode(): NavigationModeType {
    return this.getCurrentPageConfig().navigationMode;
  }

  /**
   * 转换为 NavigationMode
   */
  toNavigationMode(modeType: NavigationModeType): NavigationMode {
    return modeType === NavigationModeType.SPLIT
      ? NavigationMode.Auto
      : NavigationMode.Stack;
  }
}
