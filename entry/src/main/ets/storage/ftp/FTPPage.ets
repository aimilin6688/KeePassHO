import { Router } from '@kit.ArkUI';
import { FileType, StorageConfig, StorageType } from '..';
import { FTPStorageConfig, ProtocolType } from './FTPConfig';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { CommonUtils, ResourceManager, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'FTP';

@Entry
@Component
struct FTP {
  @State host: string = '111.230.44.135';
  @State port: string = '22';
  @State username: string = 'root';
  @State password: string = 'zfkm,2017';
  @State rootPath: string = '/';
  @State secure: boolean = false;
  @State protocol: ProtocolType = ProtocolType.FTP;
  @State isLoading: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.FTP);
  private router: Router = this.getUIContext().getRouter();

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
        const protocol = fileName.substring(0, protocolEnd).toLowerCase();
        const rest = fileName.substring(protocolEnd + 3);
        const slashPos = rest.indexOf('/');
        const colonPos = rest.indexOf(':');

        // 根据协议设置类型和默认端口
        if (protocol === 'sftp') {
          this.protocol = ProtocolType.SFTP;
          this.port = '22';
        } else {
          this.protocol = ProtocolType.FTP;
          this.port = '21';
        }

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
      this.protocol = storageConfig.protocol || ProtocolType.FTP;
    }
  }

  // 协议切换时的处理
  private onProtocolChange(value: ProtocolType) {
    this.protocol = value;
    // 根据协议设置默认端口
    if (value === ProtocolType.SFTP) {
      this.port = '22';
    } else {
      this.port = '21';
    }
  }

  // 处理确认事件
  private handleConfirm() {
    // 导出数据库
    if (LocationParam.isSaveMode()) {
      this.selectDir();
    } else {
      this.selectFile();
    }
  }

  // 跳转到文件预览页面
  private toFileList() {
    if (!this.checkParam()) {
      return;
    }
    this.router.pushUrl(
      {
        url: 'pages/open/FileList',
        params: {
          mode: LocationParam.getMode(),
          filePath: this.rootPath,
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
      // 简单测试连接
      this.fileManager.init(this.getStorageConfig());
      const testPath = this.rootPath;
      const result = await this.fileManager.exists(testPath);
      if (result !== undefined) {
        this.connectionStatus = ResourceManager.getString($r('app.string.connection_success'));
        this.isErrorStatus = false;
      } else {
        this.connectionStatus = ResourceManager.getString($r('app.string.connection_failed'));
        this.isErrorStatus = true;
        hilog.error(DOMAIN, TAG, 'FTP connection error: %{public}s', this.connectionStatus);
      }
    } catch (error) {
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, 'FTP connection error: %{public}s', this.connectionStatus);
    } finally {
      this.isConnecting = false;
    }
  }

  // 选择文件（导入模式）
  private async selectFile() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;
    try {
      const storageConfig = this.getStorageConfig();
      // 获取文件信息
      const fileInfo = await this.fileManager.init(storageConfig).getInfo(this.rootPath);
      hilog.info(DOMAIN, TAG, `Loading KDBX file: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
      if (fileInfo.type === FileType.DIR) {
        this.toFileList();
      } else {
        // 回调位置信息
        LocationParam.callOnLocation({
          mode: LocationParam.getMode(),
          filePath: this.rootPath,
          fileName: fileInfo.name,
          fileSuffix: LocationParam.getFileSuffix(),
          storageType: StorageType.FTP,
          storageConfig: storageConfig
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load KDBX file: %{public}s, %{public}s, stack:%{public}s', this.rootPath, error.message, error.stack);
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
      CommonUtils.showToast({ message: error.message });
    } finally {
      this.isConnecting = false;
    }
  }

  /**
   * 导出数据库
   */
  private async selectDir() {
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
      const path = this.rootPath + LocationParam.getFileName();
      const existsFile = await this.fileManager.exists(path);
      hilog.info(DOMAIN, TAG, `Export file to FTP path: ${path}`);
      if (existsFile) {
        // 获取文件类型
        this.connectionStatus = ResourceManager.getString($r('app.string.get_file_info'));
        const fileInfo = await this.fileManager.getInfo(path);
        hilog.info(DOMAIN, TAG, `Loading file info: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
        // 如果是文件夹，则跳转到文件列表页面
        if (fileInfo.type === FileType.DIR) {
          this.toFileList();
        } else {
          this.handleSelectDir(storageConfig, path);
        }
      } else {
        this.handleSelectDir(storageConfig, path);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to select file: %{public}s, %{public}s, stack:%{public}s', this.rootPath, error.message, error.stack);
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
      CommonUtils.showToast({ message: error.message });
    } finally {
      this.isConnecting = false;
    }
  }

  // 保存文件（导出模式）
  private async handleSelectDir(storageConfig: StorageConfig, filePath: string) {
    try {
      this.connectionStatus = ResourceManager.getString($r('app.string.save_saving'));
      const database = FileService.getDatabase();
      const buffer = await database.save();
      await this.fileManager.init(storageConfig).write(filePath, buffer);
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.save_success')) });
      this.router.back();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to export kdbx file: %{public}s', error.message);
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
      CommonUtils.showToast({ message: error.message });
    } finally {
      this.isConnecting = false;
    }
  }

  // 参数校验
  private checkParam(): boolean {
    if (!this.host) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.ftp_host_empty')) });
      return false;
    }
    if (!this.username) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.ftp_username_empty')) });
      return false;
    }
    if (!this.password) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.ftp_password_empty')) });
      return false;
    }
    const portNum = parseInt(this.port);
    if (isNaN(portNum) || portNum <= 0 || portNum > 65535) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.ftp_port_invalid')) });
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
        timeout: 30000,
        protocol: this.protocol
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
            this.router.back();
          })

        Text($r('app.string.ftp_button_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)

      // 主要内容区域
      Scroll() {
        Column() {
          // 协议选择
          Text('协议')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          Row() {
            Button('FTP')
              .height(40)
              .layoutWeight(1)
              .margin({ right: 8 })
              .backgroundColor(this.protocol === ProtocolType.FTP ? $r('app.color.button_bg_blue') : Color.Gray)
              .fontColor(Color.White)
              .onClick(() => {
                this.onProtocolChange(ProtocolType.FTP);
              })
            Button('SFTP')
              .height(40)
              .layoutWeight(1)
              .margin({ left: 8 })
              .backgroundColor(this.protocol === ProtocolType.SFTP ? $r('app.color.button_bg_blue') : Color.Gray)
              .fontColor(Color.White)
              .onClick(() => {
                this.onProtocolChange(ProtocolType.SFTP);
              })
          }
          .width('100%')
          .margin({ top: 20 })

          // 服务器地址输入
          Text($r('app.string.ftp_host'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.host, placeholder: ResourceManager.getString($r('app.string.ftp_host_placeholder')) })
            .height(40)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.host = value;
            })

          // 端口输入
          Text($r('app.string.ftp_port'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.port })
            .height(40)
            .margin({ top: 20 })
            .type(InputType.Number)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.port = value;
            })

          // 用户名输入
          Text($r('app.string.username'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.username, placeholder: ResourceManager.getString($r('app.string.username_placeholder')) })
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
          TextInput({ text: this.password, placeholder: ResourceManager.getString($r('app.string.password_placeholder')) })
            .height(40)
            .margin({ top: 20 })
            .type(InputType.Password)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.password = value;
            })

          // 根路径输入
          Text($r('app.string.ftp_root_path'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text: this.rootPath })
            .height(40)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.rootPath = value || '/';
            })

          // 安全连接（仅FTP可用）
          if (this.protocol === ProtocolType.FTP) {
            Row() {
              Text($r('app.string.ftp_secure'))
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.secure })
                .onChange((isOn: boolean) => {
                  this.secure = isOn;
                })
            }
            .width('100%')
            .height(40)
            .margin({ top: 20 })
            .alignItems(VerticalAlign.Center)
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