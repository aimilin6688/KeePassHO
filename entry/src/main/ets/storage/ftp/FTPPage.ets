import { PromptAction, Router } from '@kit.ArkUI';
import { FileType, StorageConfig, StorageType } from '..';
import { FTPStorageConfig } from './FTPConfig';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { ResourceManager, FilenameUtils, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'FTP';

@Entry
@Component
struct FTP {
  @State host: string = '';
  @State port: string = '21';
  @State username: string = '';
  @State password: string = '';
  @State rootPath: string = '/';
  @State secure: boolean = false;
  @State isLoading: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.FTP);
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  aboutToAppear(): void {
    this.initSaveParam();
  }

  onPageAppear(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  // 导出数据初始化
  private initSaveParam() {
    if (!LocationParam.isSaveMode()) {
      return;
    }
    // 初始化导出
    const dbFileParam = FileService.getDbFileParam();
    if (!(dbFileParam.storageType === StorageType.FTP)) {
      const fileName = LocationParam.getFileName();
      // 尝试从文件名中提取主机信息
      if (fileName.includes('://')) {
        const protocolEnd = fileName.indexOf('://');
        const rest = fileName.substring(protocolEnd + 3);
        const slashPos = rest.indexOf('/');
        const colonPos = rest.indexOf(':');
        
        if (colonPos > 0) {
          this.host = rest.substring(0, colonPos);
          if (slashPos > colonPos) {
            this.port = rest.substring(colonPos + 1, slashPos);
            this.rootPath = rest.substring(slashPos) || '/';
          } else {
            this.port = rest.substring(colonPos + 1);
            this.rootPath = '/';
          }
        } else if (slashPos > 0) {
          this.host = rest.substring(0, slashPos);
          this.rootPath = rest.substring(slashPos) || '/';
        } else {
          this.host = rest;
          this.rootPath = '/';
        }
      }
      return;
    }
    const storageConfig = dbFileParam.storageConfig as FTPStorageConfig;
    if (storageConfig) {
      this.host = storageConfig.host;
      this.port = storageConfig.port.toString();
      this.username = storageConfig.getUserNameText();
      this.password = storageConfig.getPasswordText();
      this.rootPath = storageConfig.rootPath || '/';
      this.secure = storageConfig.secure === true;
    }
  }

  // 处理确认事件
  private handleConfirm() {
    // 导出数据库
    if (LocationParam.isSaveMode()) {
      this.saveFile();
    } else {
      this.toFileList();
    }
  }

  // 跳转到文件预览页面
  private toFileList() {
    if (!this.checkParam()) {
      return;
    }
    const path = this.rootPath + LocationParam.getFileName();
    this.router.pushUrl({
      url: 'pages/open/FileList',
      params: {
        mode: LocationParam.getMode(),
        filePath: path,
        fileSuffix: LocationParam.getFileSuffix(),
        fileName: LocationParam.getFileName(),
        storageType: StorageType.FTP,
        storageConfig: this.getStorageConfig()
      }
    });
  }

  // 测试FTP连接
  private async testConnection() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      // 测试连接
      this.fileManager.init(this.getStorageConfig());
      const testPath = this.rootPath;
      const result = await this.fileManager.exists(testPath);
      if (result !== undefined) {
        this.connectionStatus = ResourceManager.getString($r('app.string.connection_success'));
        this.isErrorStatus = false;
      } else {
        this.connectionStatus = ResourceManager.getString($r('app.string.connection_failed'));
        this.isErrorStatus = true;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'FTP connection test failed: ' + error.message);
      this.connectionStatus = ResourceManager.getString($r('app.string.connection_failed')) + ': ' + error.message;
      this.isErrorStatus = true;
    } finally {
      this.isConnecting = false;
    }
  }

  // 选择文件（导入模式）
  private selectFile() {
    this.toFileList();
  }

  // 保存文件（导出模式）
  private async saveFile() {
    if (!this.checkParam()) {
      return;
    }
    this.isLoading = true;
    try {
      const filePath = this.rootPath + LocationParam.getFileName();
      const database = FileService.getDatabase();
      const buffer = await database.save();
      await this.fileManager.init(this.getStorageConfig()).write(filePath, buffer);
      this.promptAction.showToast({ message: ResourceManager.getString($r('app.string.save_success')) });
      this.router.back();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Save file error: ' + error.message);
      this.promptAction.showToast({ message: error.message });
    } finally {
      this.isLoading = false;
    }
  }

  // 参数校验
  private checkParam(): boolean {
    if (!this.host) {
      this.promptAction.showToast({ message: ResourceManager.getString($r('app.string.ftp_host_empty')) });
      return false;
    }
    if (!this.username) {
      this.promptAction.showToast({ message: ResourceManager.getString($r('app.string.ftp_username_empty')) });
      return false;
    }
    if (!this.password) {
      this.promptAction.showToast({ message: ResourceManager.getString($r('app.string.ftp_password_empty')) });
      return false;
    }
    const portNum = parseInt(this.port);
    if (isNaN(portNum) || portNum <= 0 || portNum > 65535) {
      this.promptAction.showToast({ message: ResourceManager.getString($r('app.string.ftp_port_invalid')) });
      return false;
    }
    return true;
  }

  // 获取存储配置
  private getStorageConfig(): FTPStorageConfig {
    const portNum = parseInt(this.port);
    return new FTPStorageConfig(
      this.host,
      this.username,
      this.password,
      {
        port: portNum,
        rootPath: this.rootPath || '/',
        secure: this.secure,
        timeout: 30000
      }
    );
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back();
          })

        Text($r('app.string.ftp_button_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ right: 40 })
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column() {
          // 服务器地址
          Column() {
            Text(ResourceManager.getString($r('app.string.ftp_host')))
              .fontSize(14)
              .fontColor('#666666')
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            TextInput({ placeholder: ResourceManager.getString($r('app.string.ftp_host_placeholder')) })
              .width('100%')
              .height(44)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .fontSize(14)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.host = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 16 })

          // 端口
          Column() {
            Text(ResourceManager.getString($r('app.string.ftp_port')))
              .fontSize(14)
              .fontColor('#666666')
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            TextInput({ text: this.port })
              .width('100%')
              .height(44)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .fontSize(14)
              .padding({ left: 12, right: 12 })
              .type(InputType.Number)
              .onChange((value: string) => {
                this.port = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 16 })

          // 用户名
          Column() {
            Text(ResourceManager.getString($r('app.string.username')))
              .fontSize(14)
              .fontColor('#666666')
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            TextInput({ placeholder: ResourceManager.getString($r('app.string.username_placeholder')) })
              .width('100%')
              .height(44)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .fontSize(14)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.username = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 16 })

          // 密码
          Column() {
            Text(ResourceManager.getString($r('app.string.password')))
              .fontSize(14)
              .fontColor('#666666')
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            TextInput({ placeholder: ResourceManager.getString($r('app.string.password_placeholder')) })
              .width('100%')
              .height(44)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .fontSize(14)
              .padding({ left: 12, right: 12 })
              .type(InputType.Password)
              .onChange((value: string) => {
                this.password = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 16 })

          // 根路径
          Column() {
            Text(ResourceManager.getString($r('app.string.ftp_root_path')))
              .fontSize(14)
              .fontColor('#666666')
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            TextInput({ text: this.rootPath })
              .width('100%')
              .height(44)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .fontSize(14)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.rootPath = value || '/';
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 16 })

          // 安全连接
          Row() {
            Text(ResourceManager.getString($r('app.string.ftp_secure')))
              .fontSize(14)
              .fontColor('#333333')
              .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.secure })
              .onChange((isOn: boolean) => {
                this.secure = isOn;
              })
          }
          .width('100%')
          .height(44)
          .padding({ left: 12, right: 12 })
          .alignItems(VerticalAlign.Center)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .margin({ bottom: 16 })

          // 连接测试按钮
          Button(this.isConnecting ? 
            ResourceManager.getString($r('app.string.testing')) : 
            ResourceManager.getString($r('app.string.test_connection')))
            .width('100%')
            .height(44)
            .fontSize(16)
            .backgroundColor('#007AFF')
            .enabled(!this.isConnecting)
            .onClick(() => {
              this.testConnection();
            })
            .margin({ bottom: 16 })

          // 连接状态
          if (this.connectionStatus) {
            Text(this.connectionStatus)
              .fontSize(14)
              .fontColor(this.isErrorStatus ? '#FF3B30' : '#34C759')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 16 })
          }
        }
        .padding(16)
      }
      .layoutWeight(1)

      // 底部确认按钮
      Column() {
        Button(LocationParam.isSaveMode() ? 
          $r('app.string.save_button_text') : 
          $r('app.string.confirm_button_text'))
          .width('100%')
          .height(50)
          .fontSize(16)
          .backgroundColor(this.isLoading ? '#CCCCCC' : '#007AFF')
          .enabled(!this.isLoading)
          .onClick(() => {
            this.handleConfirm();
          })
          .margin({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}