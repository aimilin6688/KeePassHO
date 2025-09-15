import { SettingsService } from '../../services/SettingsService';
import { Router } from '@kit.ArkUI';
import { SupportService } from '../../services/SupportService';


@Entry
@Component
struct SettingApplication {
  @State isHideSupportDialog: boolean = !SettingsService.KEY_SHOW_SUPPORT_DIALOG_DEFAULT;
  private settingsService: SettingsService = SettingsService.getInstance();
  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();

  aboutToAppear(): void {
    this.initSettings();
  }

  // 初始化设置信息
  private initSettings(): void {
    // 是否隐藏支持对话框
    this.settingsService.get(SettingsService.KEY_SHOW_SUPPORT_DIALOG, SettingsService.KEY_SHOW_SUPPORT_DIALOG_DEFAULT).then(result => {
      this.isHideSupportDialog = !result;
    });
  }

  // 隐藏支持弹框
  private hideSupportDialog(isOn: boolean) {
    // 开启隐藏时处理
    if (isOn) {
      if (!SupportService.isCanHideSupport()) {
        this.promptAction.showToast({ message: $r('app.string.application_hide_support_tips'), duration: 2000 });
        this.isHideSupportDialog = false;
        return;
      }
      this.isHideSupportDialog = true;
      // 已经使用过一段时间了,隐藏捐赠弹框
      SettingsService.put(SettingsService.KEY_SHOW_SUPPORT_DIALOG, false);
    } else {
      this.isHideSupportDialog = false;
      SettingsService.put(SettingsService.KEY_SHOW_SUPPORT_DIALOG, true);
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
        Text($r('app.string.Settings_application'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)


      List() {
        ListItemGroup() {
          // 隐藏支持对话框
          ListItem() {
            Row() {
              Column() {
                Text($r("app.string.application_hide_support"))
                  .fontSize(16)
                  .flexGrow(1)
                Text($r("app.string.application_hide_support_tips"))
                  .fontSize(12)
                  .fontColor($r("app.color.text_secondary"))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .flexGrow(1)
              .layoutWeight(1)

              Blank()

              Toggle({ type: ToggleType.Switch, isOn: $$this.isHideSupportDialog })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.hideSupportDialog(isOn);
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
      }
      .width('100%')
      .height('auto')
      .layoutWeight(1)
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}