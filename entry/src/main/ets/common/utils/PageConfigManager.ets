import { PageConfig, NavigationModeType } from '../constants/PageConfig';
import { PageConstants } from '../constants/PageConstants';
import { NavigationConstants } from '../constants/NavigationConstants';
import { FileStorage, PageConfig as StoragePageConfig } from '../../storage';

/**
 * 页面配置项接口（用于首页相关页面）
 */
interface HomePageConfig {
  name: string;
  maxWidth: number;
  padding: number;
}

/**
 * 数据库页面配置项接口
 */
interface DatabasePageConfig {
  name: string;
  padding: number;
}

/**
 * 页面配置管理器
 *
 * 职责：
 * 1. 管理所有页面的配置
 * 2. 提供配置继承机制
 * 3. 缓存导航栈的配置
 */
export class PageConfigManager {
  private static instance: PageConfigManager;

  /**
   * 页面配置映射表
   */
  private pageConfigs: Map<string, PageConfig> = new Map();

  /**
   * 导航栈配置缓存
   * key: 导航栈根页面名称
   * value: 页面配置
   */
  private navigationStackConfig: Map<string, PageConfig> = new Map();

  private constructor() {
    this.initializePageConfigs();
  }

  /**
   * 初始化页面配置
   */
  private initializePageConfigs(): void {
    // ==================== 首页相关页面（独占模式 + 限制最大宽度）====================
    const homePages: HomePageConfig[] = [
      { name: PageConstants.PAGE_INDEX, maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH, padding: PageConstants.HOME_PAGE_PADDING },
      { name: PageConstants.PAGE_PASSWORD, maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH, padding: PageConstants.HOME_PAGE_PADDING },
      { name: PageConstants.PAGE_RECENT_FILES, maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH, padding: PageConstants.HOME_PAGE_PADDING },
      { name: PageConstants.PAGE_SELECT_LOCATION, maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH, padding: PageConstants.HOME_PAGE_PADDING },
      { name: PageConstants.PAGE_CREATE_DATABASE, maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH, padding: PageConstants.HOME_PAGE_PADDING },
      { name: PageConstants.PAGE_UNLOCK_DATABASE, maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH, padding: PageConstants.HOME_PAGE_PADDING },
      { name: PageConstants.PAGE_CHANGE_PASSWORD, maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH, padding: PageConstants.HOME_PAGE_PADDING },
      { name: PageConstants.PAGE_OAUTH2_LOGIN, maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH, padding: PageConstants.HOME_PAGE_PADDING },
    ];

    // ==================== 存储相关页面（独占模式 + 限制最大宽度）====================
    // 从 FileStorageFactory 注册的存储 PageConfig 中获取（本地 + 各云存储），
    // 页面名称取 pageUrl 最后一段（与 StorageNavigation.getConfigPageName 规则一致），
    // 新增存储类型只需在 FileStorageFactory 注册，此处自动生效
    FileStorage.getAllPageConfig().forEach((storagePageConfig: StoragePageConfig) => {
      const pageName: string = storagePageConfig.pageUrl.split('/').pop() || storagePageConfig.pageUrl;
      homePages.push({
        name: pageName,
        maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
        padding: PageConstants.HOME_PAGE_PADDING
      });
    });

    homePages.forEach((page: HomePageConfig) => {
      const config: PageConfig = {
        name: page.name,
        navigationMode: NavigationModeType.EXCLUSIVE,
        constrainMaxWidth: true,
        maxWidth: page.maxWidth,
        padding: page.padding
      };
      this.pageConfigs.set(page.name, config);
    });

    // ==================== 数据库相关页面（分栏模式 + 不限制宽度）====================
    const databasePages: DatabasePageConfig[] = [
      { name: PageConstants.PAGE_DATABASE_VIEW, padding: 0 },
      { name: PageConstants.PAGE_ENTRY_VIEW, padding: PageConstants.ENTRY_PAGE_PADDING },
      { name: PageConstants.PAGE_ENTRY_EDIT, padding: PageConstants.ENTRY_PAGE_PADDING },
      { name: PageConstants.PAGE_TOTP_VIEW, padding: PageConstants.ENTRY_PAGE_PADDING },
      { name: PageConstants.PAGE_TEMPLATE_ENTRY_CREATE, padding: PageConstants.ENTRY_PAGE_PADDING },
      { name: PageConstants.PAGE_EXPIRY_REPORT, padding: PageConstants.ENTRY_PAGE_PADDING },
    ];

    databasePages.forEach((page: DatabasePageConfig) => {
      const config: PageConfig = {
        name: page.name,
        navigationMode: NavigationModeType.SPLIT,
        constrainMaxWidth: false,
        padding: page.padding
      };
      this.pageConfigs.set(page.name, config);
    });

    // ==================== 设置页面（分栏模式）====================
    const settingsConfig: PageConfig = {
      name: PageConstants.PAGE_SETTINGS,
      navigationMode: NavigationModeType.SPLIT,
      constrainMaxWidth: false,
      padding: PageConstants.SETTINGS_PAGE_PADDING
    };
    this.pageConfigs.set(PageConstants.PAGE_SETTINGS, settingsConfig);
  }

  static getInstance(): PageConfigManager {
    if (!PageConfigManager.instance) {
      PageConfigManager.instance = new PageConfigManager();
    }
    return PageConfigManager.instance;
  }

  /**
   * 获取页面配置
   */
  getPageConfig(pageName: string): PageConfig | undefined {
    return this.pageConfigs.get(pageName);
  }

  /**
   * 设置导航栈的根配置
   */
  setNavigationStackConfig(rootPage: string, config: PageConfig): void {
    this.navigationStackConfig.set(rootPage, config);
  }

  /**
   * 获取导航栈的根配置
   */
  getNavigationStackConfig(rootPage: string): PageConfig | undefined {
    return this.navigationStackConfig.get(rootPage);
  }

  /**
   * 获取页面的有效配置（处理继承）
   *
   * 继承规则：
   * 1. 如果页面有自己的配置，使用自己的配置
   * 2. 如果页面是子页面，且没有特定配置，继承导航栈根页面的配置
   */
  getEffectivePageConfig(pageName: string, rootPage: string): PageConfig {
    const pageConfig = this.pageConfigs.get(pageName);
    const rootConfig = this.navigationStackConfig.get(rootPage);

    if (pageConfig && rootConfig) {
      // 合并配置：页面自己的配置优先，缺失的配置继承根配置
      const mergedConfig: PageConfig = {
        name: pageName,
        navigationMode: pageConfig.navigationMode,
        constrainMaxWidth: pageConfig.constrainMaxWidth ?? rootConfig.constrainMaxWidth,
        maxWidth: pageConfig.maxWidth ?? rootConfig.maxWidth,
        padding: pageConfig.padding ?? rootConfig.padding ?? PageConstants.HOME_PAGE_PADDING
      };
      return mergedConfig;
    }

    // 返回页面自己的配置或默认配置
    if (pageConfig) {
      return pageConfig;
    }

    // 默认配置
    const defaultConfig: PageConfig = {
      name: pageName,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    };
    return defaultConfig;
  }

  /**
   * 判断是否是根页面
   */
  isRootPage(pageName: string): boolean {
    return NavigationConstants.isRootPage(pageName);
  }
}
