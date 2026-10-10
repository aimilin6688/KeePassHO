import { PromptAction } from '@kit.ArkUI';
import { FileType, StorageConfig, StorageType } from '..';
import { PCloudStorageConfig } from './PCloudConfig';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { CommonUtils, DateUtils, ResourceManager, StorageNavigation, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';
import { createPCloudOAuth2Config, PCloudOAuth2Provider } from './PCloudOAuth2Provider';
import { OAuth2AuthService, OAuth2Provider, OAuth2Token } from '../../common/oauth2';
import BuildProfile from 'BuildProfile';
import { TokenFlowResult } from '../../pages/OAuth2Login';

const DOMAIN = 0x0000;
const TAG = 'PCloud';

// PCloud配置页面的Builder函数（NavDestination）
@Builder
export function PCloudPageBuilder(name: string, param: Object): void {
  NavDestination() {
    PCloud()
  }
  .title(StorageNavigation.getStorageTitle(StorageType.PCLOUD))
  .backgroundColor($r('app.color.bg_primary'))
  .onShown(() => {
    // NavDestination 下 onPageShow 不回调，通过计数驱动页面显示处理（含 OAuth2 回调）
    AppStorage.set<number>('pcloud_page_shown_tick', (AppStorage.get<number>('pcloud_page_shown_tick') ?? 0) + 1);
  })
}

@Component
struct PCloud {
  @State oauth2Token: OAuth2Token | null = null;
  @State isLoggedIn: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.PCLOUD);
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private oauth2Provider?: PCloudOAuth2Provider;

  aboutToAppear(): void {
    this.initSaveParam();
    this.loadTokenFromStorage();
  }

  // NavDestination 下 onPageShow 不回调，由 NavDestination.onShown 驱动页面显示处理
  @StorageProp('pcloud_page_shown_tick') @Watch('onPageShownTickChange') pageShownTick: number = 0;

  onPageShownTickChange(): void {
    this.onPageShow();
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
    const token = await OAuth2AuthService.loadToken(OAuth2Provider.PCLOUD);
    if (token) {
      this.oauth2Token = token;
      this.isLoggedIn = true;
    }
  }

  /**
   * 保存令牌到存储服务（加密）
   */

  /**
   * 生成授权 URL 并跳转到授权页面
   */
  private generateAuthUrl(): void {
    if (!this.oauth2Provider) {
      this.initOAuth2Provider();
    }
    const authUrl = this.oauth2Provider!.getAuthorizationUrl();
    hilog.info(DOMAIN, TAG, `Auth URL generated: ${authUrl}`);

    StorageNavigation.pushOAuth2Login(authUrl, this.oauth2Provider!.getConfig(),
      ResourceManager.getInstance().getString($r('app.string.pcloud_authorize_title')));
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

      await OAuth2AuthService.saveToken(OAuth2Provider.PCLOUD, this.oauth2Token);

      hilog.info(DOMAIN, TAG, `Token obtained, hostname: ${tokenFlow.hostname}`);
      CommonUtils.showToast({
        message: ResourceManager.getString($r('app.string.pcloud_login_successful'))
      });
      // 登录成功后继续选择文件的流程：直接进入文件列表
      this.toFileList();
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
    await OAuth2AuthService.deleteToken(OAuth2Provider.PCLOUD);
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
    StorageNavigation.pushFileList(StorageType.PCLOUD, '/', this.getStorageConfig());
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
    const hostname = this.oauth2Token.extraParams?.['hostname'];
    if (typeof hostname === 'string' && hostname.length > 0) {
      config.apiBaseUrl = 'https://' + hostname;
    }
    return config;
  }

  build() {
    Column() {
      // 主要内容区域（标题栏与返回键由 NavDestination 系统标题栏提供）
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
