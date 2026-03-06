import { CommonUtils, KdbxUtils, ResourceManager, WindowUtils } from '../common/utils';
import { FileService } from '../services/FileService';
import { RecentFilesService } from '../services/RecentFilesService';
import { DataService } from '../services/DataService';
import { LocationInfo, LocationMode, LocationParam } from '../services/beans/LocationParam';
import { Router } from '@kit.ArkUI';
import { ToastSaveDatabaseCallback } from '../workers/callback/ToastSaveDatabaseCallback';
import { common } from '@kit.AbilityKit';
import { AuthType } from '../services/TypeDefined';

/**
 * 修改密码
 */
@Entry
@Component
struct ChangePassword {
  @State oldPassword: string = ''; // 旧密码
  @State newPassword: string = ''; // 新密码
  @State confirmPassword: string = ''; // 确认新密码
  @State keyLocation: LocationInfo | undefined = undefined; // 密钥文件路径
  @State keyFileName: string = ResourceManager.getString($r('app.string.select_key_file_placeholder')); // 密钥文件名称
  @State errorMessage: string = ''; // 错误信息
  @State notUseKeyFile: boolean = false; // 不使用keyfile
  @State isKeyfileOnlyMode: boolean = false; // 当前是否为仅密钥文件模式
  @State useKeyfileOnly: boolean = false; // 是否切换到仅密钥文件模式
  private router: Router = this.getUIContext().getRouter();

  onPageShow(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
    // 初始化当前认证模式
    const dbFileParam = FileService.getDbFileParam();
    this.isKeyfileOnlyMode = AuthType.isKeyfileOnly(dbFileParam.authType);
    // 如果当前是仅密钥文件模式，初始化密钥文件信息
    if (this.isKeyfileOnlyMode && dbFileParam.keyLocation) {
      this.keyLocation = dbFileParam.keyLocation;
      this.keyFileName = dbFileParam.keyLocation.fileName;
    }
  }

  private changePassword() {
    if (!this.validatePassword()) {
      return;
    }
    const dbFileParam = FileService.getDbFileParam();
    // 仅密钥文件模式下不需要验证旧密码
    if (!this.isKeyfileOnlyMode && this.oldPassword !== dbFileParam.password) {
      this.errorMessage = ResourceManager.getString($r('app.string.change_password_old_password_not_match'));
      return;
    }
    // 设置新的数据库密码和密钥文件
    dbFileParam.newPassword = this.useKeyfileOnly ? '' : this.newPassword;
    dbFileParam.newKeyLocation = this.keyLocation;
    dbFileParam.notUseKeyFile = this.notUseKeyFile;
    // 更新数据库主密码
    KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
      onSuccess: () => {
        this.errorMessage = '';
        this.handlePasswordChange();
      },
      onError: (message) => {
        this.errorMessage = message;
      },
    }));
  }

  /**
   * 验证密码是否匹配
   */
  private validatePassword(): boolean {
    // 仅密钥文件模式下不需要旧密码验证
    if (!this.isKeyfileOnlyMode && this.oldPassword.trim().length === 0) {
      this.errorMessage = ResourceManager.getString($r('app.string.change_password_old_password_placeholder'));
      return false;
    }
    // 如果切换到仅密钥文件模式，不需要新密码验证
    if (!this.useKeyfileOnly) {
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
    } else {
      // 仅密钥文件模式必须选择密钥文件
      if (!this.keyLocation) {
        this.errorMessage = ResourceManager.getString($r('app.string.key_file_required'));
        return false;
      }
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
    CommonUtils.pushUrl({ url: 'pages/open/SelectLocation' });
  }

  /**
   * 创建新的密钥文件
   */
  private createNewKey() {
    DataService.saveKey((locationInfo: LocationInfo) => {
      this.keyLocation = locationInfo;
      this.keyFileName = locationInfo.fileName;
      CommonUtils.showToast({ message: $r("app.string.save_success") });
      this.router.back({ url: 'pages/ChangePassword' });
    }, (error) => {
      this.router.back();
    });
    CommonUtils.pushUrl({ url: 'pages/open/SelectLocation' });
  }

  /**
   * 密码修改成功回调
   */
  private handlePasswordChange() {
    const filePath = FileService.getFilePath();
    RecentFilesService.clearPassword(filePath).then(() => {
      FileService.close();
      this.router.clear();
    })
    CommonUtils.pushUrl({
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

      // 对话框内容
      Column() {
        // 旧密码输入 - 仅密钥文件模式下不显示
        if (!this.isKeyfileOnlyMode) {
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
        }

        // 仅使用密钥文件模式选项 - 当前不是仅密钥文件模式时显示
        if (!this.isKeyfileOnlyMode) {
          Row() {
            Checkbox({ name: 'useKeyfileOnly' })
              .select(this.useKeyfileOnly)
              .shape(CheckBoxShape.CIRCLE)
              .onChange((value: boolean) => {
                this.useKeyfileOnly = value;
                if (value) {
                  this.notUseKeyFile = false;
                }
              })
            Text($r('app.string.auth_type_keyfile'))
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .margin({ left: 8 })
              .onClick(() => {
                this.useKeyfileOnly = !this.useKeyfileOnly;
                if (this.useKeyfileOnly) {
                  this.notUseKeyFile = false;
                }
              })
          }
          .width("100%")
          .margin({ top: 16, bottom: 4 })
        }

        // 新密码输入 - 仅密钥文件模式下不显示
        if (!this.useKeyfileOnly) {
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
        }

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
            .fontColor($r("app.color.warn"))
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
          .borderRadius(20)
          .fontColor($r('app.color.button_text'))
          .onClick(() => {
            this.router.replaceUrl({ url: 'pages/setting/SettingDatabase' });
          })
        Blank()
        Button($r('app.string.confirm_button_text'))
          .width('45%')
          .height(40)
          .fontSize(16)
          .enabled(this.errorMessage.length == 0)
          .fontColor($r('app.color.button_text'))
          .borderRadius(20)
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
