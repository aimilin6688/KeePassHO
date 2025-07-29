import { SettingsService } from "../services/SettingsService";
import { Router } from "@kit.ArkUI";


@Entry
@Component
export struct SettingsSecurity {
  @State isPullToRefresh:boolean = true;
  @State clipboardClearTime:number = 30;


  private settingsService: SettingsService = SettingsService.getInstance();
  private router: Router = this.getUIContext().getRouter();

  aboutToAppear(): void {
    // 获取是否开启下拉刷新功能
    this.settingsService.get(SettingsService.KEY_SECURITY_PULL_REFRESH, true).then(result=>{
      this.isPullToRefresh = result;
    });

    // 获取清理剪切板时间
    this.settingsService.get(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, 30).then(result=>{
      this.clipboardClearTime = result;
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