import router from '@ohos.router';
import { Router } from '@kit.ArkUI';

@Entry
@Component
struct OpenDatabase {
  private router: Router = this.getUIContext().getRouter();

  @Builder
  OpenMethodButton(icon: Resource, title: string|Resource, description: string|Resource, onClick: () => void) {
    Button() {
      Row() {
        Image(icon)
          .width(32)
          .height(32)
          .margin({ right: 16 })
          .fillColor($r('app.color.text_primary'))

        Column() {
          Text(title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .alignSelf(ItemAlign.Start)

          Text(description)
            .fontSize(14)
            .opacity(0.6)
            .margin({ top: 4 })
            .fontColor($r('app.color.text_primary'))
            .alignSelf(ItemAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Image($r('app.media.ic_arrow_right'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height(80)
    .backgroundColor($r("app.color.card_bg"))
    .margin({ top: 1 })
    .onClick(onClick)
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back()
          })

        Text($r('app.string.open_database'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

      // 打开方式列表
      Scroll() {
        Column() {
          // 打开方式
          Column() {
            Text($r('app.string.select_open_method_prompt'))
              .fontSize(14)
              .opacity(0.6)
              .padding({ left: 16, top: 16, bottom: 8 })
              .fontColor($r('app.color.text_primary'))
              .alignSelf(ItemAlign.Start)

            this.OpenMethodButton(
              $r('app.media.ic_file'),
              $r('app.string.local_file_button_title'),
              $r('app.string.local_file_button_description'),
              () => {
                this.router.pushUrl({ url: 'pages/open/LocalFile' })
              }
            )

            this.OpenMethodButton(
              $r('app.media.ic_cloud'),
              $r('app.string.webdav_button_title'),
              $r('app.string.webdav_button_description'),
              () => {
                this.router.pushUrl({ url: 'pages/open/WebDAV' })
              }
            )

          }
          .backgroundColor($r("app.color.card_bg"))
          .margin({ top: 16 })
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart) // 确保内容从顶部开始显示
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
