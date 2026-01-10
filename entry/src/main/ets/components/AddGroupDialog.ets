import { IconUtils } from '../common/utils';
import { Icons } from '../services/TypeDefined';
import { IconSelectorDialog } from './IconSelectorDialog';

@CustomDialog
export struct AddGroupDialog {
  @Link newGroupName: string
  @Link editingGroupIndex: number
  @State selectedIconId: number | string = Icons.Folder;
  private iconSelectorDialogController: CustomDialogController = new CustomDialogController({
    builder: IconSelectorDialog({
      selectedIconId: this.selectedIconId,
      onIconSelected: (iconId: number | string) => {
        this.selectedIconId = iconId;
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });
  controller: CustomDialogController
  onConfirm: (iconId: number | string) => void = () => {
  }
  onCancel: () => void = () => {
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text(this.editingGroupIndex === -1 ? $r('app.string.add_group_button') : $r("app.string.edit_group"))
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
      .backgroundColor($r("app.color.bg_primary"))
      .borderRadius({ topLeft: 16, topRight: 16 })

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
            Text($r("app.string.icon"))
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))

            Text($r("app.string.click_select_icon"))
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
        .backgroundColor($r("app.color.bg_primary"))
        .onClick(() => {
          // 打开独立的图标选择弹框
          this.iconSelectorDialogController = new CustomDialogController({
            builder: IconSelectorDialog({
              selectedIconId: this.selectedIconId,
              onIconSelected: (iconId: number | string) => {
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
          placeholder: $r("app.string.enter_group_name"),
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
      .backgroundColor($r("app.color.bg_primary"))

      // 底部按钮
      Row() {
        Button($r('app.string.cancel_button_text'))
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
          .borderRadius(16)

        Button($r("app.string.confirm_button_text"))
          .enabled(this.newGroupName.trim().length > 0)
          .onClick(() => {
            this.controller.close()
            if (this.onConfirm) {
              this.onConfirm(this.selectedIconId)
            }
          })
          .backgroundColor(this.newGroupName.trim().length > 0 ? $r("app.color.button_bg_blue") : $r("app.color.button_bg_disabled"))
          .fontColor($r('app.color.button_text'))
          .width('45%')
          .height(40)
          .borderRadius(16)
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: 16,
        bottom: 30
      })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor($r("app.color.bg_primary"))
    }
    .width('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
