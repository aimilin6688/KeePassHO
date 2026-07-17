import { PromptAction, Router } from '@kit.ArkUI';
import { FileType, StorageConfig, StorageType } from '..';
import { PCloudStorageConfig } from './PCloudConfig';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { CommonUtils, DateUtils, ResourceManager, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';
import { createPCloudOAuth2Config, PCloudOAuth2Provider } from './PCloudOAuth2Provider';
import { OAuth2Provider, OAuth2Token, OAuth2TokenStorageService } from '../../common/oauth2';
import BuildProfile from 'BuildProfile';
import { TokenFlowResult } from '../../pages/OAuth2Login';

const DOMAIN = 0x0000;
const TAG = 'PCloud';

@Entry
@Component
struct PCloud {
  @State oauth2Token: OAuth2Token | null = null;
  @State isLoggedIn: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.PCLOUD);
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private oauth2Provider?: PCloudOAuth2Provider;

  aboutToAppear(): void {
    this.initSaveParam();
    this.loadTokenFromStorage();
  }

  onPageShow(): void {
    this.connectionStatus = '';
    hilog.debug(DOMAIN, TAG, 'PCloudPage onPageAppear');
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);

    // 检查是否有从 OAuth2 登录页返回的授权结果
    const authResult = AppStorage.get<TokenFlowResult>('oauth2_auth_result');
    if (authResult) {
      AppStorage.delete('oauth2_auth_result');

      if (authResult.error) {
        hilog.warn(DOMAIN, TAG, `Auth error: ${authResult.error}`);
        this.connectionStatus = ResourceManager.getString($r('app.string.pcloud_authentication_failed')) +
          ': ' + authResult.error;
        this.isErrorStatus = true;
      } else if (authResult.accessToken) {
        hilog.info(DOMAIN, TAG, `Received token with length: ${authResult.accessToken.length}`);
        this.handleTokenFlowCallback(authResult);
      }
    }
  }

  /**
   * 初始化 OAuth2 提供者
   */
  private initOAuth2Provider(): void {
    const oauth2Config = createPCloudOAuth2Config(
      BuildProfile.PCLOUD_CLIENT_ID,
      BuildProfile.PCLOUD_REDIRECT_URI,
      'https://api.pcloud.com'
    );
    this.oauth2Provider = new PCloudOAuth2Provider(oauth2Config);
  }

  /**
   * 从存储服务加载令牌
   */
  private async loadTokenFromStorage(): Promise<void> {
    try {
      const storageService = OAuth2TokenStorageService.getInstance();
      const token = await storageService.loadToken({
        provider: OAuth2Provider.PCLOUD,
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
        provider: OAuth2Provider.PCLOUD,
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
        provider: OAuth2Provider.PCLOUD,
        encrypt: true
      });
      hilog.info(DOMAIN, TAG, 'Token cleared from storage service');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to clear token from storage service: %{public}s', (error as Error).message);
    }
  }

  /**
   * 生成授权 URL 并跳转到授权页面
   */
  private generateAuthUrl(): void {
    if (!this.oauth2Provider) {
      this.initOAuth2Provider();
    }
    const authUrl = this.oauth2Provider!.getAuthorizationUrl();
    hilog.info(DOMAIN, TAG, `Auth URL generated: ${authUrl}`);

    CommonUtils.pushUrl({
      url: 'pages/OAuth2Login',
      params: {
        authUrl: authUrl,
        oauth2Config: this.oauth2Provider!.getConfig(),
        pageTitle: ResourceManager.getInstance().getString($r('app.string.pcloud_authorize_title'))
      }
    });
  }

  /**
   * 处理 Token Flow 回调
   */
  private async handleTokenFlowCallback(tokenFlow: TokenFlowResult): Promise<void> {
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.pcloud_authenticating'));
    this.isErrorStatus = false;

    try {
      const token: OAuth2Token = {
        accessToken: tokenFlow.accessToken,
        tokenType: tokenFlow.tokenType || 'bearer',
        extraParams: {}
      };

      if (tokenFlow.uid) {
        token.extraParams!['uid'] = tokenFlow.uid;
      }
      if (tokenFlow.locationid) {
        token.extraParams!['locationid'] = tokenFlow.locationid;
      }
      if (tokenFlow.hostname) {
        token.extraParams!['hostname'] = tokenFlow.hostname;
        if (this.oauth2Provider) {
          this.oauth2Provider.setApiBaseUrl(`https://${tokenFlow.hostname}`);
        }
      }

      this.oauth2Token = token;
      this.isLoggedIn = true;
      this.connectionStatus = ResourceManager.getString($r('app.string.pcloud_authentication_successful'));
      this.isErrorStatus = false;

      await this.saveTokenToStorage();

      hilog.info(DOMAIN, TAG, `Token obtained, hostname: ${tokenFlow.hostname}`);
      CommonUtils.showToast({
        message: ResourceManager.getString($r('app.string.pcloud_login_successful'))
      });
    } catch (error) {
      this.connectionStatus = ResourceManager.getString($r('app.string.pcloud_authentication_failed')) +
        ': ' + (error as Error).message;
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, 'Authentication failed: %{public}s', (error as Error).message);
      CommonUtils.showToast({
        message: ResourceManager.getString($r('app.string.pcloud_authentication_failed'))
      });
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
    const dbFileParam = FileService.getDbFileParam();
    if (dbFileParam.storageType !== StorageType.PCLOUD) {
      return;
    }
    const storageConfig = dbFileParam.storageConfig as PCloudStorageConfig;
    if (storageConfig) {
      this.oauth2Token = {
        tokenType: 'bearer',
        accessToken: storageConfig.accessToken,
        expiresAt: storageConfig.expireAt
      } as OAuth2Token;
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
        storageType: StorageType.PCLOUD,
        storageConfig: this.getStorageConfig()
      }
    });
  }

  /**
   * 测试 pCloud 连接
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
      }
    } catch (error) {
      this.connectionStatus = (error as Error).message;
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, `pcloud connection error: ${(error as Error).message}`);
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 选择文件
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
      hilog.info(DOMAIN, TAG, `Loading pCloud root: ${fileInfo.name}`);
      if (fileInfo.type === FileType.DIR) {
        this.toFileList();
      } else {
        LocationParam.callOnLocation({
          mode: LocationParam.getMode(),
          filePath: '/',
          fileName: fileInfo.name,
          fileSuffix: LocationParam.getFileSuffix(),
          storageType: StorageType.PCLOUD,
          storageConfig: storageConfig
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load pCloud: %{public}s', (error as Error).message);
      this.connectionStatus = (error as Error).message;
      this.isErrorStatus = true;
      CommonUtils.showToast({ message: (error as Error).message });
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 选择目录（导出）
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
      hilog.info(DOMAIN, TAG, `Export file to pCloud path: /`);

      if (existsFile) {
        this.connectionStatus = ResourceManager.getString($r('app.string.get_file_info'));
        const fileInfo = await this.fileManager.getInfo('/');
        hilog.info(DOMAIN, TAG, `Loading file info: ${fileInfo.name}`);
        if (fileInfo.type === FileType.DIR) {
          this.toFileList();
        } else {
          this.handleSelectDir(storageConfig);
        }
      } else {
        this.handleSelectDir(storageConfig);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to select file: %{public}s', (error as Error).message);
      this.connectionStatus = (error as Error).message;
      this.isErrorStatus = true;
      CommonUtils.showToast({ message: (error as Error).message });
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 处理选择目录
   */
  private handleSelectDir(storageConfig: StorageConfig): void {
    try {
      this.connectionStatus = ResourceManager.getString($r('app.string.save_saving'));
      LocationParam.callOnLocation({
        mode: LocationParam.getMode(),
        filePath: '/',
        fileName: 'pCloud',
        fileSuffix: LocationParam.getFileSuffix(),
        storageType: StorageType.PCLOUD,
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
   */
  private checkParam(): boolean {
    if (!this.isLoggedIn) {
      this.connectionStatus = ResourceManager.getString($r('app.string.pcloud_login_first'));
      this.isErrorStatus = true;
      return false;
    }
    if (!this.oauth2Token || !this.oauth2Token.accessToken) {
      this.connectionStatus = ResourceManager.getString($r('app.string.pcloud_token_missing'));
      this.isErrorStatus = true;
      return false;
    }
    return true;
  }

  /**
   * 获取存储配置
   */
  private getStorageConfig(): StorageConfig {
    if (!this.oauth2Token) {
      return {};
    }
    const config = new PCloudStorageConfig();
    config.accessToken = this.oauth2Token.accessToken;
    if (this.oauth2Token.expiresAt && this.oauth2Token.expiresAt > 0) {
      config.expireAt = this.oauth2Token.expiresAt;
    }
    return config;
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

        Text('pCloud')
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
                Text($r('app.string.pcloud_logged_in'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.success'))
                Blank()
                Text($r('app.string.pcloud_logout'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .onClick(() => {
                    this.logout();
                  })
              }
              .width('100%')

              if (this.oauth2Token && this.oauth2Token.expiresAt && this.oauth2Token.expiresAt > 0) {
                Text(ResourceManager.getString($r('app.string.pcloud_token_expire'),
                  DateUtils.format(new Date(this.oauth2Token.expiresAt))))
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
              Text($r('app.string.pcloud_login_prompt'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 20 })

              Button($r('app.string.pcloud_login_button'))
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

              Text(ResourceManager.getString($r('app.string.connecting')))
                .fontSize(16)
                .margin({ top: 16 })
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
          }

          if (this.isLoggedIn) {
            Row() {
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
