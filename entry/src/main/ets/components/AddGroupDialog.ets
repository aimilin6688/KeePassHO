import IconUtils from '../common/utils/IconUtils';
import { Icons } from '../services/TypeDefined';
import { IconSelectorDialog } from './IconSelector';

@CustomDialog
export struct AddGroupDialog {
  @Link newGroupName: string
  @Link editingGroupIndex: number
  @State selectedIconId: number = Icons.Folder;

  private iconSelectorDialogController: CustomDialogController = new CustomDialogController({
    builder: IconSelectorDialog({
      selectedIconId: this.selectedIconId,
      onIconSelected: (iconId: number) => {
        this.selectedIconId = iconId;
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });
  
  controller: CustomDialogController
  onConfirm: (iconId: number) => void = () => {
  }
  onCancel: () => void = () => {
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text(this.editingGroupIndex === -1 ? '添加分组' : '编辑分组')
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
          this.controller.close()
          this.newGroupName = ''
          if (this.onCancel) {
            this.onCancel()
          }
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background_primary'))
      
      // 分组信息输入区域
      Column() {
        // 图标选择
        Row() {
          Image(IconUtils.getIconResourcePath(this.selectedIconId))
            .width(40)
            .height(40)
            .objectFit(ImageFit.Contain)
            .margin({ right: 16 })
          
          Column() {
            Text('图标')
              .fontSize(16)
              .fontColor('#333333')
            
            Text('点击选择图标')
              .fontSize(14)
              .fontColor('#999999')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          
          Blank()
        }
        .width('100%')
        .height(72)
        .padding({ left: 24, right: 24 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.background_primary'))
        .onClick(() => {
          // 打开独立的图标选择弹框
          this.iconSelectorDialogController = new CustomDialogController({
            builder: IconSelectorDialog({
              selectedIconId: this.selectedIconId,
              onIconSelected: (iconId: number) => {
                this.selectedIconId = iconId;
              }
            }),
            alignment: DialogAlignment.Bottom,
            customStyle: true,
            autoCancel: false
          });
          this.iconSelectorDialogController.open();
        })
        
        Divider()
          .strokeWidth(1)
          .color('#EEEEEE')
          .margin({ left: 24, right: 24 })
        
        // 分组名称输入
        TextInput({
          placeholder: '请输入分组名称',
          text: this.newGroupName
        })
          .width('100%')
          .height(56)
          .padding({ left: 24, right: 24 })
          .placeholderColor('#999999')
          .backgroundColor('transparent')
          .onChange((value: string) => {
            this.newGroupName = value.trim()
          })
        
        Divider()
          .strokeWidth(1)
          .color('#EEEEEE')
          .margin({ left: 24, right: 24 })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_primary'))
      
      // 底部按钮
      Row() {
        Button('取消')
          .onClick(() => {
            this.controller.close()
            this.newGroupName = ''
            if (this.onCancel) {
              this.onCancel()
            }
          })
          .backgroundColor(Color.Gray)
          .fontColor(Color.White)
          .width('45%')
          .height(40)
          .borderRadius(20)
        
        Button('确定')
          .enabled(this.newGroupName.trim().length > 0)
          .onClick(() => {
            this.controller.close()
            if (this.onConfirm) {
              this.onConfirm(this.selectedIconId)
            }
          })
          .backgroundColor(this.newGroupName.trim().length > 0 ? $r('app.color.accent') : $r('app.color.button_disabled_background'))
          .fontColor(Color.White)
          .width('45%')
          .height(40)
          .borderRadius(20)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 24 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor($r('app.color.background_primary'))
    }
    .width('100%')
    .backgroundColor($r('app.color.background_primary'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
