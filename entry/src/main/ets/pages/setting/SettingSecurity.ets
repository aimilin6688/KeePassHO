import { SettingsService, UnlockAuthType, ExpiryRemindFrequency } from '../../services/SettingsService';
import { CommonUtils, ResourceManager } from '../../common/utils';
import { FileService } from '../../services/FileService';
import { AuthService } from '../../services/AuthService';
import { RecentFilesService } from '../../services/RecentFilesService';
import { AuthType } from '../../services/TypeDefined';
import { SessionManager } from '../../services/SessionManager';
import { BusinessError } from '@kit.BasicServicesKit';

@Builder
export function SettingSecurityBuilder(name: string, param: Object): void {
  NavDestination() {
    SettingSecurityContent()
  }
  .title($r('app.string.Settings_security'))
  .backgroundColor($r('app.color.bg_primary'))
}

@Component
struct SettingSecurityContent {
  @State isPullToRefresh: boolean = SettingsService.KEY_SECURITY_PULL_REFRESH_DEFAULT;
  @State searchHistoryEnabled: boolean = SettingsService.KEY_SECURITY_SEARCH_HISTORY_ENABLE_DEFAULT;
  @State clipboardClearTime: number = SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT;
  @State autoLockTime: number = SettingsService.KEY_SECURITY_AUTO_LOCK_TIME_DEFAULT;
  @State quickLockPasswordLength: number = SettingsService.KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH_DEFAULT;
  @State isListShowTotp: boolean = SettingsService.KEY_SECURITY_LIST_SHOW_TOTP_DEFAULT;
  @State isItemShowTotp: boolean = SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP_DEFAULT;
  @State isItemShowGroup: boolean = SettingsService.KEY_SECURITY_ITEM_SHOW_GROUP_DEFAULT;
  @State isPrivacyWindow: boolean = SettingsService.KEY_SECURITY_PRIVACY_WINDOW_DEFAULT;
  // 解锁会话通知
  @State sessionNotifyEnabled: boolean = SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE_DEFAULT;
  // 条目到期提醒（M1）
  @State expireRemindEnabled: boolean = SettingsService.KEY_SECURITY_EXPIRE_REMIND_ENABLE_DEFAULT;
  @State expireRemindDays: number = SettingsService.KEY_SECURITY_EXPIRE_REMIND_DAYS_DEFAULT;
  @State expireRemindFrequency: ExpiryRemindFrequency = SettingsService.KEY_SECURITY_EXPIRE_REMIND_FREQUENCY_DEFAULT;
  // 认证方式
  @State fingerprintLogin: boolean = SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN_DEFAULT;
  @State faceLogin: boolean = SettingsService.KEY_SECURITY_FACE_LOGIN_DEFAULT;
  @State authTypeOptions: AuthTypeOptions[] = [{ "type": UnlockAuthType.PASSWORD, "value": ResourceManager.getString($r("app.string.password")) }];
  @State defaultAuthType: UnlockAuthType = SettingsService.KEY_SECURITY_AUTH_DEFAULT_TYPE_DEFAULT;
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
  private quickLockPasswordLengthOptions: Array<LengthOption> = [    { value: "2" },
    { value: "3" },
    { value: "4" },
    { value: "5" },
    { value: "6" },
    { value: "7" },
    { value: "8" }
  ];
  // 到期提醒提前天数（M1）
  private expireRemindDaysOptions: Array<TimeOption> = [
    { value: ResourceManager.getString($r("app.string.settings_security_expire_remind_days_option"), 1), time: 1 },
    { value: ResourceManager.getString($r("app.string.settings_security_expire_remind_days_option"), 3), time: 3 },
    { value: ResourceManager.getString($r("app.string.settings_security_expire_remind_days_option"), 7), time: 7 },
    { value: ResourceManager.getString($r("app.string.settings_security_expire_remind_days_option"), 14), time: 14 },
    { value: ResourceManager.getString($r("app.string.settings_security_expire_remind_days_option"), 30), time: 30 },
  ];
  // 到期提醒频率（M1）
  private expireRemindFrequencyOptions: Array<ExpiryRemindFrequencyOption> = [
    { value: ResourceManager.getString($r("app.string.settings_security_expire_remind_every_unlock")), frequency: ExpiryRemindFrequency.EVERY_UNLOCK },
    { value: ResourceManager.getString($r("app.string.settings_security_expire_remind_daily")), frequency: ExpiryRemindFrequency.DAILY },
  ];
  private settingsService: SettingsService = SettingsService.getInstance();

  aboutToAppear(): void {
    this.initSettings();
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

    // 条目是否显示分组名称
    this.settingsService.get(SettingsService.KEY_SECURITY_ITEM_SHOW_GROUP, this.isItemShowGroup).then(result => {
      this.isItemShowGroup = result;
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
    // 是否启用隐私窗口
    this.settingsService.get(SettingsService.KEY_SECURITY_PRIVACY_WINDOW, this.isPrivacyWindow).then(result => {
      this.isPrivacyWindow = result;
    });

    // 解锁会话通知开关
    this.settingsService.get(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE, this.sessionNotifyEnabled).then(result => {
      this.sessionNotifyEnabled = result;
    });

    // 条目到期提醒开关（M1）
    this.settingsService.get(SettingsService.KEY_SECURITY_EXPIRE_REMIND_ENABLE, this.expireRemindEnabled).then(result => {
      this.expireRemindEnabled = result;
    });
    // 到期提醒提前天数
    this.settingsService.get(SettingsService.KEY_SECURITY_EXPIRE_REMIND_DAYS, this.expireRemindDays).then(result => {
      this.expireRemindDays = result;
    });
    // 到期提醒频率
    this.settingsService.get(SettingsService.KEY_SECURITY_EXPIRE_REMIND_FREQUENCY, this.expireRemindFrequency).then(result => {
      this.expireRemindFrequency = result;
    });
  }

  /**
   * 认证类型改变
   * @param isOn 是否开启
   */
  private onAuthTypeChange(authType: string, isOn: boolean) {
    this.settingsService.put(authType, isOn);
    if (isOn && FileService.isDatabaseValid()) {
      let dbFileParam = FileService.getDbFileParam();
      RecentFilesService.setPassword(dbFileParam.filePath, dbFileParam.password);
    }
  }

  /**
   * 验证主密码是否正确
   * @returns
   */
  private checkPassword(authType: string): HitTestMode {
    // 关闭指纹登录
    if (authType === SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN && !this.fingerprintLogin == false) {
      return HitTestMode.Default;
    }
    // 关闭面容登录
    if (authType === SettingsService.KEY_SECURITY_FACE_LOGIN && !this.faceLogin == false) {
      return HitTestMode.Default;
    }
    // 启用隐私窗口
    if (authType === SettingsService.KEY_SECURITY_PRIVACY_WINDOW && !this.isPrivacyWindow == true) {
      return HitTestMode.Default;
    }

    // 构建认证成功回调
    const authSuccessCallback = (): void => {
      this.fingerprintLogin = authType === SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN ? !this.fingerprintLogin : this.fingerprintLogin;
      this.faceLogin = authType === SettingsService.KEY_SECURITY_FACE_LOGIN ? !this.faceLogin : this.faceLogin;
      this.isPrivacyWindow = authType === SettingsService.KEY_SECURITY_PRIVACY_WINDOW ? !this.isPrivacyWindow : this.isPrivacyWindow;
    };

    // 检查是否为仅密钥文件模式
    if (AuthType.isKeyfileOnly(FileService.getDbFileParam().authType)) {
      authSuccessCallback();
      return HitTestMode.None;
    }

    // 密码认证
    AuthService.startPasswordAuth({
      onSuccess: (result): void => {
        authSuccessCallback();
      },
      onFail: (result): void => {
        CommonUtils.showToast($r("app.string.password_error"));
      },
      onError: (error: BusinessError): void => {
        CommonUtils.showToast(error.message);
      }
    });
    return HitTestMode.None;
  }

  build() {
    Column() {
      // 设置内容（弹框中显示，无需导航栏）

      List() {
        if (this.isFingerprintSupport || this.isFaceSupport) {
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
                    .onTouchIntercept(() => {
                      return this.checkPassword(SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN);
                    })
                    .onChange((isOn: boolean) => {
                      this.fingerprintLogin = isOn;
                      this.onAuthTypeChange(SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN, isOn);
                    });
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
                    .onTouchIntercept(() => {
                      return this.checkPassword(SettingsService.KEY_SECURITY_FACE_LOGIN);
                    })
                    .onChange((isOn: boolean) => {
                      this.faceLogin = isOn;
                      this.onAuthTypeChange(SettingsService.KEY_SECURITY_FACE_LOGIN, isOn);
                    });
                }
                .width('100%')
                .padding(16)
              }
            }
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
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(12)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
          })
        }

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

          // 隐私窗口
          ListItem() {
            Row() {
              Column() {
                Text($r("app.string.security_privacy_window"))
                  .fontSize(16)
                  .flexGrow(1)
                Text($r("app.string.security_privacy_window_tips"))
                  .fontSize(12)
                  .fontColor($r("app.color.text_secondary"))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .flexGrow(1)
              .layoutWeight(1)

              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.isPrivacyWindow })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onTouchIntercept(() => {
                  return this.checkPassword(SettingsService.KEY_SECURITY_PRIVACY_WINDOW);
                })
                .onChange((isOn: boolean) => {
                  this.isPrivacyWindow = isOn;
                  this.settingsService.put(SettingsService.KEY_SECURITY_PRIVACY_WINDOW, isOn);
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

          // 解锁会话通知开关
          ListItem() {
            Row() {
              Column() {
                Text($r("app.string.security_session_notify_enable"))
                  .fontSize(16)
                  .flexGrow(1)
                Text($r("app.string.security_session_notify_enable_tips"))
                  .fontSize(12)
                  .fontColor($r("app.color.text_secondary"))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .flexGrow(1)

              Toggle({ type: ToggleType.Switch, isOn: this.sessionNotifyEnabled })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.sessionNotifyEnabled = isOn;
                  this.settingsService.put(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE, isOn);
                  // 启用→禁用：立即删除已显示的通知；禁用→启用：会话进行中立即恢复
                  // 显式传入新值：put 异步落盘，refreshNotification 内部回读会拿到旧值导致行为颠倒
                  SessionManager.getInstance().refreshNotification(isOn);
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

          // 条目显示分组名称
          ListItem() {
            Row() {
              Text($r("app.string.security_item_show_group"))
                .fontSize(16)
                .flexGrow(1)
              Toggle({ type: ToggleType.Switch, isOn: this.isItemShowGroup })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.settingsService.put(SettingsService.KEY_SECURITY_ITEM_SHOW_GROUP, isOn);
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

        // 条目到期提醒设置（M1）
        ListItemGroup() {
          // 条目到期提醒开关
          ListItem() {
            Row() {
              Column() {
                Text($r("app.string.settings_security_expire_remind"))
                  .fontSize(16)
                  .flexGrow(1)
                Text($r("app.string.settings_security_expire_remind_tips"))
                  .fontSize(12)
                  .fontColor($r("app.color.text_secondary"))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .flexGrow(1)

              Toggle({ type: ToggleType.Switch, isOn: this.expireRemindEnabled })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.expireRemindEnabled = isOn;
                  this.settingsService.put(SettingsService.KEY_SECURITY_EXPIRE_REMIND_ENABLE, isOn);
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

          // 到期提醒提前天数
          if (this.expireRemindEnabled) {
            ListItem() {
              Row() {
                Text($r("app.string.settings_security_expire_remind_days"))
                  .fontSize(16)
                  .flexGrow(1)

                Select(this.expireRemindDaysOptions)
                  .value(this.expireRemindDaysOptions[this.expireRemindDaysOptions.findIndex((item: TimeOption) => item.time === this.expireRemindDays)].value)
                  .font({ size: 16 })
                  .selectedOptionFont({ size: 16 })
                  .optionFont({ size: 16 })
                  .backgroundColor($r("app.color.card_bg"))
                  .onSelect(async (index: number) => {
                    this.expireRemindDays = this.expireRemindDaysOptions[index].time;
                    this.settingsService.put(SettingsService.KEY_SECURITY_EXPIRE_REMIND_DAYS, this.expireRemindDays);
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

          // 到期提醒频率
          if (this.expireRemindEnabled) {
            ListItem() {
              Row() {
                Text($r("app.string.settings_security_expire_remind_frequency"))
                  .fontSize(16)
                  .flexGrow(1)

                Select(this.expireRemindFrequencyOptions)
                  .value(this.expireRemindFrequencyOptions[this.expireRemindFrequencyOptions.findIndex((item: ExpiryRemindFrequencyOption) => item.frequency === this.expireRemindFrequency)].value)
                  .font({ size: 16 })
                  .selectedOptionFont({ size: 16 })
                  .optionFont({ size: 16 })
                  .backgroundColor($r("app.color.card_bg"))
                  .onSelect(async (index: number) => {
                    this.expireRemindFrequency = this.expireRemindFrequencyOptions[index].frequency;
                    this.settingsService.put(SettingsService.KEY_SECURITY_EXPIRE_REMIND_FREQUENCY, this.expireRemindFrequency);
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
      .padding({ left: 12, right: 12, top: 4 })
      .clipContent(ContentClipMode.SAFE_AREA)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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

/**
 * 到期提醒频率选项（M1）
 */
export interface ExpiryRemindFrequencyOption {
  value: string;
  frequency: ExpiryRemindFrequency;
}