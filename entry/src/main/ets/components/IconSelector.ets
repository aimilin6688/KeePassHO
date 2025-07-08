import IconUtils from '../common/utils/IconUtils';
import { IconResource } from '../services/TypeDefined';

@Component
export struct IconSelector {
  @Link selectedIconId: number;
  private onIconSelected?: (iconId: number) => void;

  // 每行显示的图标数量
  private readonly columnsPerRow: number = 5;

  // 图标大小
  private readonly iconSize: number = 40;

  // 图标间距
  private readonly iconGap: number = 16;

  build() {
    Column() {
      Text('选择图标')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 16, bottom: 16 })

      Grid() {
        ForEach(IconUtils.getAllIcons(), (icon:IconResource) => {
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
              if (this.onIconSelected) {
                this.onIconSelected(icon.id);
              }
            })
          }
        })
      }
      .columnsTemplate('1fr '.repeat(this.columnsPerRow))
      .columnsGap(this.iconGap)
      .rowsGap(this.iconGap)
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
    .backgroundColor(Color.White)
  }
}
