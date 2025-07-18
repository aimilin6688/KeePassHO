import { PromptAction, Router } from '@kit.ArkUI';

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
          
          Text('关于')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
          
          Blank()
        }
        .width('100%')
        .height(56)
        .backgroundColor($r("app.color.card_bg"))

        // 内容
        Column() {
          Text('KeePassHO')
            .fontSize(20)
            .margin({top: 20, bottom: 30})

          Text('版本: 1.0.0')
            .fontSize(16)
            .margin(5)

          Text('KeePassHO 是一款支持Keepass 2.x格式的密码管理器应用。')
            .margin({top: 20})
            .fontSize(16)
            .margin(5)
        }
        .width('100%')
        .height('100%')
        .padding(16)
      }
    }
    .width('100%')
    .height('100%')
  }
}
