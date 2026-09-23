import { PromptAction } from '@kit.ArkUI';
import { FileType, StorageConfig, StorageType } from '..';
import { HuaweiDriveStorageConfig, HuaweiDriveScope } from './HuaweiDriveConfig';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { CommonUtils, DateUtils, ResourceManager, StorageNavigation, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';
import { HuaweiDriveOAuth2Provider } from './HuaweiDriveOAuth2Provider';
import { OAuth2AuthService, OAuth2Provider, OAuth2Token } from '../../common/oauth2';
import BuildProfile from 'BuildProfile';
import { AuthCallbackResult } from '../../pages/OAuth2Login';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDrive';

// 华为云盘配置页面的Builder函数（NavDestination）
@Builder
export function HuaweiDrivePageBuilder(name: string, param: Object): void {
  NavDestination() {
    HuaweiDrive()
  }
  .title(StorageNavigation.getStorageTitle(StorageType.HUAWEI_DRIVE))
  .backgroundColor($r('app.color.bg_primary'))
}

@Component
struct HuaweiDrive {
  @State oauth2Token: OAuth2Token | null = null;
  @State isLoggedIn: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  @State selectedScope: HuaweiDriveScope = HuaweiDriveScope.FULL; // 默认选择完整访问
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.HUAWEI_DRIVE);
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private oauth2Provider?: HuaweiDriveOAuth2Provider;

  aboutToAppear(): void {
    this.initSaveParam();
    this.loadTokenFromStorage();
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
    }
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
    StorageNavigation.pushOAuth2Login(authUrl, this.oauth2Provider!.getConfig(), '华为云盘授权');
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
    this.connectionStatus = '正在认证...';
    this.isErrorStatus = false;

    try {
      const token = await OAuth2AuthService.exchangeCodeForToken(this.oauth2Provider!, code, state,
        OAuth2Provider.HUAWEI_DRIVE);

      this.oauth2Token = token;
      this.isLoggedIn = true;
      this.connectionStatus = '认证成功';
      this.isErrorStatus = false;

      hilog.info(DOMAIN, TAG, `Token obtained, expires at: ${token.expiresAt}`);
      this.promptAction.showToast({ message: '登录成功' });
    } catch (error) {
      this.connectionStatus = `认证失败: ${(error as Error).message}`;
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, 'Authentication failed: %{public}s', (error as Error).message);
      this.promptAction.showToast({ message: '认证失败' });
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

      this.oauth2Token = null;
      this.isLoggedIn = false;
      this.connectionStatus = '';

      hilog.info(DOMAIN, TAG, 'Logged out successfully');
      this.promptAction.showToast({ message: '已退出登录' });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to logout: %{public}s', (error as Error).message);
      this.promptAction.showToast({ message: `退出失败: ${(error as Error).message}` });
    }
  }

  /**
   * 初始化保存参数
   */
  private initSaveParam(): void {
    const saveParam = AppStorage.get<LocationParam>('saveParam');
    if (saveParam) {
      // fileManager 不提供 setSaveParam，保存参数由各业务场景自行读取
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('华为云盘')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Divider()

      if (!this.isLoggedIn) {
        // 未登录状态 - 显示授权范围选择和登录按钮
        Column() {
          Text('选择授权范围')
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
              Text('完整访问云盘（推荐）')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Text('可以访问云盘中所有文件，适合需要在多个位置管理密码库的用户')
                .fontSize(14)
                .fontColor('#666666')
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })
          }
          .width('90%')
          .alignItems(VerticalAlign.Center)
          .padding(16)
          .backgroundColor('#F5F5F5')
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
              Text('仅访问应用文件')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Text('只能访问本应用创建的文件，更安全但无法打开已有的密码库文件')
                .fontSize(14)
                .fontColor('#666666')
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })
          }
          .width('90%')
          .alignItems(VerticalAlign.Center)
          .padding(16)
          .backgroundColor('#F5F5F5')
          .borderRadius(12)
          .onClick(() => {
            this.selectedScope = HuaweiDriveScope.APP_FILE;
          })

          // 登录按钮
          Button('登录华为账号')
            .width('90%')
            .height(48)
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor('#007DFF')
            .borderRadius(24)
            .margin({ top: 32 })
            .enabled(!this.isConnecting)
            .onClick(() => {
              this.generateAuthUrl();
            })

          // 连接状态
          if (this.connectionStatus) {
            Text(this.connectionStatus)
              .fontSize(14)
              .fontColor(this.isErrorStatus ? '#FF0000' : '#666666')
              .margin({ top: 16 })
          }
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        // 已登录状态 - 显示文件浏览器
        Column() {
          Text('已授权')
            .fontSize(16)
            .fontColor('#52C419')
            .margin({ top: 16, bottom: 8 })

          Text(`授权范围: ${this.selectedScope === HuaweiDriveScope.FULL ? '完整访问' : '仅应用文件'}`)
            .fontSize(14)
            .fontColor('#666666')
            .margin({ bottom: 16 })

          Button('退出登录')
            .width('90%')
            .height(48)
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor('#FF0000')
            .borderRadius(24)
            .onClick(() => {
              this.logout();
            })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}
