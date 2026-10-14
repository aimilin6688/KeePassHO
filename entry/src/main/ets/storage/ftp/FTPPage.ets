import { FileType, StorageConfig, StorageType } from '..';
import { FTPStorageConfig, ProtocolType, SecureType } from './FTPConfig';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { CommonUtils, FilenameUtils, ResourceManager, Sm4Utils, StorageNavigation, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { RecentFilesService } from '../../services/RecentFilesService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';
import { FTPStorage } from './FTPStorage';

const DOMAIN = 0x0000;
const TAG = 'FTP';

// FTP配置页面的Builder函数（NavDestination）
@Builder
export function FTPPageBuilder(name: string, param: Object): void {
  NavDestination() {
    FTP({ reEditParam: param })
  }
  .title(StorageNavigation.getStorageTitle(StorageType.FTP))
  .backgroundColor($r('app.color.bg_primary'))
  .onShown(() => {
    // NavDestination 下 onPageShow 不回调，通过计数驱动页面显示处理
    AppStorage.set<number>('ftp_page_shown_tick', (AppStorage.get<number>('ftp_page_shown_tick') ?? 0) + 1);
  })
}

@Component
struct FTP {
  @State url: string = '/';
  @State host: string = '';
  @State port: string = '21';
  @State username: string = '';
  @State password: string = '';
  @State secure: SecureType = false;
  @State protocol: ProtocolType = ProtocolType.FTP;
  @State isLoading: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;
  @State secureSelectIndex: number = 0;
  @State secureSelectText: ResourceStr = $r('app.string.ftp_secure_type_none');
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.FTP);
  reEditParam: Object | undefined = undefined;
  private secureTypeOptions: Array<SecureTypeOptions> = [
    { value: $r('app.string.ftp_secure_type_none'), type: false },
    { value: $r('app.string.ftp_secure_type_explicit'), type: true },
    { value: $r('app.string.ftp_secure_type_implicit'), type: 'implicit' },
  ];

  aboutToAppear(): void {
    this.initSaveParam();
    this.initReEditPrefill();
  }

  // NavDestination 下 onPageShow 不回调，由 NavDestination.onShown 驱动页面显示处理
  @StorageProp('ftp_page_shown_tick') @Watch('onPageShownTickChange') pageShownTick: number = 0;

  onPageShownTickChange(): void {
    this.onPageShow();
  }

  onPageShow(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.connectionStatus = '';
  }

  // 导出数据初始化
  private initSaveParam() {
    if (!LocationParam.isSaveMode()) {
      return;
    }
    // 初始化导出
    const dbFileParam = FileService.getDbFileParam();
    if (!(dbFileParam.storageType === StorageType.FTP)) {
      this.url = LocationParam.getFileName();
      return;
    }
    const storageConfig = FTPStorage.parseConfig(dbFileParam.storageConfig as FTPStorageConfig);
    if (storageConfig) {
      this.prefillForm(storageConfig);
      this.url = FilenameUtils.replaceFileName(dbFileParam.filePath, LocationParam.getFileName());
    }
  }

  /**
   * 重新编辑连接配置（解密失败引导）预填：按传入的文件路径（URL）从最近记录解析原配置
   */
  private async initReEditPrefill(): Promise<void> {
    if (LocationParam.isSaveMode()) {
      return;
    }
    const reEditParam = this.reEditParam as Record<string, string>;
    const filePath: string = reEditParam?.filePath ?? '';
    if (!filePath) {
      return;
    }
    const recent = await RecentFilesService.getRecentFile(filePath);
    if (!recent || recent.storageType !== StorageType.FTP) {
      return;
    }
    this.prefillForm(FTPStorage.parseConfig(recent.storageConfig as FTPStorageConfig));
  }

  /**
   * 预填 FTP 连接配置表单：明文字段（host/port/secure/protocol）直接回填；
   * 凭证（用户名/密码）密文仅在可解密时回填，解密失败（密钥变更/密文损坏）留空由用户重新输入
   */
  private prefillForm(config: FTPStorageConfig): void {
    this.host = config.host || '';
    this.port = config.port?.toString() || '21';
    this.username = Sm4Utils.tryDecryptWithPrefix(config.username);
    this.password = Sm4Utils.tryDecryptWithPrefix(config.password);
    this.secure = config.secure ?? false;
    this.protocol = config.protocol || ProtocolType.FTP;
    this.syncSecureSelect();
  }

  /**
   * 同步安全连接下拉框选中态与 secure 值一致
   */
  private syncSecureSelect(): void {
    if (this.secure === true) {
      this.secureSelectIndex = 1;
      this.secureSelectText = $r('app.string.ftp_secure_type_explicit');
    } else if (this.secure === 'implicit') {
      this.secureSelectIndex = 2;
      this.secureSelectText = $r('app.string.ftp_secure_type_implicit');
    } else {
      this.secureSelectIndex = 0;
      this.secureSelectText = $r('app.string.ftp_secure_type_none');
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
    StorageNavigation.pushFileList(StorageType.FTP, this.url, this.getStorageConfig());
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
      this.fileManager.init(this.getStorageConfig())
        .exists(this.url)
        .then(result => {
          if (result !== undefined) {
            this.connectionStatus = ResourceManager.getString($r('app.string.connection_success'));
            this.isErrorStatus = false;
          } else {
            this.connectionStatus = ResourceManager.getString($r('app.string.connection_failed'));
            this.isErrorStatus = true;
            hilog.error(DOMAIN, TAG, 'FTP connection error: %{public}s', this.connectionStatus);
          }
        })
        .catch((error: Error) => {
          this.connectionStatus = error.message;
          this.isErrorStatus = true;
          hilog.error(DOMAIN, TAG, 'FTP connection error: %{public}s, stack: %{public}s', error.message, error.stack);
        })
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
      const fileInfo = await this.fileManager.init(storageConfig).getInfo(this.url);
      hilog.info(DOMAIN, TAG, `Loading file: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
      if (fileInfo.type === FileType.DIR) {
        this.toFileList();
      } else {
        // 回调位置信息
        LocationParam.callOnLocation({
          mode: LocationParam.getMode(),
          filePath: this.url,
          fileName: fileInfo.name,
          fileSuffix: LocationParam.getFileSuffix(),
          storageType: StorageType.FTP,
          storageConfig: storageConfig
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load KDBX file: %{public}s, %{public}s, stack:%{public}s', this.url, error.message, error.stack);
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
      const existsFile = await this.fileManager.exists(this.url);
      hilog.info(DOMAIN, TAG, `Export file to FTP path: ${this.url}`);
      if (existsFile) {
        // 获取文件类型
        this.connectionStatus = ResourceManager.getString($r('app.string.get_file_info'));
        const fileInfo = await this.fileManager.getInfo(this.url);
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
      hilog.error(DOMAIN, TAG, 'Failed to select file: %{public}s, %{public}s, stack:%{public}s', this.url, error.message, error.stack);
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
      CommonUtils.showToast({ message: error.message });
    } finally {
      this.isConnecting = false;
    }
  }

  // 保存文件（导出模式）
  private async handleSelectDir(storageConfig: StorageConfig) {
    try {
      this.connectionStatus = ResourceManager.getString($r('app.string.save_saving'));
      // 回调位置信息
      LocationParam.callOnLocation({
        mode: LocationParam.getMode(),
        filePath: this.url,
        fileName: FilenameUtils.getFileName(this.url),
        fileSuffix: LocationParam.getFileSuffix(),
        storageType: StorageType.FTP,
        storageConfig: storageConfig
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to export kdbx file: %{public}s', error.message);
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
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
        secure: this.secure,
        timeout: 30000,
        protocol: this.protocol
      }
    );
  }

  build() {
    Column() {
      // 主要内容区域（标题栏与返回键由 NavDestination 系统标题栏提供）
      Scroll() {
        Column() {
          // 协议选择
          Row() {
            Text($r('app.string.ftp_protocol'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Select([
              { value: ProtocolType.FTP.toString() },
              { value: ProtocolType.SFTP.toString() }
            ])
              .selected(this.protocol === ProtocolType.SFTP ? 1 : 0)
              .value(this.protocol.toString())
              .font({ size: 16, weight: FontWeight.Normal })
              .fontColor($r('app.color.text_primary'))
              .selectedOptionFont({ size: 16, weight: FontWeight.Medium })
              .optionFont({ size: 16, weight: FontWeight.Normal })
              .onSelect((index: number, value?: string) => {
                if (value === ProtocolType.SFTP.toString()) {
                  this.onProtocolChange(ProtocolType.SFTP);
                } else {
                  this.onProtocolChange(ProtocolType.FTP);
                }
              })
              .width('60%')
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          Row() {
            Text("*").fontColor($r('app.color.required'))
            // 服务器地址输入
            Text($r('app.string.ftp_host'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Start)
            Blank()
            TextInput({ text: this.host, placeholder: ResourceManager.getString($r('app.string.ftp_host_placeholder')) })
              .height(40)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r("app.color.card_bg"))
              .onChange((value: string) => {
                this.host = value;
              })
              .width('60%')
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          Row() {
            Text("*").fontColor($r('app.color.required'))
            // 端口输入
            Text($r('app.string.ftp_port'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Start)
            Blank()
            TextInput({ text: this.port })
              .height(40)
              .type(InputType.Number)
              .width('60%')
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r("app.color.card_bg"))
              .onChange((value: string) => {
                this.port = value;
              })
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)


          // 用户名输入
          Row() {
            Text("*").fontColor($r('app.color.required'))
            Text($r('app.string.username'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Start)
            Blank()
            TextInput({ text: this.username, placeholder: ResourceManager.getString($r('app.string.username_placeholder')) })
              .height(40)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r("app.color.card_bg"))
              .width('60%')
              .onChange((value: string) => {
                this.username = value;
              })
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          // 密码输入
          Row() {
            Text("*").fontColor($r('app.color.required'))
            Text($r('app.string.password'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Start)
            Blank()
            TextInput({ text: this.password, placeholder: ResourceManager.getString($r('app.string.password_placeholder')) })
              .height(40)
              .type(InputType.Password)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r("app.color.card_bg"))
              .width('60%')
              .onChange((value: string) => {
                this.password = value;
              })
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          // 根路径输入
          Row() {
            Text($r('app.string.ftp_root_path'))
              .height(40)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Start)
            Blank()
            TextArea({ text: this.url })
              .minLines(1)
              .maxLines(3)
              .padding({ top: 12, bottom: 12 })
              .width('60%')
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r("app.color.card_bg"))
              .onChange((value: string) => {
                this.url = value || '/';
              })
          }
          .width('100%')
          .height('auto')
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          // 安全连接（仅FTP可用）
          if (this.protocol === ProtocolType.FTP) {
            Row() {
              Text($r('app.string.ftp_secure'))
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Blank()
              Select(this.secureTypeOptions)
                .value(this.secureSelectText)
                .selected(this.secureSelectIndex)
                .font({ size: 16 })
                .selectedOptionFont({ size: 16 })
                .optionFont({ size: 16 })
                .backgroundColor($r("app.color.card_bg"))
                .onSelect(async (index: number) => {
                  const secureType = this.secureTypeOptions[index];
                  this.secure = secureType.type;
                  this.secureSelectIndex = index;
                  this.secureSelectText = secureType.value;
                })
                .width('60%')
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
        .width('100%')
        .padding({ left: 16, right: 16 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('auto')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

export interface SecureTypeOptions {
  value: ResourceStr;
  type: SecureType;
}