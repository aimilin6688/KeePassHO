import { Router } from '@kit.ArkUI';
import ResourceManager from '../../common/utils/ResourceManager';
import { OpenMethodButton } from '../../components/OpenMethodButton';

@Entry
@Component
struct SelectLocation {
  private router: Router = this.getUIContext().getRouter();
  @State typeMsg: string = "";

  onPageShow(): void {
    const params = this.router.getParams() as Record<string, string>;
    this.typeMsg = this.createTypeMsg(params?.type);
  }

  // 类型提示文本
  private createTypeMsg(type: string): string {
    if (type === LocationMode.SAVE) {
      return ResourceManager.getString($r("app.string.location_save"));
    } else if (type === LocationMode.CREATE) {
      return ResourceManager.getString($r('app.string.location_create'));
    }
    return ResourceManager.getString($r('app.string.location_select'));
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

        Text($r('app.string.location_title', this.typeMsg))
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
            Text($r('app.string.select_open_method_prompt', this.typeMsg))
              .fontSize(14)
              .opacity(0.6)
              .padding({ left: 16, top: 16, bottom: 8 })
              .fontColor($r('app.color.text_primary'))
              .alignSelf(ItemAlign.Start)

            OpenMethodButton(
              $r('app.media.ic_file'),
              $r('app.string.local_file_button_title'),
              $r('app.string.local_file_button_description', this.typeMsg),
              () => {
                this.router.pushUrl({ url: 'pages/open/LocalFile' })
              }
            )

            OpenMethodButton(
              $r("app.media.ic_webdav"),
              $r('app.string.webdav_button_title'),
              $r('app.string.webdav_button_description', this.typeMsg),
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

/**
 * 打开方式类型
 */
export enum LocationMode {
  SAVE = "SAVE",
  CREATE = "CREATE"
}