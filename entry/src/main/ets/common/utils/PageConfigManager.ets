import { PageConfig, NavigationModeType } from '../constants/PageConfig';
import { PageConstants } from '../constants/PageConstants';
import { NavigationConstants } from '../constants/NavigationConstants';

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

  private initializePageConfigs(): void {
    // ==================== 首页相关页面（独占模式 + 限制最大宽度）====================
    const homePageConfig: PageConfig = {
      name: PageConstants.PAGE_INDEX,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    };
    this.pageConfigs.set(PageConstants.PAGE_INDEX, homePageConfig);

    this.pageConfigs.set(PageConstants.PAGE_PASSWORD, {
      name: PageConstants.PAGE_PASSWORD,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_RECENT_FILES, {
      name: PageConstants.PAGE_RECENT_FILES,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_SELECT_LOCATION, {
      name: PageConstants.PAGE_SELECT_LOCATION,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_CREATE_DATABASE, {
      name: PageConstants.PAGE_CREATE_DATABASE,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_UNLOCK_DATABASE, {
      name: PageConstants.PAGE_UNLOCK_DATABASE,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_CHANGE_PASSWORD, {
      name: PageConstants.PAGE_CHANGE_PASSWORD,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_OAUTH2_LOGIN, {
      name: PageConstants.PAGE_OAUTH2_LOGIN,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_LOCAL_FILE, {
      name: PageConstants.PAGE_LOCAL_FILE,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_WEBDAV, {
      name: PageConstants.PAGE_WEBDAV,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_ONEDRIVE, {
      name: PageConstants.PAGE_ONEDRIVE,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_FTP, {
      name: PageConstants.PAGE_FTP,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_S3, {
      name: PageConstants.PAGE_S3,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_PCLOUD, {
      name: PageConstants.PAGE_PCLOUD,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    });

    // ==================== 数据库相关页面（分栏模式 + 不限制宽度）====================
    this.pageConfigs.set(PageConstants.PAGE_DATABASE_VIEW, {
      name: PageConstants.PAGE_DATABASE_VIEW,
      navigationMode: NavigationModeType.SPLIT,
      constrainMaxWidth: false,
      padding: 0
    });

    this.pageConfigs.set(PageConstants.PAGE_ENTRY_VIEW, {
      name: PageConstants.PAGE_ENTRY_VIEW,
      navigationMode: NavigationModeType.SPLIT,
      constrainMaxWidth: false,
      padding: PageConstants.ENTRY_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_ENTRY_EDIT, {
      name: PageConstants.PAGE_ENTRY_EDIT,
      navigationMode: NavigationModeType.SPLIT,
      constrainMaxWidth: false,
      padding: PageConstants.ENTRY_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_TOTP_VIEW, {
      name: PageConstants.PAGE_TOTP_VIEW,
      navigationMode: NavigationModeType.SPLIT,
      constrainMaxWidth: false,
      padding: PageConstants.ENTRY_PAGE_PADDING
    });

    this.pageConfigs.set(PageConstants.PAGE_TEMPLATE_ENTRY_CREATE, {
      name: PageConstants.PAGE_TEMPLATE_ENTRY_CREATE,
      navigationMode: NavigationModeType.SPLIT,
      constrainMaxWidth: false,
      padding: PageConstants.ENTRY_PAGE_PADDING
    });

    // ==================== 设置页面（分栏模式）====================
    this.pageConfigs.set(PageConstants.PAGE_SETTINGS, {
      name: PageConstants.PAGE_SETTINGS,
      navigationMode: NavigationModeType.SPLIT,
      constrainMaxWidth: false,
      padding: PageConstants.SETTINGS_PAGE_PADDING
    });
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
      return {
        name: pageName,
        navigationMode: pageConfig.navigationMode,
        constrainMaxWidth: pageConfig.constrainMaxWidth ?? rootConfig.constrainMaxWidth,
        maxWidth: pageConfig.maxWidth ?? rootConfig.maxWidth,
        padding: pageConfig.padding ?? rootConfig.padding ?? PageConstants.HOME_PAGE_PADDING
      };
    }

    // 返回页面自己的配置或默认配置
    return pageConfig || {
      name: pageName,
      navigationMode: NavigationModeType.EXCLUSIVE,
      constrainMaxWidth: true,
      maxWidth: PageConstants.HOME_PAGE_MAX_WIDTH,
      padding: PageConstants.HOME_PAGE_PADDING
    };
  }

  /**
   * 判断是否是根页面
   */
  isRootPage(pageName: string): boolean {
    return NavigationConstants.isRootPage(pageName);
  }
}
