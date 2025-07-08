import IconUtils from '../common/utils/IconUtils';
import { IconResource } from '../services/TypeDefined';

@CustomDialog
export struct IconSelectorDialog {
  @State selectedIconId: number = -1;
  private controller: CustomDialogController;
  private onIconSelected: (iconId: number) => void = () => {};
  
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
      .columnsTemplate('1fr '.repeat(this.columnsPerRow))
      .columnsGap(this.iconGap)
      .rowsGap(this.iconGap)
      .padding({ left: 16, right: 16, bottom: 16 })
      
      // 底部按钮
      Row() {
        Button('取消')
          .onClick(() => {
            this.controller.close();
          })
          .backgroundColor(Color.Gray)
          .fontColor(Color.White)
          .width('45%')
          .height(40)
          .borderRadius(20)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 24 })
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.background_primary'))
    }
    .width('100%')
    .backgroundColor($r('app.color.background_primary'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}

// 保留原来的组件，用于在其他组件中内嵌使用
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
