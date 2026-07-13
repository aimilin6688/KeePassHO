import { NavPathStack, NavigationMode } from '@kit.ArkUI';
import { NavigationManager } from '../common/utils/NavigationManager';
import { PageConfigManager } from '../common/utils/PageConfigManager';
import { NavigationModeType } from '../common/constants/PageConfig';
import { NavigationConstants } from '../common/constants/NavigationConstants';
import { PageConstants } from '../common/constants/PageConstants';
import { PageContainer } from '../components/PageContainer';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'AppNavigation';

@Entry
@Component
struct AppNavigation {
  private navPathStack: NavPathStack = new NavPathStack();
  private navManager: NavigationManager = NavigationManager.getInstance();
  private configManager: PageConfigManager = PageConfigManager.getInstance();

  @State currentMode: NavigationMode = NavigationMode.Stack;

  aboutToAppear() {
    this.navManager.setNavPathStack(this.navPathStack);
    this.registerRoutes();
    this.navManager.navigateTo(PageConstants.PAGE_INDEX);
  }

  build() {
    this.updateNavigationMode();

    Navigation(this.navPathStack) {
      Column() {
        Text($r('app.string.loading'))
      }
    }
    .mode(this.currentMode)
    .navBarWidthRange(NavigationConstants.NAV_BAR_WIDTH_RANGE)
    .minContentWidth(NavigationConstants.MIN_CONTENT_WIDTH)
    .enableDragBar(true)
    .width('100%')
    .height('100%')
  }

  private updateNavigationMode() {
    const config = this.navManager.getCurrentPageConfig();
    this.currentMode = config.navigationMode === NavigationModeType.SPLIT
      ? NavigationMode.Auto
      : NavigationMode.Stack;
  }

  private registerRoutes() {
    // 首页相关页面
    this.navPathStack.bindRoute(PageConstants.PAGE_INDEX, this.IndexBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_PASSWORD, this.PasswordBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_RECENT_FILES, this.RecentFilesBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_SELECT_LOCATION, this.SelectLocationBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_CREATE_DATABASE, this.CreateDatabaseBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_UNLOCK_DATABASE, this.UnLockDatabaseBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_CHANGE_PASSWORD, this.ChangePasswordBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_OAUTH2_LOGIN, this.OAuth2LoginBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_LOCAL_FILE, this.LocalFilePageBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_WEBDAV, this.WebDAVPageBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_ONEDRIVE, this.OneDrivePageBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_FTP, this.FTPPageBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_S3, this.S3PageBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_PCLOUD, this.PCloudPageBuilder);

    // 数据库相关页面
    this.navPathStack.bindRoute(PageConstants.PAGE_DATABASE_VIEW, this.DatabaseViewBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_ENTRY_VIEW, this.EntryViewBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_ENTRY_EDIT, this.EntryEditBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_TOTP_VIEW, this.TotpViewBuilder);
    this.navPathStack.bindRoute(PageConstants.PAGE_TEMPLATE_ENTRY_CREATE, this.TemplateEntryCreateBuilder);

    // 设置
    this.navPathStack.bindRoute(PageConstants.PAGE_SETTINGS, this.SettingsBuilder);
  }

  // ============ 首页相关页面构建器（使用 PageContainer 自动处理最大宽度）============

  @Builder
  IndexBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_INDEX, context: this.getUIContext() }) {
      Index({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  PasswordBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_PASSWORD, context: this.getUIContext() }) {
      Password({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  RecentFilesBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_RECENT_FILES, context: this.getUIContext() }) {
      RecentFiles({
        navPathStack: this.navPathStack,
        source: (param as Record<string, string>)?.source || 'home'
      });
    }
  }

  @Builder
  SelectLocationBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_SELECT_LOCATION, context: this.getUIContext() }) {
      SelectLocation({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  CreateDatabaseBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_CREATE_DATABASE, context: this.getUIContext() }) {
      CreateDatabase({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  UnLockDatabaseBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_UNLOCK_DATABASE, context: this.getUIContext() }) {
      UnLockDatabase({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  ChangePasswordBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_CHANGE_PASSWORD, context: this.getUIContext() }) {
      ChangePassword({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  OAuth2LoginBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_OAUTH2_LOGIN, context: this.getUIContext() }) {
      OAuth2Login({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  LocalFilePageBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_LOCAL_FILE, context: this.getUIContext() }) {
      FileList({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  WebDAVPageBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_WEBDAV, context: this.getUIContext() }) {
      FileList({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  OneDrivePageBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_ONEDRIVE, context: this.getUIContext() }) {
      FileList({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  FTPPageBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_FTP, context: this.getUIContext() }) {
      FileList({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  S3PageBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_S3, context: this.getUIContext() }) {
      FileList({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  PCloudPageBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_PCLOUD, context: this.getUIContext() }) {
      FileList({ navPathStack: this.navPathStack });
    }
  }

  // ============ 数据库相关页面构建器（不限制宽度）============

  @Builder
  DatabaseViewBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_DATABASE_VIEW }) {
      DatabaseView({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  EntryViewBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_ENTRY_VIEW }) {
      EntryView({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  EntryEditBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_ENTRY_EDIT }) {
      EntryEdit({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  TotpViewBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_TOTP_VIEW }) {
      TotpView({ navPathStack: this.navPathStack });
    }
  }

  @Builder
  TemplateEntryCreateBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_TEMPLATE_ENTRY_CREATE }) {
      TemplateEntryCreate({ navPathStack: this.navPathStack });
    }
  }

  // ============ 设置页面构建器 ============

  @Builder
  SettingsBuilder(name: string, param: Object) {
    PageContainer({ pageName: PageConstants.PAGE_SETTINGS }) {
      Settings({ navPathStack: this.navPathStack });
    }
  }
}
