/**
 * 页面配置常量
 *
 * 职责：管理页面布局尺寸、内边距、页面名称等配置
 */
export class PageConstants {
  // ==================== 首页相关页面配置 ====================

  /**
   * 首页内容最大宽度（vp）
   * 屏幕宽度 > 此值时内容居中显示，否则100%宽度
   */
  static readonly HOME_PAGE_MAX_WIDTH: number = 700;

  /**
   * 首页页面默认内边距（vp）
   */
  static readonly HOME_PAGE_PADDING: number = 16;

  // ==================== 数据库相关页面配置 ====================

  /**
   * 数据库页面 - 左侧列表默认宽度（vp）
   */
  static readonly DATABASE_LIST_WIDTH: number = 280;

  /**
   * 数据库页面 - 左侧列表最小宽度（vp）
   */
  static readonly DATABASE_LIST_MIN_WIDTH: number = 240;

  /**
   * 数据库页面 - 左侧列表最大宽度（vp）
   */
  static readonly DATABASE_LIST_MAX_WIDTH: number = 400;

  /**
   * 数据库页面 - 内容区内边距（vp）
   */
  static readonly DATABASE_PAGE_PADDING: number = 16;

  // ==================== 设置页面配置 ====================

  /**
   * 设置页面 - 左侧列表宽度（vp）
   */
  static readonly SETTINGS_LIST_WIDTH: number = 280;

  /**
   * 设置页面 - 内容区内边距（vp）
   */
  static readonly SETTINGS_PAGE_PADDING: number = 0;

  // ==================== 条目相关页面配置 ====================

  /**
   * 条目详情页面 - 内边距（vp）
   */
  static readonly ENTRY_PAGE_PADDING: number = 16;

  // ==================== 通用页面配置 ====================

  /**
   * 页面标题栏高度（vp）
   */
  static readonly TITLE_BAR_HEIGHT: number = 44;

  /**
   * 页面标题字体大小（fp）
   */
  static readonly TITLE_FONT_SIZE: number = 18;

  // ==================== 页面名称常量 ====================

  /**
   * 首页相关页面名称
   */
  static readonly PAGE_INDEX: string = 'Index';
  static readonly PAGE_PASSWORD: string = 'Password';
  static readonly PAGE_RECENT_FILES: string = 'RecentFiles';
  static readonly PAGE_SELECT_LOCATION: string = 'SelectLocation';
  static readonly PAGE_CREATE_DATABASE: string = 'CreateDatabase';
  static readonly PAGE_UNLOCK_DATABASE: string = 'UnLockDatabase';
  static readonly PAGE_CHANGE_PASSWORD: string = 'ChangePassword';
  static readonly PAGE_OAUTH2_LOGIN: string = 'OAuth2Login';
  static readonly PAGE_FILE_LIST: string = 'FileListPage';

  /**
   * 数据库相关页面名称
   */
  static readonly PAGE_DATABASE_VIEW: string = 'DatabaseView';
  static readonly PAGE_ENTRY_VIEW: string = 'EntryView';
  static readonly PAGE_ENTRY_EDIT: string = 'EntryEdit';
  static readonly PAGE_TOTP_VIEW: string = 'TotpView';
  static readonly PAGE_TEMPLATE_ENTRY_CREATE: string = 'TemplateEntryCreate';
  static readonly PAGE_EXPIRY_REPORT: string = 'ExpiryReport';

  /**
   * 设置相关页面名称
   */
  static readonly PAGE_SETTINGS: string = 'Settings';
  static readonly PAGE_SETTING_SECURITY: string = 'SettingSecurity';
  static readonly PAGE_SETTING_DATABASE: string = 'SettingDatabase';
  static readonly PAGE_SETTING_APPLICATION: string = 'SettingApplication';
  static readonly PAGE_SETTING_DATABASE_META: string = 'SettingDatabaseMeta';
  static readonly PAGE_SETTING_DATABASE_KEY_FUNCTION: string = 'SettingDatabaseKeyFunction';
  static readonly PAGE_SETTING_CUSTOM_ICONS: string = 'SettingCustomIcons';
  static readonly PAGE_SETTING_DATABASE_PROTECTED_FIELD: string = 'SettingDatabaseProtectedFiled';
  static readonly PAGE_SETTING_DATABASE_CLEAN: string = 'SettingDatabaseClean';
  static readonly PAGE_CHILD_DATABASES: string = 'ChildDatabases';
  static readonly PAGE_ABOUT: string = 'About';
  static readonly PAGE_SUPPORT: string = 'Support';
}
