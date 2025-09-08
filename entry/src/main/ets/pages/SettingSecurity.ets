import { SettingsService, UnlockAuthType } from '../services/SettingsService';
import { Router } from '@kit.ArkUI';
import ResourceManager from '../common/utils/ResourceManager';
import { FileService } from '../services/FileService';
import { AuthService } from '../services/AuthService';
import { RecentFilesService } from '../services/RecentFilesService';


@Entry
@Component
struct SettingsSecurity {
  @State isPullToRefresh: boolean = SettingsService.KEY_SECURITY_PULL_REFRESH_DEFAULT;
  @State searchHistoryEnabled: boolean = SettingsService.KEY_SECURITY_SEARCH_HISTORY_ENABLE_DEFAULT;
  @State clipboardClearTime: number = SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT;
  @State autoLockTime: number = SettingsService.KEY_SECURITY_AUTO_LOCK_TIME_DEFAULT;
  @State quickLockPasswordLength: number = SettingsService.KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH_DEFAULT;
  @State isListShowTotp: boolean = SettingsService.KEY_SECURITY_LIST_SHOW_TOTP_DEFAULT;
  @State isItemShowTotp: boolean = SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP_DEFAULT;
  // 认证方式
  @State fingerprintLogin: boolean = SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN_DEFAULT;
  @State faceLogin: boolean = SettingsService.KEY_SECURITY_FACE_LOGIN_DEFAULT;
  @State authTypeOptions: AuthTypeOptions[] = [{ "type": UnlockAuthType.PASSWORD, "value": ResourceManager.getString($r("app.string.password")) }];
  @State defaultAuthType: UnlockAuthType = SettingsService.KEY_SECURITY_AUTH_DEFAULT_TYPE_DEFAULT;
  @State isDatabaseValid: boolean = false;
  private isFingerprintSupport: boolean = AuthService.isFingerprintSupport();
  private isFaceSupport: boolean = AuthService.isFaceSupport();
  // 自动清空剪切板时间
  private clearTimeOptions: Array<TimeOption> = [
    { value: "15 " + ResourceManager.getString($r("app.string.second")), time: 15 },
    { value: "30 " + ResourceManager.getString($r("app.string.second")), time: 30 },
    { value: "1 " + ResourceManager.getString($r("app.string.minute")), time: 60 },
    { value: "3 " + ResourceManager.getString($r("app.string.minute")), time: 180 },
    { value: "5 " + ResourceManager.getString($r("app.string.minute")), time: 300 },
    { value: "10 " + ResourceManager.getString($r("app.string.minute")), time: 600 },
    { value: ResourceManager.getString($r("app.string.never")), time: -1 },
  ];
  // 至于后台多长时间自动锁定
  private autoLockTimeOptions: Array<TimeOption> = [
    { value: "5 " + ResourceManager.getString($r("app.string.second")), time: 5 },
    { value: "30 " + ResourceManager.getString($r("app.string.second")), time: 30 },
    { value: "1 " + ResourceManager.getString($r("app.string.minute")), time: 60 },
    { value: "3 " + ResourceManager.getString($r("app.string.minute")), time: 180 },
    { value: "5 " + ResourceManager.getString($r("app.string.minute")), time: 300 },
    { value: "10 " + ResourceManager.getString($r("app.string.minute")), time: 600 },
    { value: "30 " + ResourceManager.getString($r("app.string.minute")), time: 1800 },
    { value: "1 " + ResourceManager.getString($r("app.string.hour")), time: 3600 },
    { value: ResourceManager.getString($r("app.string.never")), time: -1 },
  ];
  // 快速解锁密码长度
  private quickLockPasswordLengthOptions: Array<LengthOption> = [
    { value: "2" },
    { value: "3" },
    { value: "4" },
    { value: "5" },
    { value: "6" },
    { value: "7" },
    { value: "8" }
  ];
  private settingsService: SettingsService = SettingsService.getInstance();
  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();

  aboutToAppear(): void {
    this.initSettings();
  }

  onPageShow(): void {
    const dbFileParam = FileService.getDbFileParam();
    this.isDatabaseValid = dbFileParam && dbFileParam.database !== undefined;
  }

  // 初始化设置信息
  private initSettings(): void {
    // 获取是否开启下拉刷新功能
    this.settingsService.get(SettingsService.KEY_SECURITY_PULL_REFRESH, this.isPullToRefresh).then(result => {
      this.isPullToRefresh = result;
    });

    // 是否启用搜索历史
    this.settingsService.get(SettingsService.KEY_SECURITY_SEARCH_HISTORY_ENABLE, this.searchHistoryEnabled).then(result => {
      this.searchHistoryEnabled = result;
    });

    // 获取清理剪切板时间
    this.settingsService.get(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, this.clipboardClearTime).then(result => {
      this.clipboardClearTime = result;
    });

    // 至于后台多长时间自动锁定
    this.settingsService.get(SettingsService.KEY_SECURITY_AUTO_LOCK_TIME, this.autoLockTime).then(result => {
      this.autoLockTime = result;
    });

    // 快速解锁密码长度
    this.settingsService.get(SettingsService.KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH, this.quickLockPasswordLength).then(result => {
      this.quickLockPasswordLength = result;
    });

    // 列表是否显示TOTP
    this.settingsService.get(SettingsService.KEY_SECURITY_LIST_SHOW_TOTP, this.isListShowTotp).then(result => {
      this.isListShowTotp = result;
    });

    // 条目是否显示TOTP
    this.settingsService.get(SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP, this.isItemShowTotp).then(result => {
      this.isItemShowTotp = result;
    });

    // 获取指纹登录
    this.settingsService.get(SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN, this.fingerprintLogin).then(result => {
      this.fingerprintLogin = result;
    });
    // 获取面容登录
    this.settingsService.get(SettingsService.KEY_SECURITY_FACE_LOGIN, this.faceLogin).then(result => {
      this.faceLogin = result;
    });
    // 获取默认认证方式
    this.settingsService.get(SettingsService.KEY_SECURITY_AUTH_DEFAULT_TYPE, this.defaultAuthType).then(result => {
      this.defaultAuthType = result;
    });

    if (this.isFingerprintSupport) {
      this.authTypeOptions.push({ "type": UnlockAuthType.FINGERPRINT, "value": ResourceManager.getString($r("app.string.fingerprint")) });
    }
    if (this.isFaceSupport) {
      this.authTypeOptions.push({ "type": UnlockAuthType.FACE, "value": ResourceManager.getString($r("app.string.face")) });
    }
  }

  // 修改指纹登录选项
  private changeFingerprintLogin(isOn: boolean) {
    this.settingsService.put(SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN, isOn);
    if (this.isFingerprintSupport && isOn && this.isDatabaseValid) {
      let dbFileParam = FileService.getDbFileParam();
      RecentFilesService.setPassword(dbFileParam.filePath, dbFileParam.password);
    }
  }

  // 修改人脸登录选项
  private changeFaceLogin(isOn: boolean) {
    this.settingsService.put(SettingsService.KEY_SECURITY_FACE_LOGIN, isOn);
    if (this.isFaceSupport && isOn && this.isDatabaseValid) {
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
        Text($r('app.string.Settings_security'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)


      List() {
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
                    this.settingsService.put(SettingsService.KEY_SECURITY_AUTH_DEFAULT_TYPE, this.defaultAuthType);
                  })
              }
              .width('100%')
              .padding({
                left: 16,
                right: 16,
                top: 9,
                bottom: 9
              })
            }
          }
        }
        .margin({ top: 12, bottom: 12 })
        .backgroundColor($r("app.color.card_bg"))
        .borderRadius(12)
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
        })

        ListItemGroup() {
          // 下拉刷新
          ListItem() {
            Row() {
              Text($r("app.string.security_is_pull_to_refresh"))
                .fontSize(16)
                .flexGrow(1)
              Toggle({ type: ToggleType.Switch, isOn: this.isPullToRefresh })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.settingsService.put(SettingsService.KEY_SECURITY_PULL_REFRESH, isOn);
                })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
            })
          }

          // 搜索历史
          ListItem() {
            Row() {
              Text($r("app.string.security_search_history_enabled"))
                .fontSize(16)
                .flexGrow(1)
              Toggle({ type: ToggleType.Switch, isOn: this.searchHistoryEnabled })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.settingsService.put(SettingsService.KEY_SECURITY_SEARCH_HISTORY_ENABLE, isOn);
                })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
            })
          }

          // 剪切板自动清理时间
          ListItem() {
            Row() {
              Text($r("app.string.security_auto_clear_pasteboard_time"))
                .fontSize(16)
                .flexGrow(1)

              Select(this.clearTimeOptions)
                .value(this.clearTimeOptions[this.clearTimeOptions.findIndex((item) => item.time === this.clipboardClearTime)].value)
                .font({ size: 16 })
                .selectedOptionFont({ size: 16 })
                .optionFont({ size: 16 })
                .backgroundColor($r("app.color.card_bg"))
                .onSelect(async (index: number) => {
                  this.clipboardClearTime = this.clearTimeOptions[index].time;
                  this.settingsService.put(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, this.clipboardClearTime);
                })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
            })
          }

          // 至于后台多长时间自动锁定
          ListItem() {
            Row() {
              Text($r("app.string.security_auto_lock_time"))
                .fontSize(16)
                .flexGrow(1)

              Select(this.autoLockTimeOptions)
                .value(this.autoLockTimeOptions[this.autoLockTimeOptions.findIndex((item) => item.time === this.autoLockTime)].value)
                .font({ size: 16 })
                .selectedOptionFont({ size: 16 })
                .optionFont({ size: 16 })
                .backgroundColor($r("app.color.card_bg"))
                .onSelect(async (index: number) => {
                  this.autoLockTime = this.autoLockTimeOptions[index].time;
                  this.settingsService.put(SettingsService.KEY_SECURITY_AUTO_LOCK_TIME, this.autoLockTime);
                })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
            })
          }

          // 快速解锁密码长度
          ListItem() {
            Row() {
              Text($r("app.string.security_quick_lock_password_length"))
                .fontSize(16)
                .flexGrow(1)

              Select(this.quickLockPasswordLengthOptions)
                .value(this.quickLockPasswordLength + "")
                .font({ size: 16 })
                .selectedOptionFont({ size: 16 })
                .optionFont({ size: 16 })
                .backgroundColor($r("app.color.card_bg"))
                .onSelect(async (index: number) => {
                  this.quickLockPasswordLength = parseInt(this.quickLockPasswordLengthOptions[index].value);
                  this.settingsService.put(SettingsService.KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH, this.quickLockPasswordLength);
                })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
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

        //显示设置
        ListItemGroup() {
          // 列表显示totp字段
          ListItem() {
            Row() {
              Text($r("app.string.security_list_show_totp"))
                .fontSize(16)
                .flexGrow(1)
              Toggle({ type: ToggleType.Switch, isOn: this.isListShowTotp })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.settingsService.put(SettingsService.KEY_SECURITY_LIST_SHOW_TOTP, isOn);
                })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
            })
          }

          // 条目显示totp字段
          ListItem() {
            Row() {
              Text($r("app.string.security_item_show_totp"))
                .fontSize(16)
                .flexGrow(1)
              Toggle({ type: ToggleType.Switch, isOn: this.isItemShowTotp })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.settingsService.put(SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP, isOn);
                })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
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
      }
      .width('100%')
      .height('auto')
      .layoutWeight(1)
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP,SafeAreaEdge.BOTTOM])
  }
}

/**
 * 主题选项接口
 */
export interface TimeOption {
  time: number;
  value: string;
}

/**
 * 主题选项接口
 */
export interface LengthOption {
  value: string;
}

/**
 * 认证方式
 */
export interface AuthTypeOptions {
  value: string;
  type: UnlockAuthType;
}