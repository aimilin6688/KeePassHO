import { Router } from '@kit.ArkUI';
import {OpenMethodButton} from "../../components/OpenMethodButton";

@Entry
@Component
struct ExportDatabase {
  private router: Router = this.getUIContext().getRouter();

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back()
          })

        Text($r('app.string.export_database'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

      // 导出方式列表
      Scroll() {
        Column() {
          // 导出方式
          Column() {
            Text($r("app.string.export_select_way"))
              .fontSize(14)
              .opacity(0.6)
              .padding({ left: 16, top: 16, bottom: 8 })
              .fontColor($r('app.color.text_primary'))
              .alignSelf(ItemAlign.Start)

            OpenMethodButton(
              $r('app.media.ic_file'),
              $r('app.string.local_file_button_title'),
              $r("app.string.export_to_local_desc"),
              () => {

              }
            )

            OpenMethodButton(
              $r("app.media.ic_webdav"),
              $r('app.string.webdav_button_title'),
              $r("app.string.export_to_webdav_desc"),
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
