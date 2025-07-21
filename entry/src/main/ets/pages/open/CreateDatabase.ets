import { PromptAction, Router } from '@kit.ArkUI';
import picker from '@ohos.file.picker';
import common from '@ohos.app.ability.common';
import { AuthType } from '../../services/TypeDefined';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { LocalFileStorageConfig, StorageType } from '../../services/kdbx/interfaces';
import { BusinessError } from '@kit.BasicServicesKit';
import * as kdbxweb from 'kdbxweb';
import { RecentFilesService } from '../../services/RecentFilesService';
import FileUtils from '../../common/utils/FIleUtils';
import ResourceManager from '../../common/utils/ResourceManager';


import { hilog } from '@kit.PerformanceAnalysisKit';
const DOMAIN = 0x0000;
const TAG = 'CreateDatabase';

@Entry
@Component
struct CreateDatabase {
  @State databaseName: string = '';
  @State password: string = '';
  @State confirmPassword: string = '';
  @State isCreating: boolean = false;
  @State errorMsg: string = '';
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.LOCAL);
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back()
          })

        Text($r("app.string.create_database"))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

      // 主要内容区域
      Column() {
        // 数据库名称输入
        Text($r('app.string.CreateDatabase_name_label'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 20, left: 16 })
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start)

        TextInput({ placeholder: $r('app.string.CreateDatabase_name_placeholder'), text: this.databaseName })
          .type(InputType.Normal)
          .placeholderColor($r('app.color.text_secondary'))
          .placeholderFont({ size: 16 })
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r("app.color.card_bg"))
          .margin({ top: 8, left: 16, right: 16 })
          .padding({ left: 12, right: 12 })
          .height(48)
          .width('100%')
          .borderRadius(8)
          .onChange((value) => {
            this.databaseName = value;
          })

        // 密码输入
        Text($r('app.string.password'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 20, left: 16 })
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start)

        Row() {
          TextInput({ placeholder: $r('app.string.password_placeholder'), text: this.password })
            .type(InputType.Password)
            .placeholderColor($r('app.color.text_secondary'))
            .placeholderFont({ size: 16 })
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .padding({ left: 12 })
            .layoutWeight(1)
            .height(48)
            .borderRadius(8)
            .onChange((value) => {
              this.password = value;
              this.validatePasswords();
            })
        }
        .margin({ top: 8, left: 16, right: 16 })
        .width('100%')
        .backgroundColor($r("app.color.card_bg"))
        .borderRadius(8)

        // 确认密码输入
        Text($r("app.string.confirm_password_label"))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 20, left: 16 })
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start)

        Row() {
          TextInput({ placeholder: $r("app.string.confirm_password_placeholder"), text: this.confirmPassword })
            .type(InputType.Password)
            .placeholderColor($r('app.color.text_secondary'))
            .placeholderFont({ size: 16 })
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .padding({ left: 12 })
            .layoutWeight(1)
            .height(48)
            .borderRadius(8)
            .onChange((value) => {
              this.confirmPassword = value;
              this.validatePasswords();
            })
        }
        .margin({ top: 8, left: 16, right: 16 })
        .width('100%')
        .backgroundColor($r("app.color.card_bg"))
        .borderRadius(8)

        // 错误信息
        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(14)
            .fontColor(Color.Red)
            .margin({ top: 8, left: 16 })
        }

        // 创建按钮
        Button($r('app.string.create_database'))
          .width('90%')
          .height(48)
          .margin({ top: 40 })
          .borderRadius(24)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .enabled(!this.isCreating && this.databaseName.length > 0 && this.password.length > 0 && this.password === this.confirmPassword)
          .onClick(() => {
            this.createDatabase();
          })
      }
      .width('100%')
      .layoutWeight(1)
      .padding(16)
      .backgroundColor($r("app.color.bg_primary"))
    }
    .width('100%')
    .height('100%')
  }

  validatePasswords() {
    if (this.password.length > 0 && this.confirmPassword.length > 0 && this.password !== this.confirmPassword) {
      this.errorMsg = ResourceManager.getString($r('app.string.CreateDatabase_password_mismatch'));
    } else {
      this.errorMsg = '';
    }
  }

  async createDatabase() {
    if (this.databaseName.length === 0) {
      this.promptAction.showToast({ message: $r('app.string.CreateDatabase_name_placeholder') });
      return;
    }

    if (this.password.length === 0) {
      this.promptAction.showToast({ message: $r('app.string.password_placeholder') });
      return;
    }

    if (this.password !== this.confirmPassword) {
      this.promptAction.showToast({ message: $r('app.string.CreateDatabase_password_mismatch') });
      return;
    }

    this.isCreating = true;

    try {
      // 确保文件名有.kdbx后缀
      let fileName = this.databaseName;
      if (!fileName.toLowerCase().endsWith('.kdbx')) {
        fileName += '.kdbx';
      }

      // 使用文件选择器让用户选择保存位置
      const documentPicker = new picker.DocumentViewPicker(this.context);
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      options.fileSuffixChoices = ['.kdbx'];

      // 显示文件保存对话框
      documentPicker.save(options).then(async (result) => {
        hilog.info(DOMAIN, TAG, `Selected URIs: ${result}`);
        if (result && result.length > 0) {
          this.saveKdbxFile(result[0]);
        }
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG,`Failed to show document save dialog: ${err.message}`, err.stack);
        this.promptAction.showToast({ message: $r('app.string.CreateDatabase_location_failed', err.message) });
      })
    } catch (error) {
      hilog.error(DOMAIN, TAG,`Failed to create database: ${error.message}`, error.stack);
      this.promptAction.showToast({ message: $r('app.string.CreateDatabase_error_message', error.message) });
    } finally {
      this.isCreating = false;
    }
  }

  private async saveKdbxFile(filePath: string) {
    hilog.info(DOMAIN, TAG,`Selected URI: ${filePath}`);
    let credentials = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString(this.password));
    // 将kdbx对象转换为ArrayBuffer
    let newDb = kdbxweb.Kdbx.create(credentials, this.databaseName);
    newDb.save().then((dbContent: ArrayBuffer) => {
      hilog.info(DOMAIN, TAG, 'saveKdbxFile: ', dbContent.byteLength);
      // 保存数据库文件
      this.fileManager.saveKdbxFile(filePath, dbContent).then(async () => {
        hilog.info(DOMAIN, TAG, 'Database saved successfully: %{public}s', filePath);
        // 显示成功提示
        this.promptAction.showToast({ message: $r("app.string.CreateDatabase_create_success") });
        await RecentFilesService.getInstance()
          .addRecentFile({
            filePath: filePath,
            fileName: FileUtils.getFileName(filePath),
            storageType: StorageType.LOCAL,
            authType: AuthType.PASSWORD,
            storageConfig: new LocalFileStorageConfig(dbContent.byteLength)
          });
        // 跳转到密码页面
        this.router.replaceUrl({
          url: 'pages/Password',
          params: {
            filePath: filePath
          }
        });
      }).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, `Failed to save database: ${error.message}`, error.stack);
        this.promptAction.showToast({ message: $r('app.string.save_failed_message', error.message) });
      });
    }).catch((error: Error) => {
      hilog.info(DOMAIN, TAG, `Failed to create database: ${error.message}`, error.stack);
      this.promptAction.showToast({ message: $r('app.string.CreateDatabase_create_failed') });
    });
  }
}
