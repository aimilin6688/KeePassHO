import KdbxUtils from '../common/utils/KdbxUtils';
import ResourceManager from '../common/utils/ResourceManager';
import { FileService } from '../services/FileService';
import { RecentFilesService } from '../services/RecentFilesService';
import { DataService } from '../services/DataService';
import { LocationInfo, LocationMode, LocationParam } from '../services/beans/LocationParam';
import { PromptAction, Router } from '@kit.ArkUI';

/**
 * 修改密码
 */
@Entry
@Component
export struct ChangePassword {
  @State oldPassword: string = ''; // 旧密码
  @State newPassword: string = ''; // 新密码
  @State confirmPassword: string = ''; // 确认新密码
  @State keyLocation: LocationInfo | undefined = undefined; // 密钥文件路径
  @State keyFileName: string = ResourceManager.getString($r('app.string.select_key_file_placeholder')); // 密钥文件名称
  @State errorMessage: string = ''; // 错误信息
  @State notUseKeyFile: boolean = false; // 不适用keyfile

  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private router: Router = this.getUIContext().getRouter();

  private changePassword() {
    if (!this.validatePassword()) {
      return;
    }
    const dbFileParam = FileService.getDbFileParam();
    if (this.oldPassword !== dbFileParam.password) {
      this.errorMessage = ResourceManager.getString($r('app.string.change_password_old_password_not_match'));
      return;
    }
    // 设置新的数据库密码和密钥文件
    dbFileParam.newPassword = this.newPassword;
    dbFileParam.newKeyLocation = this.keyLocation;
    dbFileParam.notUseKeyFile = this.notUseKeyFile;
    // 更新数据库主密码
    KdbxUtils.saveDatabase({
      onSuccess: () => {
        // 重置最近打开文件的数据库密码
        RecentFilesService.setPassword(dbFileParam.filePath, this.newPassword);
        this.handlePasswordChange();
      }
    });
  }

  /**
   * 验证密码是否匹配
   */
  private validatePassword(): boolean {
    if (this.oldPassword.trim().length === 0) {
      this.errorMessage = ResourceManager.getString($r('app.string.change_password_old_password_placeholder'));
      return false;
    }
    if (this.newPassword.trim().length === 0) {
      this.errorMessage = ResourceManager.getString($r('app.string.change_password_new_password_placeholder'));
      return false;
    }
    if (this.confirmPassword.trim().length === 0) {
      this.errorMessage = ResourceManager.getString($r('app.string.change_password_confirm_password_placeholder'));
      return false;
    }
    if (this.newPassword !== this.confirmPassword) {
      this.errorMessage = ResourceManager.getString($r('app.string.change_password_confirm_password_not_match'));
      return false;
    }
    this.errorMessage = '';
    return true;
  }

  /**
   * 选择密钥文件
   */
  private async selectKeyFile() {
    LocationParam.of({
      mode: LocationMode.SELECT,
      onLocation: (locationInfo: LocationInfo) => {
        this.keyLocation = locationInfo;
        this.keyFileName = locationInfo.fileName;
        this.router.back({ url: 'pages/ChangePassword' });
      }
    });
    this.router.pushUrl({ url: 'pages/open/SelectLocation' });
  }

  /**
   * 创建新的密钥文件
   */
  private createNewKey() {
    DataService.saveKey((locationInfo: LocationInfo) => {
      this.keyLocation = locationInfo;
      this.keyFileName = locationInfo.fileName;
      this.promptAction.showToast({ message: $r("app.string.save_success") });
      this.router.back({ url: 'pages/ChangePassword' });
    }, (error) => {
      this.router.back();
    });
    this.router.pushUrl({ url: 'pages/open/SelectLocation' });
  }

  /**
   * 密码修改成功回调
   */
  private handlePasswordChange() {
    this.promptAction.showToast({ message: $r('app.string.operation_success'), duration: 2000 });
    let filePath = FileService.getDbFileParam().filePath;
    FileService.close();
    this.router.clear();
    RecentFilesService.clearPassword(filePath);
    this.router.pushUrl({
      url: 'pages/Password',
      params: {
        filePath: filePath,
      }
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
            this.router.back();
          })

        Text($r('app.string.change_password'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

      // 对话框内容
      Column() {
        // 旧密码输入
        Row() {
          Text("*").fontColor($r('app.color.required'))
          Text($r('app.string.change_password_old_password'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        }.width('100%')
        .margin({ top: 8, bottom: 4 })

        TextInput({ placeholder: $r('app.string.change_password_old_password_placeholder'), text: this.oldPassword })
          .type(InputType.Password)
          .height(48)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .borderRadius(8)
          .width("100%")
          .enableAutoFill(false)
          .onChange((value) => {
            this.oldPassword = value;
            this.validatePassword();
          })

        // 新密码输入
        Row() {
          Text("*").fontColor($r('app.color.required'))
          Text($r('app.string.change_password_new_password'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        }.width('100%').margin({ top: 16, bottom: 4 })

        TextInput({ placeholder: $r('app.string.change_password_new_password_placeholder'), text: this.newPassword })
          .type(InputType.Password)
          .height(48)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .borderRadius(8)
          .width("100%")
          .enableAutoFill(false)
          .onChange((value) => {
            this.newPassword = value;
            this.validatePassword();
          })

        // 确认新密码输入
        Row() {
          Text("*").fontColor($r('app.color.required'))
          Text($r('app.string.change_password_confirm_password'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        }.width('100%').margin({ top: 16, bottom: 4 })

        TextInput({ placeholder: $r('app.string.change_password_confirm_password_placeholder'), text: this.confirmPassword })
          .type(InputType.Password)
          .height(48)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .borderRadius(8)
          .width("100%")
          .enableAutoFill(false)
          .onChange((value) => {
            this.confirmPassword = value;
            this.validatePassword();
          })

        // 密钥文件选择
        Text($r("app.string.key_file"))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16, bottom: 4 })

        if (!this.notUseKeyFile) {
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
              .backgroundColor($r("app.color.bg_secondary"))
              .onClick(() => {
                this.selectKeyFile();
              })

            Button($r("app.string.create_new"))
              .height(40)
              .fontSize(14)
              .width("21%")
              .margin({ left: 8 })
              .fontColor($r('app.color.button_text'))
              .backgroundColor(Color.Gray)
              .onClick(() => {
                this.createNewKey();
              })
          }
          .width("100%")
          .alignItems(VerticalAlign.Center)

          Text($r('app.string.change_password_key_file_tip'))
            .fontSize(12)
            .fontColor($r('app.color.yellow'))
            .margin({ top: 4 })
        }
        // 不适用密钥文件
        Row() {
          Checkbox({ name: 'notUseKeyFile' })
            .select(this.notUseKeyFile)
            .shape(CheckBoxShape.CIRCLE)
            .onChange((value: boolean) => {
              this.notUseKeyFile = value;
            })
          Text($r('app.string.key_file_not_use_key_file'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.notUseKeyFile = !this.notUseKeyFile;
            })
        }
        .width("100%")
        .margin({ top: 16, bottom: 4 })

        // 密码匹配提示
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor('#FF0000')
            .margin({ top: 4 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: 24,
        right: 24,
        top: 16,
        bottom: 16
      })

      // 底部按钮
      Row() {
        Button($r('app.string.cancel_button_text'))
          .width('45%')
          .height(40)
          .fontSize(16)
          .backgroundColor(Color.Gray)
          .fontColor($r('app.color.button_text'))
          .onClick(() => {
            this.router.replaceUrl({url: 'pages/SettingDatabase'});
          })
        Blank()
        Button($r('app.string.confirm_button_text'))
          .width('45%')
          .height(40)
          .fontSize(16)
          .enabled(this.errorMessage.length == 0)
          .fontColor($r('app.color.button_text'))
          .backgroundColor($r("app.color.button_bg_blue"))
          .onClick(() => {
            this.changePassword();
          })
      }
      .width('100%')
      .height(45)
      .padding({
        top: 12,
        bottom: 0,
        left: 16,
        right: 16
      })
      .position({ x: 0, y: '100%' })
      .translate({ y: -45 }) // 调整位置，确保正确显示
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
