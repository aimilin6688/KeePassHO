import { Router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

@Entry
@Component
struct Reward {
  @State isShowOtherPay:boolean = false;

  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();

  build() {
    // 内容区域
    Column() {
      // 标题栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 12, right: 12 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back()
          })
        Text($r('app.string.about_give_a_reward'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
        Blank()
      }
      .width('100%')
      .height(56)

      // 内容
      List(){
        ListItem(){
          // Logo或应用图标
          Column() {
            Image($r('app.media.startIcon'))
              .width(90)
              .height(90)
              .margin({ top: 40, bottom: 10 })

            Text($r('app.string.reward_thanks'))
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 20, bottom: 10 })

            Text($r('app.string.reward_description'))
              .margin({ top: 10, bottom: 30 })
              .fontColor($r('app.color.text_secondary'))
              .fontSize(16)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
        }

        // 其他打赏方式
        if(this.isShowOtherPay){
          // 微信支付
          ListItem(){
            // 微信支付
            Column() {
              Text($r('app.string.reward_wechat_pay'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })

              // 使用应用图标作为占位符
              Image($r("app.media.startIcon"))
                .width(200)
                .height(200)
                .margin({ bottom: 10 })
                .borderRadius(8)
                .backgroundColor($r('app.color.card_bg'))
            }
            .width('100%')
          }
          .margin({ bottom: 30 })

          // 支付宝
          ListItem(){
            Column() {
              Text($r('app.string.reward_alipay'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })

              // 使用应用图标作为占位符
              Image($r("app.media.startIcon"))
                .width(200)
                .height(200)
                .margin({ bottom: 10 })
                .borderRadius(8)
                .backgroundColor($r('app.color.card_bg'))
            }
            .width('100%')
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding(16)
    }
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
  }
}