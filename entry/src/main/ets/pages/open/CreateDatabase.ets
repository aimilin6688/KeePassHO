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
import { FileKeyService } from '../../services/FileKeyService';

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
  @State keyFilePath: string = '';
  @State keyFileName: ResourceStr = $r('app.string.select_key_file_placeholder');
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.LOCAL);
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  private validatePasswords() {
    if (this.password.length > 0 && this.confirmPassword.length > 0 && this.password !== this.confirmPassword) {
      this.errorMsg = ResourceManager.getString($r('app.string.CreateDatabase_password_mismatch'));
    } else {
      this.errorMsg = '';
    }
  }

  private async createDatabase() {
    if (this.databaseName.length === 0) {
      this.promptAction.showToast({ message: $r("app.string.database_name_placeholder") });
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
        hilog.error(DOMAIN, TAG, `Failed to show document save dialog: ${err.message}`, err.stack);
        this.promptAction.showToast({ message: $r('app.string.CreateDatabase_location_failed', err.message) });
      })
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to create database: ${error.message}`, error.stack);
      this.promptAction.showToast({ message: $r('app.string.CreateDatabase_error_message', error.message) });
    } finally {
      this.isCreating = false;
    }
  }

  /**
   * 保存数据库文件
   * @param filePath
   */
  private async saveKdbxFile(filePath: string) {
    hilog.info(DOMAIN, TAG, `Selected URI: ${filePath}`);
    let keyFileContent: ArrayBuffer | null = null;
    if (this.keyFilePath) {
      await new KdbxFileManager(StorageType.LOCAL).readFile(this.keyFilePath).then(fileContent => {
        keyFileContent = fileContent.content;
      })
    }
    let credentials = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString(this.password), keyFileContent);
    // 将kdbx对象转换为ArrayBuffer
    let newDb = kdbxweb.Kdbx.create(credentials, this.databaseName);
    newDb.save().then((dbContent: ArrayBuffer) => {
      hilog.info(DOMAIN, TAG, 'saveKdbxFile: ', dbContent.byteLength);
      // 保存数据库文件
      this.fileManager.writeFile(filePath, dbContent).then(async () => {
        hilog.info(DOMAIN, TAG, 'Database saved successfully: %{public}s', filePath);
        // 显示成功提示
        this.promptAction.showToast({ message: $r("app.string.CreateDatabase_create_success") });
        await RecentFilesService.getInstance().addRecentFile({
          filePath: filePath,
          fileName: FileUtils.getFileName(filePath),
          storageType: StorageType.LOCAL,
          authType: AuthType.PASSWORD,
          storageConfig: new LocalFileStorageConfig(dbContent.byteLength)
        }).then((result) => {
          // 跳转到密码页面
          this.router.replaceUrl({
            url: 'pages/Password',
            params: {
              filePath: filePath
            }
          });
        }).catch((error: Error) => {
          // 通过DocumentViewPicker save 保存的文件，不能持久化授权，只能让用户重新选择文件授权
          hilog.error(DOMAIN, TAG, `Failed to add recent file: ${error.message}`, error.stack);
          // 跳转到首页面
          this.router.replaceUrl({ url: 'pages/Index' });
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

  /**
   * 选择密钥文件
   */
  private async selectKeyFile() {
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const result = await documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: [] // 只显示key文件
    });
    if (result && result.length > 0) {
      const fileUri = result[0];
      this.keyFilePath = fileUri;
      this.keyFileName = FileUtils.getFileName(fileUri);
    }
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
        Row(){
          Text("*")
            .fontColor($r('app.color.required'))
          Text($r("app.string.database_name"))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)
        }.width('100%')
        .margin({ top: 20, left: 16 })


        TextInput({ placeholder: $r("app.string.database_name_placeholder"), text: this.databaseName })
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
        Row(){
          Text("*")
            .fontColor($r('app.color.required'))
          Text($r('app.string.password'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)
        }.width('100%')
        .margin({ top: 20, left: 16 })

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
        Row(){
          Text("*")
            .fontColor($r('app.color.required'))
          Text($r("app.string.confirm_password_label"))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)
        }.width('100%')
        .margin({ top: 20, left: 16 })


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

        // 密钥文件
        Text($r("app.string.key_file"))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 20, left: 16 })
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start)
        Row() {
          // 密钥文件选择
          Text(this.keyFileName)
            .height(48)
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
            .borderRadius(8)
            .width("77%")
            .padding({
              top: 6,
              bottom: 6,
              left: 12,
              right: 4
            })
            .backgroundColor($r("app.color.card_bg"))
            .onClick(() => {
              this.selectKeyFile();
            })

          Button($r("app.string.create_new"))
            .height(40)
            .fontSize(16)
            .width("21%")
            .margin({ left: 8 })
            .fontColor($r('app.color.button_text'))
            .backgroundColor(Color.Gray)
            .onClick(() => {
              FileKeyService.createKeyFile(this.context);
            })
        }
        .margin({ top: 8, left: 16, right: 16 })
        .width('100%')
        .borderRadius(8)
        .alignItems(VerticalAlign.Center)

        Text($r("app.string.key_file_tip"))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.yellow'))
          .margin({ top: 4, left: 28, right: 16 })
          .width('100%')
          .textAlign(TextAlign.Start)

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
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .enabled(!this.isCreating && this.databaseName.length > 0 && this.password.length > 0 && this.password === this.confirmPassword)
          .onClick(() => {
            this.createDatabase();
          })
      }
      .width('100%')
      .layoutWeight(1)
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
