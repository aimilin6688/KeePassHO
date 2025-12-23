import { PromptAction, Router } from '@kit.ArkUI';
import { FileType, StorageConfig, StorageType } from '..';
import { OneDriveStorageConfig } from './OneDriveConfig';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { ResourceManager, FilenameUtils, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'OneDrive';

@Entry
@Component
struct OneDrive {
  @State clientId: string = '';
  @State clientSecret: string = '';
  @State tenantId: string = '';
  @State redirectUri: string = '';
  @State accessToken: string = '';
  @State refreshToken: string = '';
  @State isLoading: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.ONEDRIVE);
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  aboutToAppear(): void {
    this.initSaveParam();
  }

  onPageAppear(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
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
    const storageConfig = dbFileParam.storageConfig as OneDriveStorageConfig;
    if (storageConfig) {
      this.clientId = storageConfig.getClientIdText();
      this.clientSecret = storageConfig.getClientSecretText();
      this.tenantId = storageConfig.getTenantIdText();
      this.redirectUri = storageConfig.getRedirectUriText();
      this.accessToken = storageConfig.getAccessTokenText();
      this.refreshToken = storageConfig.getRefreshTokenText();
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
    this.router.pushUrl({
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
  private async testConnection(): void {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      this.fileManager.init(this.getStorageConfig());
      const exists = await this.fileManager.exists('/');
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
      hilog.error(DOMAIN, TAG, 'onedrive connection error: %{public}s', this.connectionStatus);
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 保存OneDrive配置（选择文件）
   */
  private async selectFile(): void {
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
      this.promptAction.showToast({ message: (error as Error).message });
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 导出数据库（选择目录）
   */
  private async selectDir(): void {
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
      this.promptAction.showToast({ message: (error as Error).message });
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
    if (!this.clientId) {
      this.connectionStatus = 'Please enter client ID';
      this.isErrorStatus = true;
      return false;
    }
    if (!this.clientSecret) {
      this.connectionStatus = 'Please enter client secret';
      this.isErrorStatus = true;
      return false;
    }
    if (!this.tenantId) {
      this.connectionStatus = 'Please enter tenant ID';
      this.isErrorStatus = true;
      return false;
    }
    if (!this.redirectUri) {
      this.connectionStatus = 'Please enter redirect URI';
      this.isErrorStatus = true;
      return false;
    }
    if (!this.accessToken) {
      this.connectionStatus = 'Please enter access token';
      this.isErrorStatus = true;
      return false;
    }
    if (!this.refreshToken) {
      this.connectionStatus = 'Please enter refresh token';
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
    return new OneDriveStorageConfig(
      this.clientId,
      this.clientSecret,
      this.tenantId,
      this.redirectUri,
      this.accessToken,
      this.refreshToken
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
          // 客户端ID输入
          Text('Client ID')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.clientId, placeholder: 'Enter client ID' })
            .height(40)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.clientId = value;
            })

          // 客户端密钥输入
          Text('Client Secret')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.clientSecret, placeholder: 'Enter client secret' })
            .height(40)
            .type(InputType.Password)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.clientSecret = value;
            })

          // 租户ID输入
          Text('Tenant ID')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.tenantId, placeholder: 'Enter tenant ID' })
            .height(40)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.tenantId = value;
            })

          // 重定向URI输入
          Text('Redirect URI')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.redirectUri, placeholder: 'Enter redirect URI' })
            .height(40)
            .type(TextAreaType.URL)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.redirectUri = value;
            })

          // 访问令牌输入
          Text('Access Token')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.accessToken, placeholder: 'Enter access token' })
            .height(40)
            .type(InputType.Password)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.accessToken = value;
            })

          // 刷新令牌输入
          Text('Refresh Token')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.refreshToken, placeholder: 'Enter refresh token' })
            .height(40)
            .type(InputType.Password)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.refreshToken = value;
            })

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
              .onClick(() => {
                this.handleConfirm();
              })
          }
          .width("100%")
        }
        .width('90%')
        .height('100%')
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
