import { FileType, StorageConfig, StorageType } from '..';
import { BaiduNetdiskStorageConfig } from './BaiduNetdiskConfig';
import { BaiduNetdiskQuota, BaiduUserInfo } from './BaiduNetdiskTypes';
import { BaiduNetdiskStorage } from './BaiduNetdiskStorage';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { ClipboardUtils, CommonUtils, DateUtils, ResourceManager, StorageNavigation, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';
import { BaiduNetdiskOAuth2Provider, createBaiduNetdiskOAuth2Config } from './BaiduNetdiskOAuth2Provider';
import { OAuth2AuthService, OAuth2Provider, OAuth2Token } from '../../common/oauth2';
import BuildProfile from 'BuildProfile';
import { AuthCallbackResult } from '../../pages/OAuth2Login';

const DOMAIN = 0x0000;
const TAG = 'BaiduNetdisk';

// 百度网盘配置页面的Builder函数（NavDestination 由 BaiduNetdiskPage 组件自身构建，便于挂载 onShown 生命周期）
@Builder
export function BaiduNetdiskPageBuilder(name: string, param: Object): void {
  BaiduNetdiskPage()
}

@Component
struct BaiduNetdiskPage {
  @State oauth2Token: OAuth2Token | null = null;
  @State isLoggedIn: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  @State showManualEntry: boolean = false;
  @State manualCode: string = '';
  @State userInfo: BaiduUserInfo | null = null; // 账户信息（账号名、会员类型）
  @State quotaInfo: BaiduNetdiskQuota | null = null; // 网盘容量信息（总容量/已用/剩余）
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.BAIDU_NETDISK);
  private oauth2Provider?: BaiduNetdiskOAuth2Provider;
  /**
   * oob 手动授权码兜底 provider（redirectUri='oob'，授权码换令牌时 redirect_uri 必须匹配，D10）
   */
  private oobProvider?: BaiduNetdiskOAuth2Provider;

  aboutToAppear(): void {
    this.initSaveParam();
    this.loadTokenFromStorage();
  }

  /**
   * Router 时代的页面显示回调
   * 注意：分栏/Navigation 架构下 NavDestination 页面不会回调 onPageShow，
   * 因此授权结果处理统一走 handlePageShown()，由 NavDestination 的 onShown 触发。
   */
  onPageShow(): void {
    this.handlePageShown();
  }

  /**
   * 页面显示处理（首次进入 / 从 OAuth2 登录页返回 均会触发）
   */
  private handlePageShown(): void {
    this.connectionStatus = '';
    hilog.debug(DOMAIN, TAG, 'BaiduNetdiskPage onPageShown');
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
    // 检查是否有从OAuth2登录页返回的授权结果
    const authResult = AppStorage.get<AuthCallbackResult>('oauth2_auth_result');
    if (authResult && authResult.codeFlow && authResult.codeFlow.code) {
      hilog.info(DOMAIN, TAG, `Received auth result with code length: ${authResult.codeFlow.code.length}`);
      this.handleAuthCallback(authResult.codeFlow.code, authResult.codeFlow.state, this.getMainProvider());
      // 清除存储的授权结果
      AppStorage.delete('oauth2_auth_result');
    }
  }

  /**
   * 主授权 provider（自定义 scheme 回调，经应用内 OAuth2Login 页完成）
   */
  private getMainProvider(): BaiduNetdiskOAuth2Provider {
    if (!this.oauth2Provider) {
      this.oauth2Provider = new BaiduNetdiskOAuth2Provider(createBaiduNetdiskOAuth2Config(
        BuildProfile.BAIDU_NETDISK_CLIENT_ID,
        BuildProfile.BAIDU_NETDISK_CLIENT_SECRET,
        BuildProfile.BAIDU_NETDISK_REDIRECT_URI
      ));
    }
    return this.oauth2Provider;
  }

  /**
   * oob 手动授权码 provider（redirectUri='oob'，授权码换令牌时 redirect_uri 必须匹配）
   */
  private getOobProvider(): BaiduNetdiskOAuth2Provider {
    if (!this.oobProvider) {
      this.oobProvider = new BaiduNetdiskOAuth2Provider(createBaiduNetdiskOAuth2Config(
        BuildProfile.BAIDU_NETDISK_CLIENT_ID,
        BuildProfile.BAIDU_NETDISK_CLIENT_SECRET,
        'oob'
      ));
    }
    return this.oobProvider;
  }

  /**
   * 从存储服务加载令牌
   */
  private async loadTokenFromStorage(): Promise<void> {
    const token = await OAuth2AuthService.loadToken(OAuth2Provider.BAIDU_NETDISK);
    if (token) {
      this.oauth2Token = token;
      this.isLoggedIn = true;
      this.loadAccountInfo();
    }
  }

  /**
   * 加载账户信息（xpan uinfo 用户信息 + api/quota 容量信息）
   * 令牌刷新由存储层 ensureValidToken 内部处理并持久化
   */
  private async loadAccountInfo(): Promise<void> {
    if (!this.oauth2Token) {
      return;
    }
    const storage = new BaiduNetdiskStorage(this.getStorageConfig() as BaiduNetdiskStorageConfig);
    try {
      this.userInfo = await storage.getUserInfo();
      this.quotaInfo = await storage.getQuota();
      hilog.info(DOMAIN, TAG, 'Account info loaded: user=%{public}s, vipType=%{public}d, total=%{public}d, used=%{public}d',
        this.userInfo.netdiskName || this.userInfo.baiduName, this.userInfo.vipType,
        this.quotaInfo.total, this.quotaInfo.used);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load account info: %{public}s', (error as Error).message);
      this.userInfo = null;
      this.quotaInfo = null;
      this.connectionStatus = ResourceManager.getString($r('app.string.baidu_netdisk_load_account_failed'),
        (error as Error).message);
      this.isErrorStatus = true;
    }
  }

  /**
   * 生成授权URL并跳转到授权页面（自定义 scheme 回调）
   */
  private generateAuthUrl(): void {
    const provider = this.getMainProvider();
    const authUrl = provider.getAuthorizationUrl();
    hilog.info(DOMAIN, TAG, `Auth URL generated: ${authUrl}`);
    // 跳转到OAuth2登录页面
    StorageNavigation.pushOAuth2Login(authUrl, provider.getConfig(), '百度网盘授权');
  }

  /**
   * 复制 oob 授权链接（手动授权码兜底入口）
   */
  private copyOobAuthUrl(): void {
    const authUrl = this.getOobProvider().getAuthorizationUrl();
    ClipboardUtils.copy(authUrl, 0);
    hilog.info(DOMAIN, TAG, 'OOB auth URL copied');
  }

  /**
   * 手动授权码登录（oob 兜底）
   */
  private handleManualLogin(): void {
    const code = this.manualCode.trim();
    if (code.length === 0) {
      CommonUtils.showToast({
        message: ResourceManager.getString($r('app.string.baidu_netdisk_manual_code_empty'))
      });
      return;
    }
    this.handleAuthCallback(code, '', this.getOobProvider());
  }

  /**
   * 处理授权回调
   * @param code 授权码
   * @param state 状态参数
   * @param provider 完成授权码换令牌的 provider（主方案自定义 scheme / 兜底 oob）
   */
  private async handleAuthCallback(code: string, state: string,
    provider: BaiduNetdiskOAuth2Provider): Promise<void> {
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.baidu_netdisk_authenticating'));
    this.isErrorStatus = false;

    try {
      const token =
        await OAuth2AuthService.exchangeCodeForToken(provider, code, state, OAuth2Provider.BAIDU_NETDISK);

      this.oauth2Token = token;
      this.isLoggedIn = true;
      this.manualCode = '';
      this.connectionStatus = ResourceManager.getString($r('app.string.baidu_netdisk_authentication_successful'));
      this.isErrorStatus = false;

      hilog.info(DOMAIN, TAG, `Token obtained, expires at: ${token.expiresAt}`);
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.baidu_netdisk_login_successful')) });
      // 登录成功后加载账户信息（用户信息 + 网盘容量），类似华为云盘展示方式
      this.loadAccountInfo();
    } catch (error) {
      this.connectionStatus =
        ResourceManager.getString($r('app.string.baidu_netdisk_authentication_failed')) + `: ${(error as Error).message}`;
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, 'Authentication failed: %{public}s', (error as Error).message);
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.baidu_netdisk_authentication_failed')) });
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
    this.manualCode = '';
    this.userInfo = null;
    this.quotaInfo = null;
    this.oauth2Provider = undefined;
    this.oobProvider = undefined;
    await OAuth2AuthService.deleteToken(OAuth2Provider.BAIDU_NETDISK);
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
    if (!(dbFileParam.storageType === StorageType.BAIDU_NETDISK)) {
      return;
    }
    let storageConfig = dbFileParam.storageConfig as BaiduNetdiskStorageConfig;
    if (storageConfig) {
      storageConfig = new BaiduNetdiskStorageConfig(storageConfig.accessToken, storageConfig.refreshToken, storageConfig.expiresAt, {
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
    StorageNavigation.pushFileList(StorageType.BAIDU_NETDISK, '/', this.getStorageConfig());
  }

  /**
   * 测试百度网盘连接
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
        hilog.error(DOMAIN, TAG, 'baidu netdisk connection error: %{public}s', this.connectionStatus);
      }
    } catch (error) {
      this.connectionStatus = (error as Error).message;
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, `baidu netdisk connection error: ${error?.message}, stack: ${(error as Error).stack}`);
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 保存百度网盘配置（选择文件）
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
      hilog.info(DOMAIN, TAG, `Loading Baidu Netdisk root: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
      if (fileInfo.type === FileType.DIR) {
        this.toFileList();
      } else {
        // 回调位置信息
        LocationParam.callOnLocation({
          mode: LocationParam.getMode(),
          filePath: '/',
          fileName: fileInfo.name,
          fileSuffix: LocationParam.getFileSuffix(),
          storageType: StorageType.BAIDU_NETDISK,
          storageConfig: storageConfig
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load Baidu Netdisk: %{public}s, %{public}s, stack:%{public}s',
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
      hilog.info(DOMAIN, TAG, `Export file to Baidu Netdisk path: /`);
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
        fileName: 'BaiduNetdisk',
        fileSuffix: LocationParam.getFileSuffix(),
        storageType: StorageType.BAIDU_NETDISK,
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
      this.connectionStatus = 'Please login to Baidu Netdisk first';
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
   * @returns StorageConfig 存储配置
   */
  private getStorageConfig(): StorageConfig {
    if (!this.oauth2Token) {
      return {};
    }
    return new BaiduNetdiskStorageConfig(
      this.oauth2Token.accessToken,
      this.oauth2Token.refreshToken || '',
      this.oauth2Token.expiresAt || 0,
      {
        tokenType: this.oauth2Token.tokenType,
        scope: this.oauth2Token.scope
      }
    );
  }

  /**
   * 格式化字节为可读字符串（B/KB/MB/GB/TB）
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

  /**
   * 会员类型文案（vip_version=v2 语义：0-普通用户 1-会员用户 2-超级会员用户）
   */
  private getVipTypeText(): string {
    const vipType: number = this.userInfo?.vipType ?? 0;
    if (vipType === 2) {
      return ResourceManager.getString($r('app.string.baidu_netdisk_vip_svip'));
    }
    if (vipType === 1) {
      return ResourceManager.getString($r('app.string.baidu_netdisk_vip_member'));
    }
    return ResourceManager.getString($r('app.string.baidu_netdisk_vip_normal'));
  }

  build() {
    NavDestination() {
      Column() {
      // 主要内容区域（标题栏与返回键由 NavDestination 系统标题栏提供）
      Scroll() {
        Column() {
          // 登录状态提示
          if (this.isLoggedIn) {
            Column() {
              Row() {
                Text($r('app.string.baidu_netdisk_logged_in'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.success'))
                Blank()
                Text($r('app.string.baidu_netdisk_logout'))
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

              // 账户信息：用户、会员类型、总容量、已用容量、剩余容量
              if (this.userInfo && this.quotaInfo) {
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ top: 12, bottom: 12 })

                Row() {
                  Text($r('app.string.baidu_netdisk_user'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.userInfo.netdiskName || this.userInfo.baiduName || '-')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                }
                .width('100%')

                Row() {
                  Text($r('app.string.baidu_netdisk_vip_type'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.getVipTypeText())
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                }
                .width('100%')
                .margin({ top: 8 })

                Row() {
                  Text($r('app.string.baidu_netdisk_total_space'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.formatBytes(this.quotaInfo.total))
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                }
                .width('100%')
                .margin({ top: 8 })

                Row() {
                  Text($r('app.string.baidu_netdisk_used_space'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.formatBytes(this.quotaInfo.used))
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                }
                .width('100%')
                .margin({ top: 8 })

                Row() {
                  Text($r('app.string.baidu_netdisk_free_space'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.formatBytes(this.quotaInfo.free))
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
          } else {
            // 未登录状态
            Column() {
              Text($r('app.string.baidu_netdisk_login_prompt'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 20 })

              Button($r('app.string.baidu_netdisk_login_button'))
                .width('100%')
                .height(44)
                .margin({ top: 20 })
                .backgroundColor($r('app.color.button_bg_blue'))
                .fontColor($r('app.color.button_text_blue'))
                .onClick(() => {
                  this.generateAuthUrl();
                })

              // oob 手动授权码兜底入口
              Text($r('app.string.baidu_netdisk_manual_login_toggle'))
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 16 })
                .onClick(() => {
                  this.showManualEntry = !this.showManualEntry;
                })

              if (this.showManualEntry) {
                Column() {
                  Text($r('app.string.baidu_netdisk_manual_login_prompt'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))

                  Button($r('app.string.baidu_netdisk_copy_auth_url'))
                    .height(36)
                    .margin({ top: 12 })
                    .backgroundColor($r('app.color.button_bg_blue'))
                    .fontColor($r('app.color.button_text_blue'))
                    .onClick(() => {
                      this.copyOobAuthUrl();
                    })

                  TextInput({
                    placeholder: $r('app.string.baidu_netdisk_manual_code_placeholder'),
                    text: this.manualCode
                  })
                    .height(44)
                    .margin({ top: 12 })
                    .fontSize(14)
                    .onChange((value: string) => {
                      this.manualCode = value;
                    })

                  Button($r('app.string.baidu_netdisk_manual_code_exchange'))
                    .width('100%')
                    .height(40)
                    .margin({ top: 12 })
                    .backgroundColor($r('app.color.button_bg_blue'))
                    .fontColor($r('app.color.button_text_blue'))
                    .enabled(!this.isConnecting)
                    .onClick(() => {
                      this.handleManualLogin();
                    })
                }
                .width('100%')
                .margin({ top: 12 })
                .padding(12)
                .backgroundColor($r('app.color.card_bg'))
                .borderRadius(8)
                .alignItems(HorizontalAlign.Start)
              }
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
      .backgroundColor($r("app.color.bg_primary"))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .title(StorageNavigation.getStorageTitle(StorageType.BAIDU_NETDISK))
    .backgroundColor($r('app.color.bg_primary'))
    .onShown(() => {
      // Router 时代的 onPageShow 在 NavDestination 下不回调，
      // 这里保证从 OAuth2 登录页返回时能处理授权回调
      this.handlePageShown();
    })
  }
}
