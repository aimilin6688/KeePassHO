import { Router } from '@kit.ArkUI';
import { OpenMethodButton } from '../../components/OpenMethodButton';
import { LocationParam } from '../../services/beans/LocationParam';
import { FileStorage, PageConfig } from '../../storage';

@Entry
@Component
struct SelectLocation {
  private router: Router = this.getUIContext().getRouter();
  @State titleMsg: ResourceStr = '';
  private pageConfigs: PageConfig[] = [];

  aboutToAppear(): void {
    this.initMsg();
  }

  // 类型提示文本
  private initMsg(): void {
    if (LocationParam.isSaveMode()) {
      this.titleMsg = $r('app.string.location_title_save');
    } else {
      this.titleMsg = $r('app.string.location_title_select');
    }
    this.pageConfigs = FileStorage.getAllPageConfig();
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

            ForEach(this.pageConfigs, (config: PageConfig, index) => {
              OpenMethodButton({
                icon: config.icon,
                title: config.title,
                description: LocationParam.isSaveMode() ? config.saveDesc : config.selectDesc,
                onClickEvent: () => {
                  this.router.pushUrl({ url: config.pageUrl })
                }
              })
            }, (item: PageConfig) => item.pageUrl)
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

/**
 * 打开方式类型
 */
export enum LocationMode {
  SAVE = "SAVE",
  SELECT = "SELECT"
}