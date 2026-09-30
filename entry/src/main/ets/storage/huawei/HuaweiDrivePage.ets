import { FileType, StorageConfig, StorageType } from '..';
import { HuaweiDriveStorageConfig, HuaweiDriveScope } from './HuaweiDriveConfig';
import { HuaweiDriveAbout } from './HuaweiDriveClient';
import { HuaweiDriveStorage } from './HuaweiDriveStorage';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { CommonUtils, ResourceManager, StorageNavigation, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';
import { HuaweiDriveOAuth2Provider } from './HuaweiDriveOAuth2Provider';
import { OAuth2AuthService, OAuth2Provider, OAuth2Token } from '../../common/oauth2';
import { AuthCallbackResult } from '../../pages/OAuth2Login';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDrive';

/**
 * handleStorageError 的可选配置
 */
interface StorageErrorHandleOptions {
  /** 自定义 toast 消息（默认显示 error.message） */
  toastMessage?: string;
  /** false 时不显示 toast（如 testConnection 仅用 connectionStatus 展示），默认 true */
  showToast?: boolean;
  /** true 时清空 aboutInfo（loadAboutInfo 场景），默认 false */
  resetAbout?: boolean;
}

// 华为云盘配置页面的Builder函数（NavDestination）
@Builder
export function HuaweiDrivePageBuilder(name: string, param: Object): void {
  NavDestination() {
    HuaweiDrive()
  }
  .title(StorageNavigation.getStorageTitle(StorageType.HUAWEI_DRIVE))
  .backgroundColor($r('app.color.bg_primary'))
  .onShown(() => {
    // NavDestination 下 onPageShow 不回调，通过计数驱动页面显示处理（含 OAuth2 回调）
    AppStorage.set<number>('huawei_page_shown_tick', (AppStorage.get<number>('huawei_page_shown_tick') ?? 0) + 1);
  })
}

@Component
struct HuaweiDrive {
  @State oauth2Token: OAuth2Token | null = null;
  @State isLoggedIn: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  @State selectedScope: HuaweiDriveScope = HuaweiDriveScope.FULL; // 默认选择完整访问
  @State aboutInfo: HuaweiDriveAbout | null = null; // 账户信息（用户名、容量）
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.HUAWEI_DRIVE);
  private oauth2Provider?: HuaweiDriveOAuth2Provider;

  aboutToAppear(): void {
    this.initSaveParam();
    this.loadTokenFromStorage();
  }

  // NavDestination 下 onPageShow 不回调，由 NavDestination.onShown 驱动页面显示处理
  @StorageProp('huawei_page_shown_tick') @Watch('onPageShownTickChange') pageShownTick: number = 0;

  onPageShownTickChange(): void {
    this.onPageShow();
  }

  onPageShow(): void {
    this.connectionStatus = '';
    hilog.debug(DOMAIN, TAG, 'HuaweiDrivePage onPageAppear');
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
    // 检查是否有从OAuth2登录页返回的授权结果
    const authResult = AppStorage.get<AuthCallbackResult>('oauth2_auth_result');
    if (authResult && authResult.codeFlow && authResult.codeFlow.code) {
      hilog.info(DOMAIN, TAG, `Received auth result with code length: ${authResult.codeFlow.code.length}`);
      this.handleAuthCallback(authResult.codeFlow.code, authResult.codeFlow.state);
      // 清除存储的授权结果
      AppStorage.delete('oauth2_auth_result');
    }
  }

  /**
   * 初始化OAuth2提供者
   */
  private initOAuth2Provider(): void {
    const oauth2Config = HuaweiDriveOAuth2Provider.getConfig(this.selectedScope);
    this.oauth2Provider = new HuaweiDriveOAuth2Provider(oauth2Config);
  }

  /**
   * 从存储服务加载令牌
   */
  private async loadTokenFromStorage(): Promise<void> {
    const token = await OAuth2AuthService.loadToken(OAuth2Provider.HUAWEI_DRIVE);
    if (token) {
      this.oauth2Token = token;
      this.isLoggedIn = true;
      this.loadAboutInfo();
    }
  }

  /**
   * 加载账户汇总信息（用户显示名、总容量、已用容量）
   */
  private async loadAboutInfo(): Promise<void> {
    if (!this.oauth2Token) {
      return;
    }
    const storage = new HuaweiDriveStorage(this.getStorageConfig());
    try {
      const about = await storage.getAbout();
      this.aboutInfo = about;
      hilog.info(DOMAIN, TAG, `About loaded: user=${about.user.displayName}, ` +
        `total=${about.space.totalSpace}, used=${about.space.usedSpace}`);
      // getAbout 内部可能已刷新并持久化令牌，重载最新令牌，避免页面继续持有过期/已轮换的旧令牌
      const latestToken = await OAuth2AuthService.loadToken(OAuth2Provider.HUAWEI_DRIVE);
      if (latestToken) {
        this.oauth2Token = latestToken;
      }
    } catch (error) {
      this.handleStorageError(error, 'Failed to load about info', {
        toastMessage: ResourceManager.getString($r('app.string.huawei_drive_load_about_failed'),
          (error as Error).message),
        resetAbout: true
      });
    } finally {
      storage.close();
    }
  }

  /**
   * 统一处理 storage 操作错误：
   * 1. 若为 AUTH_EXPIRED（refresh_token 失效）：重置登录状态、提示重新登录，返回 true
   * 2. 否则按通用错误处理：记录日志、设置 connectionStatus/isErrorStatus、可选显示 toast
   * @param error 捕获的错误
   * @param logTag 日志标识（用于 hilog 定位）
   * @param options 可选配置：
   *   - toastMessage: 非空时显示此消息 toast（默认显示 error.message）
   *   - showToast: false 时不显示 toast（如 testConnection 仅用 connectionStatus 展示）
   *   - resetAbout: true 时清空 aboutInfo（loadAboutInfo 场景）
   * @returns true 表示 AUTH_EXPIRED 已处理；false 表示按通用错误处理
   */
  private handleStorageError(
    error: Error,
    logTag: string,
    options?: StorageErrorHandleOptions
  ): boolean {
    // AUTH_EXPIRED：refresh_token 失效，重置登录态 + 提示重新登录
    if (error instanceof StorageError && error.code === StorageErrorCodes.AUTH_EXPIRED) {
      hilog.warn(DOMAIN, TAG, '%{public}s: auth expired, resetting login state', logTag);
      this.oauth2Token = null;
      this.isLoggedIn = false;
      this.aboutInfo = null;
      this.connectionStatus = ResourceManager.getString($r('app.string.huawei_drive_login_required'));
      this.isErrorStatus = true;
      CommonUtils.showToast({
        message: ResourceManager.getString($r('app.string.huawei_drive_auth_expired'))
      });
      return true;
    }

    // 通用错误：记录日志 + 设置状态 + 可选 toast
    hilog.error(DOMAIN, TAG, '%{public}s: %{public}s, stack:%{public}s',
      logTag, error.message, error.stack ?? '');
    this.connectionStatus = error.message;
    this.isErrorStatus = true;
    if (options?.resetAbout) {
      this.aboutInfo = null;
    }
    const showToast = options?.showToast ?? true;
    if (showToast) {
      const msg = options?.toastMessage ?? error.message;
      CommonUtils.showToast({ message: msg });
    }
    return false;
  }

  /**
   * 保存令牌到存储服务（加密）
   */
  /**
   * 生成授权URL并跳转到授权页面
   */
  private generateAuthUrl(): void {
    if (!this.oauth2Provider) {
      this.initOAuth2Provider();
    }
    const authUrl = this.oauth2Provider!.getAuthorizationUrl();
    hilog.info(DOMAIN, TAG, `Auth URL generated: ${authUrl}`);

    // 跳转到OAuth2登录页面
    StorageNavigation.pushOAuth2Login(authUrl, this.oauth2Provider!.getConfig(),
      ResourceManager.getString($r('app.string.huawei_drive_auth_title')));
  }

  /**
   * 处理授权回调
   * @param code 授权码
   * @param state 状态参数
   */
  private async handleAuthCallback(code: string, state: string): Promise<void> {
    if (!this.oauth2Provider) {
      this.initOAuth2Provider();
    }

    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.huawei_drive_authenticating'));
    this.isErrorStatus = false;

    try {
      const token = await OAuth2AuthService.exchangeCodeForToken(this.oauth2Provider!, code, state,
        OAuth2Provider.HUAWEI_DRIVE);

      this.oauth2Token = token;
      this.isLoggedIn = true;
      this.connectionStatus = ResourceManager.getString($r('app.string.huawei_drive_authentication_successful'));
      this.isErrorStatus = false;

      hilog.info(DOMAIN, TAG, `Token obtained, expires at: ${token.expiresAt}`);
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.huawei_drive_login_successful')) });
      this.loadAboutInfo();
    } catch (error) {
      this.connectionStatus = ResourceManager.getString($r('app.string.huawei_drive_authentication_failed_message'),
        (error as Error).message);
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, 'Authentication failed: %{public}s', (error as Error).message);
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.huawei_drive_authentication_failed')) });
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 登出
   */
  private async logout(): Promise<void> {
    try {
      await OAuth2AuthService.deleteToken(OAuth2Provider.HUAWEI_DRIVE);
      // 退出登录后清空路径→fileId 缓存（内存+磁盘），避免残留当前账号的映射数据
      await HuaweiDriveStorage.clearPathCache();

      this.oauth2Token = null;
      this.isLoggedIn = false;
      this.connectionStatus = '';
      this.oauth2Provider = undefined;
      this.aboutInfo = null;

      hilog.info(DOMAIN, TAG, 'Logged out successfully');
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.huawei_drive_logged_out')) });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to logout: %{public}s', (error as Error).message);
      CommonUtils.showToast({
        message: ResourceManager.getString($r('app.string.huawei_drive_logout_failed_message'),
          (error as Error).message)
      });
    }
  }

  /**
   * 初始化保存参数
   */
  private initSaveParam(): void {
    if (!LocationParam.isSaveMode()) {
      return;
    }
    const dbFileParam = FileService.getDbFileParam();
    if (dbFileParam.storageType !== StorageType.HUAWEI_DRIVE) {
      return;
    }
    const storageConfig = dbFileParam.storageConfig as HuaweiDriveStorageConfig;
    if (!storageConfig) {
      return;
    }
    // 重建 config 以恢复类方法
    const cfg = new HuaweiDriveStorageConfig(
      storageConfig.accessToken,
      storageConfig.refreshToken,
      storageConfig.expiresAt,
      {
        timeout: storageConfig.timeout,
        tokenType: storageConfig.tokenType,
        scope: storageConfig.scope
      }
    );
    this.oauth2Token = {
      tokenType: cfg.tokenType,
      accessToken: cfg.getAccessTokenText(),
      refreshToken: cfg.getRefreshTokenText(),
      expiresAt: cfg.expiresAt,
      scope: cfg.scope
    } as OAuth2Token;
    this.isLoggedIn = true;
  }

  /**
   * 校验参数合法性
   * @returns 是否通过校验
   */
  private checkParam(): boolean {
    if (!this.isLoggedIn) {
      this.connectionStatus = ResourceManager.getString($r('app.string.huawei_drive_login_required'));
      this.isErrorStatus = true;
      return false;
    }
    if (!this.oauth2Token || !this.oauth2Token.accessToken) {
      this.connectionStatus = ResourceManager.getString($r('app.string.huawei_drive_token_missing'));
      this.isErrorStatus = true;
      return false;
    }
    return true;
  }

  /**
   * 获取存储配置
   * @returns HuaweiDriveStorageConfig 华为云盘存储配置
   */
  private getStorageConfig(): HuaweiDriveStorageConfig {
    if (!this.oauth2Token) {
      return new HuaweiDriveStorageConfig('', '', 0, {});
    }
    return new HuaweiDriveStorageConfig(
      this.oauth2Token.accessToken,
      this.oauth2Token.refreshToken || '',
      this.oauth2Token.expiresAt ?? 0,
      {
        tokenType: this.oauth2Token.tokenType,
        scope: this.oauth2Token.scope
      }
    );
  }

  /**
   * 测试华为云盘连接
   */
  private async testConnection(): Promise<void> {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      hilog.info(DOMAIN, TAG, `testConnection: token exists=${!!this.oauth2Token}`);
      this.fileManager.init(this.getStorageConfig());
      const exists = await this.fileManager.exists('/');
      hilog.info(DOMAIN, TAG, `testConnection: exists result=${exists}`);
      if (exists) {
        this.connectionStatus = ResourceManager.getString($r('app.string.connection_success'));
        this.isErrorStatus = false;
      } else {
        this.connectionStatus = ResourceManager.getString($r('app.string.connection_failed'));
        this.isErrorStatus = true;
        hilog.error(DOMAIN, TAG, 'huawei drive connection error: %{public}s', this.connectionStatus);
      }
    } catch (error) {
      this.handleStorageError(error, 'huawei drive connection error', { showToast: false });
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 处理确认事件
   */
  private handleConfirm(): void {
    if (LocationParam.isSaveMode()) {
      this.selectDir();
    } else {
      this.selectFile();
    }
  }

  /**
   * 跳转到文件列表页面
   */
  private toFileList(): void {
    if (!this.checkParam()) {
      return;
    }
    StorageNavigation.pushFileList(StorageType.HUAWEI_DRIVE, '/', this.getStorageConfig());
  }

  /**
   * 选择文件（打开模式）
   */
  private async selectFile(): Promise<void> {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;
    try {
      const storageConfig = this.getStorageConfig();
      const fileInfo = await this.fileManager.init(storageConfig).getInfo('/');
      hilog.info(DOMAIN, TAG, `Loading Huawei Drive root: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
      if (fileInfo.type === FileType.DIR) {
        this.toFileList();
      } else {
        LocationParam.callOnLocation({
          mode: LocationParam.getMode(),
          filePath: '/',
          fileName: fileInfo.name,
          fileSuffix: LocationParam.getFileSuffix(),
          storageType: StorageType.HUAWEI_DRIVE,
          storageConfig: storageConfig
        });
      }
    } catch (error) {
      this.handleStorageError(error, 'Failed to load Huawei Drive');
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 选择目录（保存模式）
   */
  private async selectDir(): Promise<void> {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;
    try {
      const storageConfig = this.getStorageConfig();
      this.fileManager.init(storageConfig);
      this.connectionStatus = ResourceManager.getString($r('app.string.check_file_existing'));
      const existsFile = await this.fileManager.exists('/');
      hilog.info(DOMAIN, TAG, `Export file to Huawei Drive path: /`);
      if (existsFile) {
        this.connectionStatus = ResourceManager.getString($r('app.string.get_file_info'));
        const fileInfo = await this.fileManager.getInfo('/');
        hilog.info(DOMAIN, TAG, `Loading file info: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
        if (fileInfo.type === FileType.DIR) {
          this.toFileList();
        } else {
          this.handleSelectDir(storageConfig);
        }
      } else {
        this.handleSelectDir(storageConfig);
      }
    } catch (error) {
      this.handleStorageError(error, 'Failed to select file');
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 处理选择目录回调
   * @param storageConfig 存储配置
   */
  private handleSelectDir(storageConfig: StorageConfig): void {
    try {
      this.connectionStatus = ResourceManager.getString($r('app.string.save_saving'));
      LocationParam.callOnLocation({
        mode: LocationParam.getMode(),
        filePath: '/',
        fileName: ResourceManager.getString($r('app.string.huawei_drive_title')),
        fileSuffix: LocationParam.getFileSuffix(),
        storageType: StorageType.HUAWEI_DRIVE,
        storageConfig: storageConfig
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to export kdbx file: %{public}s', (error as Error).message);
      this.connectionStatus = (error as Error).message;
      this.isErrorStatus = true;
    }
  }

  /**
   * 格式化字节为可读字符串（KB/MB/GB）
   * @param bytes 字节数
   * @returns 格式化后的字符串
   */
  private formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    const base = 1024;
    let unitIndex = 0;
    let value = bytes;
    while (value >= base && unitIndex < units.length - 1) {
      value = value / base;
      unitIndex++;
    }
    return `${value.toFixed(2)} ${units[unitIndex]}`;
  }

  build() {
    Column() {
      // 标题栏与返回键由 NavDestination 系统标题栏提供
      Scroll() {
        Column() {
          if (!this.isLoggedIn) {
            // 未登录状态 - 显示授权范围选择和登录按钮
            Text($r('app.string.huawei_drive_select_scope'))
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 32, bottom: 16 })

            // 授权范围选择
            Row() {
              Radio({ value: 'full', group: 'scopeGroup' })
                .checked(this.selectedScope === HuaweiDriveScope.FULL)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.selectedScope = HuaweiDriveScope.FULL;
                  }
                })
              Column() {
                Text($r('app.string.huawei_drive_scope_full'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                Text($r('app.string.huawei_drive_scope_full_desc'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .margin({ bottom: 12 })
            .onClick(() => {
              this.selectedScope = HuaweiDriveScope.FULL;
            })

            Row() {
              Radio({ value: 'app', group: 'scopeGroup' })
                .checked(this.selectedScope === HuaweiDriveScope.APP_FILE)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.selectedScope = HuaweiDriveScope.APP_FILE;
                  }
                })
              Column() {
                Text($r('app.string.huawei_drive_scope_app'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                Text($r('app.string.huawei_drive_scope_app_desc'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .onClick(() => {
              this.selectedScope = HuaweiDriveScope.APP_FILE;
            })

            // 登录按钮
            Button($r('app.string.huawei_drive_login_button'))
              .width('100%')
              .height(44)
              .margin({ top: 32 })
              .backgroundColor($r('app.color.button_bg_blue'))
              .fontColor($r('app.color.button_text_blue'))
              .enabled(!this.isConnecting)
              .onClick(() => {
                this.generateAuthUrl();
              })
          } else {
            // 已登录状态
            Column() {
              Row() {
                Text($r('app.string.huawei_drive_authorized'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.success'))
                Blank()
                Text($r('app.string.huawei_drive_logout'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .onClick(() => {
                    this.logout();
                  })
              }
              .width('100%')

              Text(ResourceManager.getString($r('app.string.huawei_drive_scope_label'),
                this.selectedScope === HuaweiDriveScope.FULL
                  ? ResourceManager.getString($r('app.string.huawei_drive_scope_label_full'))
                  : ResourceManager.getString($r('app.string.huawei_drive_scope_label_app'))))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 8 })

              // 账户信息：用户显示名、总容量、已用容量
              if (this.aboutInfo) {
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ top: 12, bottom: 12 })

                Row() {
                  Text($r('app.string.huawei_drive_user'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.aboutInfo.user.displayName || '-')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                }
                .width('100%')

                Row() {
                  Text($r('app.string.huawei_drive_total_space'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.formatBytes(this.aboutInfo.space.totalSpace))
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                }
                .width('100%')
                .margin({ top: 8 })

                Row() {
                  Text($r('app.string.huawei_drive_used_space'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.formatBytes(this.aboutInfo.space.usedSpace))
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                }
                .width('100%')
                .margin({ top: 8 })
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(8)
            .margin({ top: 20 })
            .alignItems(HorizontalAlign.Start)
          }

          // 连接状态
          if (this.connectionStatus) {
            Text(this.connectionStatus)
              .fontSize(14)
              .margin({ top: 10 })
              .fontColor(this.isErrorStatus ? $r('app.color.error') : $r('app.color.success'))
          }

          // 加载中状态
          if (this.isConnecting) {
            Row() {
              LoadingProgress()
                .width(50)
                .height(50)
                .color($r('app.color.text_primary'))

              Text($r('app.string.connecting'))
                .fontSize(16)
                .margin({ left: 16 })
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ top: 20 })
          }

          if (this.isLoggedIn) {
            Row() {
              // 测试连接按钮
              Button($r('app.string.test_connection'))
                .height(40)
                .margin({ top: 20 })
                .backgroundColor(Color.Gray)
                .fontColor(Color.White)
                .enabled(!this.isConnecting)
                .onClick(() => {
                  this.testConnection();
                })
              Blank()
              // 确定按钮
              Button($r('app.string.confirm_button_text'))
                .height(40)
                .margin({ top: 20 })
                .backgroundColor($r('app.color.button_bg_blue'))
                .fontColor($r('app.color.button_text_blue'))
                .enabled(!this.isConnecting)
                .onClick(() => {
                  this.handleConfirm();
                })
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
