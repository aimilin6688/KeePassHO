import { PromptAction, Router } from '@kit.ArkUI';
import { FileType, StorageConfig, StorageType } from '..';
import { WebDAVStorageConfig } from './WebDAVConfig';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { CommonUtils, FilenameUtils, ResourceManager, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';
import { picker, fs } from '@kit.CoreFileKit';
import { CertValidationMode } from './WebDAVConfig';
import { util } from '@kit.ArkTS';
import { AlertDialog, DialogAlignment } from '@kit.ArkUI';

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
  @State certValidationMode: CertValidationMode = CertValidationMode.SYSTEM;
  @State customCaCertPath: string = '';
  @State customCaCertContent: string = '';
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.WEBDAV);
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  aboutToAppear(): void {
    this.initSaveParam();
  }

  onPageShow(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  // 导出数据初始化
  private initSaveParam() {
    if (!LocationParam.isSaveMode()) {
      return;
    }
    // 初始化导出
    const dbFileParam = FileService.getDbFileParam();
    if (!(dbFileParam.storageType === StorageType.WEBDAV)) {
      this.url = LocationParam.getFileName();
      return;
    }
    let storageConfig = dbFileParam.storageConfig as WebDAVStorageConfig;
    if (storageConfig) {
      storageConfig = new WebDAVStorageConfig(storageConfig.url, storageConfig.username, storageConfig.password, {
        rootPath: storageConfig.rootPath,
        timeout: storageConfig.timeout,
        certValidationMode: storageConfig.certValidationMode,
        customCaCertContent: storageConfig.customCaCertContent
      });
      this.url = FilenameUtils.replaceFileName(dbFileParam.filePath, LocationParam.getFileName());
      this.username = storageConfig.getUserNameText();
      this.password = storageConfig.getPasswordText();
      // 恢复证书配置
      this.certValidationMode = storageConfig.certValidationMode || CertValidationMode.SYSTEM;
      this.customCaCertContent = storageConfig.customCaCertContent || '';
      this.customCaCertPath = this.customCaCertContent ?
        ResourceManager.getString($r('app.string.ssl_cert_certificate_selected')) : '';
    }
  }

  // 处理确认时间
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
    CommonUtils.pushUrl({
      url: 'pages/open/FileList',
      params: {
        mode: LocationParam.getMode(),
        filePath: this.url,
        fileSuffix: LocationParam.getFileSuffix(),
        fileName: LocationParam.getFileName(),
        storageType: StorageType.WEBDAV,
        storageConfig: this.getStorageConfig()
      }
    });
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
      hilog.info(DOMAIN, TAG, `Loading KDBX file: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
      if (fileInfo.type === FileType.DIR) {
        this.toFileList();
      } else {
        // 回调位置信息
        LocationParam.callOnLocation({
          mode: LocationParam.getMode(),
          filePath: this.url,
          fileName: fileInfo.name,
          fileSuffix: LocationParam.getFileSuffix(),
          storageType: StorageType.WEBDAV,
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
      hilog.info(DOMAIN, TAG, `Export file to webDAV path: ${this.url}`);
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

  private handleSelectDir(storageConfig: StorageConfig) {
    try {
      this.connectionStatus = ResourceManager.getString($r('app.string.save_saving'));
      // 回调位置信息
      LocationParam.callOnLocation({
        mode: LocationParam.getMode(),
        filePath: this.url,
        fileName: FilenameUtils.getFileName(this.url),
        fileSuffix: LocationParam.getFileSuffix(),
        storageType: StorageType.WEBDAV,
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

  /**
   * 校验参数合法性
   */
  private checkParam(): boolean {
    if (!this.url) {
      this.connectionStatus = ResourceManager.getString($r("app.string.webdav_url_placeholder"));
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
   * 选择 CA 证书文件
   */
  private async selectCaCert() {
    let documentPicker = new picker.DocumentViewPicker();
    try {
      const result = await documentPicker.select({
        maxSelectNumber: 1
      });
      if (result && result.length > 0) {
        const uri = result[0];
        // 读取证书内容
        const content = await this.readCertContent(uri);
        this.customCaCertContent = content;
        this.customCaCertPath = ResourceManager.getString($r('app.string.ssl_cert_certificate_selected'));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Select CA cert error: %{public}s', error.message);
      CommonUtils.showToast({ message: $r('app.string.ssl_cert_select_failed') });
    }
  }

  /**
   * 读取证书文件内容
   */
  private async readCertContent(uri: string): Promise<string> {
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      // 将 ArrayBuffer 转换为字符串
      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Read cert content error: %{public}s', error.message);
      return '';
    }
  }

  /**
   * 处理证书验证模式变更
   */
  private onCertValidationModeChange(mode: CertValidationMode) {
    if (mode === CertValidationMode.SKIP) {
      // 显示风险提示
      AlertDialog.show({
        title: $r('app.string.ssl_cert_warning_title'),
        message: $r('app.string.ssl_cert_warning_message'),
        autoCancel: true,
        alignment: DialogAlignment.CENTER,
        buttons: [
          {
            value: $r('app.string.cancel_button_text'),
            action: () => {
              // 取消，恢复到系统 CA 模式
              this.certValidationMode = CertValidationMode.SYSTEM;
            }
          },
          {
            value: $r('app.string.ssl_cert_warning_continue'),
            action: () => {
              // 确认，保持跳过验证模式
              this.certValidationMode = CertValidationMode.SKIP;
            }
          }
        ]
      });
    } else {
      this.certValidationMode = mode;
    }
  }

  /**
   * 初始化存储
   * @returns
   */
  private getStorageConfig(): StorageConfig {
    return new WebDAVStorageConfig(this.url, this.username, this.password, {
      certValidationMode: this.certValidationMode,
      customCaCertContent: this.customCaCertContent
    });
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
          TextArea({ text: this.url, placeholder: $r("app.string.webdav_url_placeholder") })
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

          // SSL 证书验证
          Text($r('app.string.ssl_cert_validation_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)

          Column() {
            Row() {
              Radio({ value: CertValidationMode.SYSTEM, group: 'certValidation' })
                .checked(this.certValidationMode === CertValidationMode.SYSTEM)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.certValidationMode = CertValidationMode.SYSTEM;
                  }
                })
              Text($r('app.string.ssl_cert_validation_system'))
                .fontSize(14)
                .margin({ left: 8 })
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.certValidationMode = CertValidationMode.SYSTEM;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })

            Row() {
              Radio({ value: CertValidationMode.SKIP, group: 'certValidation' })
                .checked(this.certValidationMode === CertValidationMode.SKIP)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.onCertValidationModeChange(CertValidationMode.SKIP);
                  }
                })
              Text($r('app.string.ssl_cert_validation_skip'))
                .fontSize(14)
                .margin({ left: 8 })
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.onCertValidationModeChange(CertValidationMode.SKIP);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })

            Row() {
              Radio({ value: CertValidationMode.CUSTOM_CA, group: 'certValidation' })
                .checked(this.certValidationMode === CertValidationMode.CUSTOM_CA)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.certValidationMode = CertValidationMode.CUSTOM_CA;
                  }
                })
              Text($r('app.string.ssl_cert_validation_custom_ca'))
                .fontSize(14)
                .margin({ left: 8 })
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.certValidationMode = CertValidationMode.CUSTOM_CA;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })

            // 自定义 CA 证书选择（仅当选择自定义 CA 模式时显示）
            if (this.certValidationMode === CertValidationMode.CUSTOM_CA) {
              Row() {
                Text(this.customCaCertPath || $r('app.string.ssl_cert_no_certificate_selected'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)

                Button($r('app.string.select_button'))
                  .height(32)
                  .fontSize(14)
                  .backgroundColor($r('app.color.button_bg_blue'))
                  .fontColor($r('app.color.button_text_blue'))
                  .onClick(() => {
                    this.selectCaCert();
                  })
              }
              .width('100%')
              .padding({ left: 32, right: 16, top: 4, bottom: 8 })
            }
          }
          .width('100%')
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(8)
          .margin({ top: 8, left: 16, right: 16 })

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
