import { PromptAction, Router } from '@kit.ArkUI';
import { FileType, StorageConfig, StorageType } from '..';
import { OneDriveStorageConfig } from './OneDriveConfig';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { CommonUtils, DateUtils, ResourceManager, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';
import { createOneDriveOAuth2Config, OneDriveOAuth2Provider } from './OneDriveOAuth2Provider';
import { OAuth2AuthRequest, OAuth2Provider, OAuth2Token, OAuth2TokenStorageService } from '../../common/oauth2';
import BuildProfile from 'BuildProfile';
import { AuthResult } from '../../pages/OAuth2Login';

const DOMAIN = 0x0000;
const TAG = 'OneDrive';

@Entry
@Component
struct OneDrive {
  @State oauth2Token: OAuth2Token | null = null;
  @State isLoggedIn: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.ONEDRIVE);
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private oauth2Provider?: OneDriveOAuth2Provider;

  aboutToAppear(): void {
    this.initSaveParam();
    this.loadTokenFromStorage();
  }

  onPageShow(): void {
    this.connectionStatus = '';
    hilog.debug(DOMAIN, TAG, 'OneDrivePage onPageAppear');
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
    // 检查是否有从OAuth2登录页返回的授权结果
    const authResult = AppStorage.get<AuthResult>('oauth2_auth_result');
    if (authResult && authResult.code) {
      hilog.info(DOMAIN, TAG, `Received auth result with code length: ${authResult.code.length}`);
      this.handleAuthCallback(authResult.code, authResult.state);
      // 清除存储的授权结果
      AppStorage.delete('oauth2_auth_result');
    }
  }

  /**
   * 初始化OAuth2提供者
   */
  private initOAuth2Provider(): void {
    const oauth2Config = createOneDriveOAuth2Config(
      BuildProfile.ONE_DRIVE_CLIENT_ID,
      BuildProfile.ONE_DRIVE_CLIENT_SECRET,
      BuildProfile.ONE_DRIVE_REDIRECT_URI,
      'Files.ReadWrite User.Read offline_access',
      BuildProfile.ONE_DRIVE_TENANT_ID
    );
    this.oauth2Provider = new OneDriveOAuth2Provider(oauth2Config);
  }

  /**
   * 从存储服务加载令牌
   */
  private async loadTokenFromStorage(): Promise<void> {
    try {
      const storageService = OAuth2TokenStorageService.getInstance();
      const token = await storageService.loadToken({
        provider: OAuth2Provider.ONEDRIVE,
        encrypt: true
      });

      if (token) {
        this.oauth2Token = token;
        this.isLoggedIn = true;
        hilog.info(DOMAIN, TAG, 'Token loaded from storage service');
      } else {
        hilog.debug(DOMAIN, TAG, 'No token found in storage service');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load token from storage service: %{public}s', (error as Error).message);
    }
  }

  /**
   * 保存令牌到存储服务（加密）
   */
  private async saveTokenToStorage(): Promise<void> {
    if (!this.oauth2Token) {
      return;
    }

    try {
      const storageService = OAuth2TokenStorageService.getInstance();
      await storageService.saveToken(this.oauth2Token, {
        provider: OAuth2Provider.ONEDRIVE,
        encrypt: true
      });
      hilog.info(DOMAIN, TAG, 'Token saved to storage service');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to save token to storage service: %{public}s', (error as Error).message);
    }
  }

  /**
   * 清除保存的令牌
   */
  private async clearTokenFromStorage(): Promise<void> {
    try {
      const storageService = OAuth2TokenStorageService.getInstance();
      await storageService.deleteToken({
        provider: OAuth2Provider.ONEDRIVE,
        encrypt: true
      });
      hilog.info(DOMAIN, TAG, 'Token cleared from storage service');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to clear token from storage service: %{public}s', (error as Error).message);
    }
  }

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
    CommonUtils.pushUrl({
      url: 'pages/OAuth2Login',
      params: {
        authUrl: authUrl,
        oauth2Config: this.oauth2Provider!.getConfig()
      }
    });
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
    this.connectionStatus = ResourceManager.getString($r('app.string.onedrive_authenticating'));
    this.isErrorStatus = false;

    try {
      const authRequest: OAuth2AuthRequest = {
        code: code,
        state: state
      };

      const token = await this.oauth2Provider!.authorize(authRequest);

      this.oauth2Token = token;
      this.isLoggedIn = true;
      this.connectionStatus = ResourceManager.getString($r('app.string.onedrive_authentication_successful'));
      this.isErrorStatus = false;

      // 保存令牌到存储服务（加密）
      await this.saveTokenToStorage();

      hilog.info(DOMAIN, TAG, `Token obtained, expires at: ${token.expiresAt}`);
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.onedrive_login_successful')) });
    } catch (error) {
      this.connectionStatus = ResourceManager.getString($r('app.string.onedrive_authentication_failed')) + `: ${(error as Error).message}`;
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, 'Authentication failed: %{public}s', (error as Error).message);
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.onedrive_authentication_failed')) });
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 注销登录
   */
  private async logout(): Promise<void> {
    this.oauth2Token = null;
    this.isLoggedIn = false;
    this.connectionStatus = '';
    this.oauth2Provider = undefined;
    await this.clearTokenFromStorage();
  }

  /**
   * 导出数据初始化
   */
  private initSaveParam(): void {
    if (!LocationParam.isSaveMode()) {
      return;
    }
    // 初始化导出
    const dbFileParam = FileService.getDbFileParam();
    if (!(dbFileParam.storageType === StorageType.ONEDRIVE)) {
      return;
    }
    let storageConfig = dbFileParam.storageConfig as OneDriveStorageConfig;
    if (storageConfig) {
      storageConfig = new OneDriveStorageConfig(storageConfig.accessToken, storageConfig.refreshToken, storageConfig.expiresAt, {
        timeout: storageConfig.timeout,
        scope: storageConfig.scope,
        tokenType: storageConfig.tokenType
      });
      this.oauth2Token = {
        tokenType: storageConfig.tokenType,
        accessToken: storageConfig.getAccessTokenText(),
        refreshToken: storageConfig.getRefreshTokenText(),
        expiresAt: storageConfig.expiresAt,
        scope: storageConfig.scope
      } as OAuth2Token;
    }
  }

  /**
   * 处理确认事件
   */
  private handleConfirm(): void {
    // 导出数据库
    if (LocationParam.isSaveMode()) {
      this.selectDir();
    } else {
      this.selectFile();
    }
  }

  /**
   * 跳转到文件预览页面
   */
  private toFileList(): void {
    if (!this.checkParam()) {
      return;
    }
    CommonUtils.pushUrl({
      url: 'pages/open/FileList',
      params: {
        mode: LocationParam.getMode(),
        filePath: '/',
        fileSuffix: LocationParam.getFileSuffix(),
        fileName: LocationParam.getFileName(),
        storageType: StorageType.ONEDRIVE,
        storageConfig: this.getStorageConfig()
      }
    });
  }

  /**
   * 测试OneDrive连接
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
      hilog.debug(DOMAIN, TAG, 'testConnection: Calling exists("/")');
      const exists = await this.fileManager.exists('/');
      hilog.info(DOMAIN, TAG, `testConnection: exists result=${exists}`);
      if (exists) {
        this.connectionStatus = ResourceManager.getString($r('app.string.connection_success'));
        this.isErrorStatus = false;
      } else {
        this.connectionStatus = ResourceManager.getString($r('app.string.connection_failed'));
        this.isErrorStatus = true;
        hilog.error(DOMAIN, TAG, 'onedrive connection error: %{public}s', this.connectionStatus);
      }
    } catch (error) {
      this.connectionStatus = (error as Error).message;
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, `onedrive connection error: ${error?.message}, stack: ${(error as Error).stack}`);
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 保存OneDrive配置（选择文件）
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
      // 获取文件信息
      const fileInfo = await this.fileManager.init(storageConfig).getInfo('/');
      hilog.info(DOMAIN, TAG, `Loading OneDrive root: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
      if (fileInfo.type === FileType.DIR) {
        this.toFileList();
      } else {
        // 回调位置信息
        LocationParam.callOnLocation({
          mode: LocationParam.getMode(),
          filePath: '/',
          fileName: fileInfo.name,
          fileSuffix: LocationParam.getFileSuffix(),
          storageType: StorageType.ONEDRIVE,
          storageConfig: storageConfig
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load OneDrive: %{public}s, %{public}s, stack:%{public}s',
        '/', (error as Error).message, (error as Error).stack);
      this.connectionStatus = (error as Error).message;
      this.isErrorStatus = true;
      CommonUtils.showToast({ message: (error as Error).message });
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 导出数据库（选择目录）
   */
  private async selectDir(): Promise<void> {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;
    try {
      // 配置信息
      const storageConfig = this.getStorageConfig();
      this.fileManager.init(storageConfig);
      this.connectionStatus = ResourceManager.getString($r("app.string.check_file_existing"));
      // 获取文件信息
      const existsFile = await this.fileManager.exists('/');
      hilog.info(DOMAIN, TAG, `Export file to OneDrive path: /`);
      if (existsFile) {
        // 获取文件类型
        this.connectionStatus = ResourceManager.getString($r('app.string.get_file_info'));
        const fileInfo = await this.fileManager.getInfo('/');
        hilog.info(DOMAIN, TAG, `Loading file info: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
        // 如果是文件夹，则跳转到文件列表页面
        if (fileInfo.type === FileType.DIR) {
          this.toFileList();
        } else {
          this.handleSelectDir(storageConfig);
        }
      } else {
        this.handleSelectDir(storageConfig);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to select file: %{public}s, %{public}s, stack:%{public}s',
        '/', (error as Error).message, (error as Error).stack);
      this.connectionStatus = (error as Error).message;
      this.isErrorStatus = true;
      CommonUtils.showToast({ message: (error as Error).message });
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 处理选择目录
   * @param storageConfig 存储配置
   */
  private handleSelectDir(storageConfig: StorageConfig): void {
    try {
      this.connectionStatus = ResourceManager.getString($r('app.string.save_saving'));
      // 回调位置信息
      LocationParam.callOnLocation({
        mode: LocationParam.getMode(),
        filePath: '/',
        fileName: 'OneDrive',
        fileSuffix: LocationParam.getFileSuffix(),
        storageType: StorageType.ONEDRIVE,
        storageConfig: storageConfig
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to export kdbx file: %{public}s', (error as Error).message);
      this.connectionStatus = (error as Error).message;
      this.isErrorStatus = true;
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 校验参数合法性
   * @returns 是否通过校验
   */
  private checkParam(): boolean {
    if (!this.isLoggedIn) {
      this.connectionStatus = 'Please login to OneDrive first';
      this.isErrorStatus = true;
      return false;
    }
    if (!this.oauth2Token || !this.oauth2Token.accessToken) {
      this.connectionStatus = 'Access token is missing';
      this.isErrorStatus = true;
      return false;
    }
    return true;
  }

  /**
   * 获取存储配置
   * @returns OneDriveStorageConfig 存储配置
   */
  private getStorageConfig(): StorageConfig {
    if (!this.oauth2Token) {
      return {};
    }
    return new OneDriveStorageConfig(
      this.oauth2Token.accessToken,
      this.oauth2Token.refreshToken || '',
      this.oauth2Token.expiresAt || 0,
      {
        tokenType: this.oauth2Token.tokenType,
        scope: this.oauth2Token.scope
      }
    );
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back()
          })

        Text('OneDrive')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)

      // 主要内容区域
      Scroll() {
        Column() {
          // 登录状态提示
          if (this.isLoggedIn) {
            Column() {
              Row() {
                Text($r('app.string.onedrive_logged_in'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.success'))
                Blank()
                Text($r('app.string.onedrive_logout'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .onClick(() => {
                    this.logout();
                  })
              }
              .width('100%')

              // 令牌过期时间
              if (this.oauth2Token && this.oauth2Token.expiresAt && this.oauth2Token.expiresAt > 0) {
                Text(`令牌过期时间: ${DateUtils.format(new Date(this.oauth2Token.expiresAt))}`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 8 })
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(8)
            .margin({ top: 20 })
            .alignItems(HorizontalAlign.Start)
          } else {
            // 未登录状态
            Column() {
              Text($r('app.string.onedrive_login_prompt'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 20 })

              Button($r('app.string.onedrive_login_button'))
                .width('100%')
                .height(44)
                .margin({ top: 20 })
                .backgroundColor($r('app.color.button_bg_blue'))
                .fontColor($r('app.color.button_text_blue'))
                .onClick(() => {
                  this.generateAuthUrl();
                })
            }
            .width('100%')
          }

          // 连接状态
          if (this.connectionStatus) {
            Text(this.connectionStatus)
              .fontSize(14)
              .margin({ top: 10 })
              .fontColor(this.isErrorStatus ? $r("app.color.error") : $r('app.color.success'))
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
                .margin({ top: 16 })
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
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
            .width("100%")
          }
        }
        .width('90%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
