import { Router } from '@kit.ArkUI';
import { OpenMethodButton } from '../../components/OpenMethodButton';
import { LocationParam } from '../../services/beans/LocationParam';

@Entry
@Component
struct SelectLocation {
  private router: Router = this.getUIContext().getRouter();
  @State titleMsg: ResourceStr = '';
  @State descLocation: ResourceStr = '';
  @State descWebDav: ResourceStr = '';

  aboutToAppear(): void {
    this.initMsg();
  }

  // 类型提示文本
  private initMsg(): void {
    if (LocationParam.isSaveMode()) {
      this.titleMsg = $r('app.string.location_title_save');
      this.descLocation = $r('app.string.location_local_desc_save');
      this.descWebDav = $r('app.string.location_webdav_desc_save');
    } else {
      this.titleMsg = $r('app.string.location_title_select');
      this.descLocation = $r('app.string.location_local_desc_select');
      this.descWebDav = $r('app.string.location_webdav_desc_select');
    }
  }

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

        Text(this.titleMsg)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)

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

            OpenMethodButton({
              icon: $r('app.media.ic_file'),
              title: $r('app.string.local_file_button_title'),
              description: this.descLocation,
              onClickEvent: () => {
                this.router.pushUrl({ url: 'pages/open/LocalFile' })
              }
            })

            OpenMethodButton({
              icon: $r("app.media.ic_webdav"),
              title: $r('app.string.webdav_button_title'),
              description: this.descWebDav,
              onClickEvent: () => {
                this.router.pushUrl({ url: 'pages/open/WebDAV' })
              }
            })

          }
          .backgroundColor($r("app.color.card_bg"))
          .margin({ top: 12 })
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP,SafeAreaEdge.BOTTOM])
  }
}

/**
 * 打开方式类型
 */
export enum LocationMode {
  SAVE = "SAVE",
  SELECT = "SELECT"
}