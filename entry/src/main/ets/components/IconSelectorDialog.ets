import { IconUtils } from '../common/utils';
import { IconResource } from '../services/TypeDefined';
import { Kdbx } from 'kdbxweb';
import { ImageAddComponent } from './ImageAddComponent';

@CustomDialog
export struct IconSelectorDialog {
  @State selectedIconId: number | string = -1;
  @State icons: IconResource[] = [];
  public onIconSelected: (iconId: number | string) => void = () => {
  };
  public database: Kdbx | null = null; // 数据库实例
  // 每行显示的图标数量
  private readonly columnsPerRow: number = 5;
  // 图标大小
  private readonly iconSize: number = 40;
  // 图标间距
  private readonly iconGap: number = 16;
  private controller: CustomDialogController;

  aboutToAppear() {
    // 获取所有图标
    this.icons = IconUtils.getAllIcons();
  }

  /**
   * 刷新图标列表
   */
  private refreshIcons() {
    this.icons = IconUtils.getAllIcons(false);
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r("app.string.select_icon"))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)

        Blank()

        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .onClick(() => {
          this.controller.close();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r("app.color.bg_primary"))
      .borderRadius({ topLeft: 16, topRight: 16 })

      // 图标网格
      Grid() {
        ForEach(this.icons.length > 0 ? this.icons : IconUtils.getAllIcons(), (icon: IconResource) => {
          GridItem() {
            Column() {
              Image(icon.resource)
                .width(this.iconSize)
                .height(this.iconSize)
                .objectFit(ImageFit.Contain)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(8)
            .backgroundColor(this.selectedIconId === icon.id ? '#E8F3FF' : 'transparent')
            .border(this.selectedIconId === icon.id ? {
              width: 2,
              color: '#007DFF',
              style: BorderStyle.Solid
            } : {
              width: 0
            })
            .onClick(() => {
              this.selectedIconId = icon.id;
              this.controller.close();
              if (this.onIconSelected) {
                this.onIconSelected(icon.id);
              }
            })
          }
        })

        GridItem() {
          // 图片添加组件
          Button() {
            ImageAddComponent({
              onSuccess: () => {
                this.refreshIcons();
              }
            })
              .width(this.iconSize)
              .height(this.iconSize)
          }
          .width(this.iconSize)
          .height(this.iconSize)
          .borderRadius(this.iconSize / 2)
          .backgroundColor($r("app.color.button_bg_blue"))
        }
      }
      .height('90%')
      .columnsTemplate('1fr '.repeat(this.columnsPerRow))
      .columnsGap(this.iconGap)
      .rowsGap(this.iconGap)
      .padding({ left: 24, right: 24, bottom: 16 })
    }
    .width('100%')
    .height('85%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
  }
}
