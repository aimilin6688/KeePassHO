import { SettingsService } from '../services/SettingsService';
import { Router } from '@kit.ArkUI';
import ResourceManager from '../common/utils/ResourceManager';


@Entry
@Component
export struct SettingsSecurity {
  @State isPullToRefresh: boolean = SettingsService.KEY_SECURITY_PULL_REFRESH_DEFAULT;
  @State clipboardClearTime: number = SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT;
  @State autoLockTime: number = SettingsService.KEY_SECURITY_AUTO_LOCK_TIME_DEFAULT;
  @State quickLockPasswordLength: number = SettingsService.KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH_DEFAULT;
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

  aboutToAppear(): void {
    // 获取是否开启下拉刷新功能
    this.settingsService.get(SettingsService.KEY_SECURITY_PULL_REFRESH, this.isPullToRefresh).then(result => {
      this.isPullToRefresh = result;
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
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .margin({ left: 12 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => this.router.back())
        Text($r('app.string.Settings_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))


      List() {
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
            .padding(16)
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
            .padding(16)
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
            .padding(16)
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
            .padding(16)
          }
        }
        .margin({ top: 12, bottom: 12 })
        .backgroundColor($r("app.color.card_bg"))
        .borderRadius(12)
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
        })

        // 密码相关功能
        ListItemGroup() {
          // 修改主密码
          ListItem() {
            Row() {
              Text($r("app.string.updated_password"))
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