import { Router } from '@kit.ArkUI';
import ResourceManager from '../common/utils/ResourceManager';
import { ChangePasswordDialog } from '../components/ChangePasswordDialog';
import { AuthService } from '../services/AuthService';
import { FileService } from '../services/FileService';
import { RecentFilesService } from '../services/RecentFilesService';
import { UnlockAuthType, SettingsService } from '../services/SettingsService';


@Entry
@Component
struct SettingsDatabase {
  @State isDatabaseValid: boolean = false;
  @State fingerprintLogin: boolean = SettingsService.KEY_DATABASE_FINGERPRINT_LOGIN_DEFAULT;
  @State faceLogin: boolean = SettingsService.KEY_DATABASE_FACE_LOGIN_DEFAULT;
  @State authTypeOptions: AuthTypeOptions[] = [{ "type": UnlockAuthType.PASSWORD, "value": ResourceManager.getString($r("app.string.password")) }];
  @State defaultAuthType: UnlockAuthType = SettingsService.KEY_DATABASE_AUTH_DEFAULT_TYPE_DEFAULT;

  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();
  private settingsService: SettingsService = SettingsService.getInstance();
  private isFingerprintSupport: boolean = AuthService.isFingerprintSupport();
  private isFaceSupport: boolean = AuthService.isFaceSupport();
  private changePasswordDialogController: CustomDialogController = new CustomDialogController({
    builder: ChangePasswordDialog({
      onSuccess: this.handlePasswordChange.bind(this)
    }),
    cancel: this.handleDialogCancel.bind(this),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });

  aboutToAppear(): void {
    // 获取是否开启下拉刷新功能
    this.settingsService.get(SettingsService.KEY_DATABASE_FINGERPRINT_LOGIN, this.fingerprintLogin).then(result => {
      this.fingerprintLogin = result;
    });
    // 获取是否开启下拉刷新功能
    this.settingsService.get(SettingsService.KEY_DATABASE_FACE_LOGIN, this.faceLogin).then(result => {
      this.faceLogin = result;
    });
    // 获取是否开启下拉刷新功能
    this.settingsService.get(SettingsService.KEY_DATABASE_AUTH_DEFAULT_TYPE, this.defaultAuthType).then(result => {
      this.defaultAuthType = result;
    });

    if(this.isFingerprintSupport){
      this.authTypeOptions.push({ "type": UnlockAuthType.FINGERPRINT, "value": ResourceManager.getString($r("app.string.fingerprint")) });
    }
    if(this.isFaceSupport){
      this.authTypeOptions.push({ "type": UnlockAuthType.FACE, "value": ResourceManager.getString($r("app.string.face")) });
    }
  }

  onPageShow(): void {
    const dbFileParam = FileService.getDbFileParam();
    this.isDatabaseValid = dbFileParam && dbFileParam.database !== undefined;
  }

  // 修改密码弹框
  private showChangePasswordDialog() {
    this.changePasswordDialogController.open();
  }

  /**
   * 密码修改成功回调
   */
  private handlePasswordChange() {
    this.promptAction.showToast({ message: $r('app.string.operation_success'), duration: 2000 });
    let filePath = FileService.getDbFileParam().filePath;
    FileService.close();
    this.router.clear();
    if (this.isFingerprintSupport) {
      RecentFilesService.clearPassword(filePath);
    }
    this.router.pushUrl({
      url: 'pages/Password',
      params: {
        filePath: filePath,
      }
    });
  }

  // 取消修改密码
  private handleDialogCancel() {
    this.changePasswordDialogController.close();
  }

  // 修改指纹登录选项
  private changeFingerprintLogin(isOn: boolean) {
    this.settingsService.put(SettingsService.KEY_DATABASE_FINGERPRINT_LOGIN, isOn);
    if (this.isFingerprintSupport && isOn) {
      let dbFileParam = FileService.getDbFileParam();
      RecentFilesService.setPassword(dbFileParam.filePath, dbFileParam.password);
    }
  }

  // 修改人脸登录选项
  private changeFaceLogin(isOn: boolean) {
    this.settingsService.put(SettingsService.KEY_DATABASE_FACE_LOGIN, isOn);
    if (this.isFaceSupport && isOn) {
      let dbFileParam = FileService.getDbFileParam();
      RecentFilesService.setPassword(dbFileParam.filePath, dbFileParam.password);
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 12 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => this.router.back())
        Text($r('app.string.Settings_database'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))


      List() {
        // 密码相关功能
        if (this.isDatabaseValid) {
          ListItemGroup() {
            if (this.isFingerprintSupport) {
              // 指纹登录
              ListItem() {
                Row() {
                  Text($r("app.string.auth_by_fingerprint"))
                    .fontSize(16)
                    .flexGrow(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.fingerprintLogin })
                    .selectedColor('#007DFF')
                    .switchPointColor('#FFFFFF')
                    .onChange((isOn: boolean) => {
                      this.changeFingerprintLogin(isOn);
                    })
                }
                .width('100%')
                .padding(16)
              }
            }
            if (this.isFaceSupport) {
              // 人脸登录
              ListItem() {
                Row() {
                  Text($r("app.string.auth_by_face"))
                    .fontSize(16)
                    .flexGrow(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.faceLogin })
                    .selectedColor('#007DFF')
                    .switchPointColor('#FFFFFF')
                    .onChange((isOn: boolean) => {
                      this.changeFaceLogin(isOn);
                    })
                }
                .width('100%')
                .padding(16)
              }
            }
            if (this.isFingerprintSupport || this.isFaceSupport) {
              // 选择默认登录方式
              ListItem() {
                Row() {
                  Text($r("app.string.auth_type_default"))
                    .fontSize(16)
                    .flexGrow(1)
                  Select(this.authTypeOptions)
                    .value(this.authTypeOptions[this.authTypeOptions.findIndex((item) => item.type === this.defaultAuthType)].value)
                    .font({ size: 16 })
                    .selectedOptionFont({ size: 16 })
                    .optionFont({ size: 16 })
                    .backgroundColor($r("app.color.card_bg"))
                    .onSelect(async (index: number) => {
                      this.defaultAuthType = this.authTypeOptions[index].type;
                      this.settingsService.put(SettingsService.KEY_DATABASE_AUTH_DEFAULT_TYPE, this.defaultAuthType);
                    })
                }
                .width('100%')
                .padding(16)
              }
            }
            // 修改主密码
            ListItem() {
              Row() {
                Text($r("app.string.change_password"))
                  .fontSize(16)
                  .flexGrow(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(20)
                  .height(20)
                  .margin({ right: 10 })
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                this.showChangePasswordDialog();
              })
            }
          }
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(12)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
          })

          // 数据库元数据设置
          ListItemGroup() {
            ListItem() {
              Row() {
                Text($r("app.string.Settings_database_metadata"))
                  .fontSize(16)
                  .flexGrow(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(20)
                  .height(20)
                  .margin({ right: 10 })
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                this.router.pushUrl({
                  url: 'pages/SettingDatabaseMeta',
                  params: {}
                });
              })
            }

            ListItem() {
              Row() {
                Text($r("app.string.Settings_custom_icons"))
                  .fontSize(16)
                  .flexGrow(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(20)
                  .height(20)
                  .margin({ right: 10 })
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                this.router.pushUrl({
                  url: 'pages/SettingCustomIcons',
                  params: {}
                });
              })
            }
          }
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(12)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
          })
        } else {
          ListItem() {
            Text($r('app.string.database_not_opened'))
              .fontSize(16)
              .margin({ top: 20, bottom: 12 })
              .textAlign(TextAlign.Center)
              .width('100%')
              .fontColor($r('app.color.text_secondary'))
          }
        }
      }
      .width('100%')
      .height('auto')
      .layoutWeight(1)
      .margin({ top: 12 })
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}

/**
 * 认证方式
 */
export interface AuthTypeOptions {
  value: string;
  type: UnlockAuthType;
}
