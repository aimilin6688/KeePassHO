import KdbxUtils from '../common/utils/KdbxUtils';
import ResourceManager from '../common/utils/ResourceManager';
import { FileService } from '../services/FileService';
import picker from '@ohos.file.picker';
import { common } from '@kit.AbilityKit';
import FileUtils from '../common/utils/FIleUtils';
import { FileKeyService } from '../services/FileKeyService';

/**
 * 修改主密码对话框组件
 */
@CustomDialog
export struct ChangePasswordDialog {
  @State oldPassword: string = ''; // 旧密码
  @State newPassword: string = ''; // 新密码
  @State confirmPassword: string = ''; // 确认新密码
  @State keyFilePath: string = ''; // 密钥文件路径
  @State keyFileName: string = ResourceManager.getString($r('app.string.select_key_file_placeholder'));  // 密钥文件名称
  @State errorMessage: string = ''; // 错误信息
  public onConfirm: (oldPassword: string, newPassword: string, keyFilePath: string) => void = () => {
  };
  private controller: CustomDialogController;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  private changePassword() {
    if(!this.validatePassword()){
      return;
    }
    const dbFileParam = FileService.getDbFileParam();
    if (this.oldPassword !== dbFileParam.password) {
      this.errorMessage = ResourceManager.getString($r('app.string.change_password_old_password_not_match'));
      return;
    }
    // 设置新的数据库密码和密钥文件
    dbFileParam.newPassword = this.newPassword;
    dbFileParam.newKeyFilePath = this.keyFilePath;
    // 更新数据库主密码
    KdbxUtils.saveDatabase().then(() => {
      this.onConfirm(this.oldPassword, this.newPassword, this.keyFilePath);
      this.close();
    })
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
   * 关闭对话框
   */
  private close() {
    this.controller.close();
  }

  /**
   * 选择密钥文件
   */
  private async selectKeyFile() {
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const result = await documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['.key'] // 只显示key文件
    });
    if (result && result.length > 0) {
      const fileUri = result[0];
      this.keyFilePath = fileUri;
      this.keyFileName = FileUtils.getFileName(fileUri);
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r("app.string.change_password"))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
        Blank()
        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .onClick(() => {
          this.close();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .borderRadius({ topLeft: 16, topRight: 16 })

      // 对话框内容
      Column() {
        // 旧密码输入
        Text($r('app.string.change_password_old_password'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
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
        Text($r('app.string.change_password_new_password'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16, bottom: 4 })
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
        Text($r('app.string.change_password_confirm_password'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16, bottom: 4 })
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

        Row(){
          // 密钥文件选择
          Text(this.keyFileName)
            .height(48)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(8)
            .width("77%")
            .padding({top:6,bottom:6, left:12, right:4})
            .backgroundColor($r("app.color.bg_secondary"))
            .onClick(() => {
              this.selectKeyFile();
            })

          Button($r("app.string.create_new"))
            .height(40)
            .fontSize(16)
            .width("21%")
            .margin({ top: 16, bottom: 4, left: 8 })
            .fontColor($r('app.color.button_text'))
            .backgroundColor(Color.Gray)
            .onClick(() => {
              FileKeyService.createKeyFile(this.context);
            })
        }
        .width("100%")
        Text($r('app.string.change_password_key_file_tip'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })

        // 密码匹配提示
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor('#FF0000')
            .margin({ top: 2 })
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
          .width('48%')
          .height(40)
          .fontSize(16)
          .backgroundColor(Color.Gray)
          .fontColor($r('app.color.button_text'))
          .onClick(() => {
            this.close();
          })

        Button($r('app.string.confirm_button_text'))
          .width('48%')
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
      .padding({
        left: 24,
        right: 24,
        top: 16,
        bottom: 30
      })
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
  }
}
