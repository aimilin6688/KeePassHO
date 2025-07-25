import { PromptAction, Router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ResourceManager from '../common/utils/ResourceManager'

const DOMAIN = 0x0000;
const TAG = 'About';

@Entry
@Component
export struct About {
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  build() {
    Stack() {
      // 内容区域
      Column() {
        // 标题栏
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .margin({left: 12, right: 12})
            .fillColor($r('app.color.text_primary'))
            .onClick(() => {
              this.router.back()
            })
          
          Text($r('app.string.Settings_about'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
          
          Blank()
        }
        .width('100%')
        .height(56)
        .backgroundColor($r("app.color.card_bg"))

        // 内容
        Column() {
          Text($r('app.string.EntryAbility_label'))
            .fontSize(20)
            .margin({top: 20, bottom: 30})

          Text(ResourceManager.getString($r('app.string.About_version')) + '1.0.0')
            .fontSize(16)
            .margin(5)

          Text($r('app.string.About_description'))
            .margin({top: 20})
            .fontSize(16)
            .margin(5)
        }
        .width('100%')
        .height('100%')
        .padding(16)
      }
    }
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
