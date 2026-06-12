import { Router } from '@kit.ArkUI';
import { StorageConfig, StorageType, FileType } from '..';
import { S3StorageConfig } from './S3Config';
import { S3Storage } from './S3Storage';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { CommonUtils, FilenameUtils, ResourceManager, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'S3Page';

@Entry
@Component
struct S3Page {
  @State endpoint: string = '';
  @State accessKeyId: string = '';
  @State secretAccessKey: string = '';
  @State region: string = '';
  @State bucket: string = '';
  @State pathStyle: boolean = false;
  @State timeout: string = '30000';
  @State filePath: string = '';
  @State showAdvanced: boolean = false;
  @State isLoading: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;

  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.S3);
  private router: Router = this.getUIContext().getRouter();

  aboutToAppear(): void {
    this.initSaveParam();
  }

  onPageShow(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.connectionStatus = '';
  }

  private initSaveParam() {
    if (!LocationParam.isSaveMode()) {
      return;
    }
    const dbFileParam = FileService.getDbFileParam();
    if (!(dbFileParam.storageType === StorageType.S3)) {
      this.filePath = LocationParam.getFileName();
      return;
    }
    const storageConfig = dbFileParam.storageConfig as S3StorageConfig;
    if (storageConfig) {
      this.endpoint = storageConfig.endpoint;
      this.accessKeyId = storageConfig.getAccessKeyIdText();
      this.secretAccessKey = storageConfig.getSecretAccessKeyText();
      this.region = storageConfig.region || 'us-east-1';
      this.bucket = storageConfig.bucket || '';
      this.pathStyle = storageConfig.pathStyle;
      this.timeout = storageConfig.timeout?.toString() || '30000';
      this.filePath = FilenameUtils.replaceFileName(dbFileParam.filePath, LocationParam.getFileName());
    }
  }

  private checkParam(): boolean {
    if (!this.endpoint) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.s3_endpoint_empty')) });
      return false;
    }
    if (!this.accessKeyId) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.s3_access_key_empty')) });
      return false;
    }
    if (!this.secretAccessKey) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.s3_secret_key_empty')) });
      return false;
    }
    return true;
  }

  private getStorageConfig(): S3StorageConfig {
    return new S3StorageConfig(
      this.endpoint,
      this.accessKeyId,
      this.secretAccessKey,
      {
        region: this.region,
        bucket: this.bucket || undefined,
        pathStyle: this.pathStyle,
        timeout: parseInt(this.timeout, 10) || 30000
      }
    );
  }

  private async testConnection() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      const storageConfig = this.getStorageConfig();
      const storage = new S3Storage(storageConfig);
      const exists = await storage.exists('/');
      this.connectionStatus = ResourceManager.getString($r('app.string.connection_success'));
      this.isErrorStatus = false;
    } catch (error) {
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, 'S3 connection error: %{public}s', this.connectionStatus);
    } finally {
      this.isConnecting = false;
    }
  }

  private handleConfirm() {
    if (LocationParam.isSaveMode()) {
      this.selectDir();
    } else {
      this.selectFile();
    }
  }

  private toFileList() {
    if (!this.checkParam()) {
      return;
    }
    CommonUtils.pushUrl({
      url: 'pages/open/FileList',
      params: {
        mode: LocationParam.getMode(),
        filePath: this.filePath,
        fileSuffix: LocationParam.getFileSuffix(),
        fileName: LocationParam.getFileName(),
        storageType: StorageType.S3,
        storageConfig: this.getStorageConfig()
      }
    });
  }

  private async selectFile() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      const storageConfig = this.getStorageConfig();
      const fileInfo = await this.fileManager.init(storageConfig).getInfo(this.filePath);

      if (fileInfo.type === FileType.DIR) {
        this.toFileList();
      } else {
        LocationParam.callOnLocation({
          mode: LocationParam.getMode(),
          filePath: this.filePath,
          fileName: fileInfo.name,
          fileSuffix: LocationParam.getFileSuffix(),
          storageType: StorageType.S3,
          storageConfig: storageConfig
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load file: %{public}s', error.message);
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
      CommonUtils.showToast({ message: error.message });
    } finally {
      this.isConnecting = false;
    }
  }

  private async selectDir() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      const storageConfig = this.getStorageConfig();
      this.fileManager.init(storageConfig);
      const existsFile = await this.fileManager.exists(this.filePath);

      if (existsFile) {
        const fileInfo = await this.fileManager.getInfo(this.filePath);
        if (fileInfo.type === FileType.DIR) {
          this.toFileList();
          return;
        }
      }

      LocationParam.callOnLocation({
        mode: LocationParam.getMode(),
        filePath: this.filePath,
        fileName: FilenameUtils.getFileName(this.filePath),
        fileSuffix: LocationParam.getFileSuffix(),
        storageType: StorageType.S3,
        storageConfig: storageConfig
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to export file: %{public}s', error.message);
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
    } finally {
      this.isConnecting = false;
    }
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_angle_left'))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back();
          })

        Text($r('app.string.s3_button_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)

      Scroll() {
        Column() {
          Row() {
            Text('*').fontColor($r('app.color.required'))
            Text($r('app.string.s3_endpoint'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            TextArea({ text: this.endpoint, placeholder: 'https://s3.amazonaws.com' })
              .minLines(1)
              .maxLines(3)
              .padding({ top: 10, bottom: 10 })
              .width('60%')
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.card_bg'))
              .onChange((value: string) => {
                this.endpoint = value;
              })
          }
          .width('100%')
          .height('auto')
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          Text($r('app.string.s3_endpoint_hint'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ top: 4 })

          Row() {
            Text('*').fontColor($r('app.color.required'))
            Text($r('app.string.s3_access_key_id'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            TextInput({ text: this.accessKeyId })
              .height(40)
              .width('60%')
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.card_bg'))
              .onChange((value: string) => {
                this.accessKeyId = value;
              })
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          Row() {
            Text('*').fontColor($r('app.color.required'))
            Text($r('app.string.s3_secret_access_key'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            TextInput({ text: this.secretAccessKey })
              .height(40)
              .width('60%')
              .type(InputType.Password)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.card_bg'))
              .onChange((value: string) => {
                this.secretAccessKey = value;
              })
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          Row() {
            Text($r('app.string.s3_file_path'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            TextArea({ text: this.filePath })
              .minLines(1)
              .maxLines(3)
              .padding({ top: 12, bottom: 12 })
              .width('60%')
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.card_bg'))
              .onChange((value: string) => {
                this.filePath = value;
              })
          }
          .width('100%')
          .height('auto')
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          Row() {
            Text($r('app.string.s3_advanced_settings'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.showAdvanced })
              .onChange((isOn: boolean) => {
                this.showAdvanced = isOn;
              })
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          if (this.showAdvanced) {
            Column() {
              Row() {
                Text($r('app.string.s3_region'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                TextInput({ text: this.region })
                  .height(36)
                  .width('60%')
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_primary'))
                  .borderRadius(6)
                  .onChange((value: string) => {
                    this.region = value;
                  })
              }
              .width('100%')
              .height(36)
              .margin({ top: 12 })
              .alignItems(VerticalAlign.Center)

              Row() {
                Text($r('app.string.s3_default_bucket'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                TextInput({ text: this.bucket })
                  .height(36)
                  .width('60%')
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_primary'))
                  .borderRadius(6)
                  .onChange((value: string) => {
                    this.bucket = value;
                  })
              }
              .width('100%')
              .height(36)
              .margin({ top: 12 })
              .alignItems(VerticalAlign.Center)

              Row() {
                Text($r('app.string.s3_url_style'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Row() {
                  Radio({ value: 'virtual', group: 'urlStyle' })
                    .checked(!this.pathStyle)
                    .onChange((isChecked: boolean) => {
                      if (isChecked) this.pathStyle = false;
                    })
                  Text($r('app.string.s3_virtual_host_style'))
                    .fontSize(12)
                    .margin({ right: 16 })
                    .onClick(() => {
                      this.pathStyle = false;
                    })

                  Radio({ value: 'path', group: 'urlStyle' })
                    .checked(this.pathStyle)
                    .onChange((isChecked: boolean) => {
                      if (isChecked) this.pathStyle = true;
                    })
                  Text($r('app.string.s3_path_style_url'))
                    .fontSize(12)
                    .onClick(() => {
                      this.pathStyle = true;
                    })
                }
              }
              .width('100%')
              .height(36)
              .margin({ top: 12 })
              .alignItems(VerticalAlign.Center)

              Row() {
                Text($r('app.string.s3_timeout'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                TextInput({ text: this.timeout })
                  .height(36)
                  .width('60%')
                  .type(InputType.Number)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_primary'))
                  .borderRadius(6)
                  .onChange((value: string) => {
                    this.timeout = value;
                  })
              }
              .width('100%')
              .height(36)
              .margin({ top: 12 })
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(8)
            .margin({ top: 8 })
          }

          if (this.connectionStatus) {
            Text(this.connectionStatus)
              .fontSize(14)
              .margin({ top: 10 })
              .fontColor(this.isErrorStatus ? $r('app.color.error') : $r('app.color.success'))
          }

          if (this.isConnecting) {
            Row() {
              LoadingProgress()
                .width(50)
                .height(50)
                .color($r('app.color.text_primary'))
              Text($r('app.string.connecting'))
                .fontSize(16)
                .margin({ left: 16 })
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ top: 20 })
          }

          Row() {
            Button($r('app.string.test_connection'))
              .height(40)
              .backgroundColor(Color.Gray)
              .fontColor(Color.White)
              .enabled(!this.isConnecting)
              .onClick(() => {
                this.testConnection();
              })
            Blank()
            Button($r('app.string.confirm_button_text'))
              .height(40)
              .backgroundColor($r('app.color.button_bg_blue'))
              .fontColor($r('app.color.button_text_blue'))
              .onClick(() => {
                this.handleConfirm();
              })
          }
          .width('100%')
          .margin({ top: 20 })
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
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
