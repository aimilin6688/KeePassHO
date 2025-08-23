import { PromptAction, Router } from '@kit.ArkUI';
import { StorageConfig, StorageType } from '../../services/kdbx/interfaces';
import { WebDAVStorageConfig } from '../../services/kdbx/interfaces/StorageConfig';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import ResourceManager from '../../common/utils/ResourceManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { RecentFilesService } from '../../services/RecentFilesService';
import { ExportType } from '../SettingDatabase';
import { KdbxExportService } from '../../services/kdbx/KdbxExportService';

const DOMAIN = 0x0000;
const TAG = 'WebDAV';


@Entry
@Component
struct WebDAV {
  @State url: string = '';
  @State username: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.WEBDAV);
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private exportType: ExportType | undefined = undefined;

  onPageShow(): void {
    const params = this.router.getParams() as Record<string, string>;
    this.exportType = params ? params.exportType as ExportType : undefined;
    this.initExport();
  }

  // 导出数据初始化
  private initExport() {
    if (!this.exportType) {
      return;
    }
    // 初始化导出
    const dbFileParam = FileService.getDbFileParam();
    if (!(dbFileParam.storageType === StorageType.WEBDAV)) {
      return;
    }
    const storageConfig = dbFileParam.storageConfig as WebDAVStorageConfig;
    if (storageConfig) {
      this.url = KdbxExportService.createFileName(storageConfig.url, this.exportType);
      this.username = WebDAVStorageConfig.getText(storageConfig.username);
      this.password = WebDAVStorageConfig.getText(storageConfig.password);
    }
  }

  // 处理确认时间
  private handleConfirm() {
    // 导出数据库
    if (this.exportType) {
      this.exportDatabase();
    } else {
      this.loadDatabase();
    }
  }

  // 测试WebDAV连接
  private async testConnection() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      // 简单测试连接
      this.fileManager.init(this.getStorageConfig())
        .exists(this.url)
        .then(result => {
          if (result) {
            this.connectionStatus = ResourceManager.getString($r('app.string.connection_success'));
            this.isErrorStatus = false;
          } else {
            this.connectionStatus = ResourceManager.getString($r('app.string.connection_failed'));
            this.isErrorStatus = true;
            hilog.error(DOMAIN, TAG, 'webdav connection error: %{public}s', this.connectionStatus);
          }
        })
        .catch((error: Error) => {
          this.connectionStatus = error.message;
          this.isErrorStatus = true;
          hilog.error(DOMAIN, TAG, 'webdav connection error: %{public}s', this.connectionStatus);
        });
    } finally {
      this.isConnecting = false;
    }
  }

  // 保存WebDAV配置
  private async loadDatabase() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;
    try {
      const storageConfig = this.getStorageConfig();
      // 获取文件信息
      const fileInfo = await this.fileManager.init(storageConfig).getFileInfo(this.url);
      hilog.info(DOMAIN, TAG, `Loading KDBX file: ${fileInfo.name}, size: ${fileInfo.size} bytes`);

      // 设置文件参数
      FileService.setFileParam({
        filePath: this.url,
        fileName: fileInfo.name,
        storageType: StorageType.WEBDAV,
        storageConfig: storageConfig
      });
      // 添加到最近打开的文件列表
      RecentFilesService.addRecentFile({
        filePath: this.url,
        fileName: fileInfo.name,
        storageType: StorageType.WEBDAV,
        storageConfig: storageConfig
      });
      // 导航到密码输入页面
      this.router.pushUrl({
        url: 'pages/Password'
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load KDBX file: %{public}s, %{public}s, stack:%{public}s', this.url, error.message, error.stack);
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
      this.promptAction.showToast({ message: error.message });
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 导出数据库
   */
  private async exportDatabase() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    const storageConfig = this.getStorageConfig();
    // 获取文件信息
    const existsFile = await this.fileManager.init(storageConfig).exists(this.url);
    hilog.info(DOMAIN, TAG, `Export kdbx file to webDAV path: ${this.url}`);
    if (existsFile) {
      this.promptAction.showDialog({
        title: $r('app.string.dialog_prompt_title'),
        message: $r('app.string.dialog_exists_file_message'),
        buttons: [
          {
            text: $r('app.string.cancel_button_text'),
            color: $r('app.color.text_secondary')
          },
          {
            text: $r('app.string.replace_button_text'),
            color: $r("app.color.button_bg_blue"),
          }
        ],
      }).then(result => {
        if (result.index === 1) {
          this.exportKdbxFile(storageConfig);
        }
      });
    } else {
      this.exportKdbxFile(storageConfig);
    }
  }

  private exportKdbxFile(storageConfig: StorageConfig) {
    if (!this.exportType) {
      return;
    }
    this.connectionStatus = ResourceManager.getString($r('app.string.save_saving'));
    KdbxExportService.createExportFile(this.exportType).then(result => {
      this.fileManager.init(storageConfig).writeFile(this.url, result.content).then(result => {
        this.promptAction.showToast({ message: ResourceManager.getString($r('app.string.save_success')) })
        this.connectionStatus = ResourceManager.getString($r('app.string.save_success'));
        this.isConnecting = false;
        this.router.back();
      });
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to export kdbx file: %{public}s', error.message);
      this.connectionStatus = error.message;
      this.isConnecting = false;
      this.isErrorStatus = true;
    })
  }

  /**
   * 校验参数合法性
   */
  private checkParam(): boolean {
    if (!this.url) {
      this.connectionStatus = ResourceManager.getString($r('app.string.url_placeholder'));
      this.isErrorStatus = true;
      return false;
    }
    if (!this.username) {
      this.connectionStatus = ResourceManager.getString($r('app.string.username_placeholder'));
      this.isErrorStatus = true;
      return false;
    }
    if (!this.password) {
      this.connectionStatus = ResourceManager.getString($r('app.string.password_placeholder'));
      this.isErrorStatus = true;
      return false;
    }
    return true;
  }

  /**
   * 初始化存储
   * @returns
   */
  private getStorageConfig(): StorageConfig {
    return new WebDAVStorageConfig(this.url, this.username, this.password);
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

        Text('WebDAV')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

      // 主要内容区域
      Scroll() {
        Column() {
          // 服务器URL输入
          Text($r('app.string.url'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextArea({ text: this.url, placeholder: $r('app.string.url_placeholder') })
            .lineHeight(24)
            .height(96)
            .type(TextAreaType.URL)
            .padding({ top: 12, bottom: 12 })
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .fontColor($r('app.color.text_primary'))
            .onChange((value: string) => {
              this.url = value;
            })

          // 用户名输入
          Text($r('app.string.username'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.username, placeholder: $r('app.string.username_placeholder') })
            .height(40)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.username = value;
            })

          // 密码输入
          Text($r('app.string.password'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.password, placeholder: $r('app.string.password_placeholder') })
            .height(40)
            .type(InputType.Password)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.password = value;
            })

          // 连接状态
          if (this.connectionStatus) {
            Text(this.connectionStatus)
              .fontSize(14)
              .margin({ top: 10 })
              .fontColor(this.isErrorStatus ? $r('app.color.danger') : $r('app.color.success'))
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
