import { CommonUtils, NavigationManager } from '../../common/utils';
import { OpenMethodButton } from '../../components/OpenMethodButton';
import { LocationParam } from '../../services/beans/LocationParam';
import { FileStorage, PageConfig } from '../../storage';
import { PageConstants } from '../../common/constants/PageConstants';

// SelectLocation页面的Builder函数
@Builder
export function SelectLocationBuilder(name: string, param: Object): void {
  NavDestination() {
    SelectLocationContent()
  }
  .title($r('app.string.location_title_select'))
  .backgroundColor($r('app.color.bg_primary'))
}

@Component
struct SelectLocationContent {
  private navManager = NavigationManager.getInstance();
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
                componentId: config.id === undefined ? '' : config.id,
                onClickEvent: () => {
                  const pageName = config.pageUrl.split('/').pop() || config.pageUrl;
                  this.navManager.getNavPathStack()?.pushPathByName(pageName, null);
                }
              })
            }, (item: PageConfig) => item.pageUrl)
          }
          .backgroundColor($r("app.color.card_bg"))
          .margin({ top: 4 })
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