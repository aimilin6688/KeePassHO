import IconUtils from '../common/utils/IconUtils';
import { IconResource } from '../services/TypeDefined';

@CustomDialog
export struct IconSelectorDialog {
  @State selectedIconId: number = -1;
  private controller: CustomDialogController;
  public onIconSelected: (iconId: number) => void = () => {};
  
  // 每行显示的图标数量
  private readonly columnsPerRow: number = 5;
  
  // 图标大小
  private readonly iconSize: number = 40;
  
  // 图标间距
  private readonly iconGap: number = 16;
  
  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('选择图标')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
        
        Blank()
        
        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor('#666666')
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
      .backgroundColor($r('app.color.background_primary'))
      
      // 图标网格
      Grid() {
        ForEach(IconUtils.getAllIcons(), (icon: IconResource) => {
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
      }
      .height('90%')
      .columnsTemplate('1fr '.repeat(this.columnsPerRow))
      .columnsGap(this.iconGap)
      .rowsGap(this.iconGap)
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
    .height('80%')
    .backgroundColor($r('app.color.background_primary'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
