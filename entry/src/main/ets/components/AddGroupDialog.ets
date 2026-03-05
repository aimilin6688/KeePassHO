import { IconUtils } from '../common/utils';
import { Icons } from '../services/TypeDefined';
import { IconSelectorDialog } from './IconSelectorDialog';
import { ColorEditDialog, ColorPickerResult } from './ColorPickerDialog';

@CustomDialog
export struct AddGroupDialog {
  @Link newGroupName: string
  @Link editingGroupIndex: number
  @State selectedIconId: number | string = Icons.Folder;
  @State fgColor: string | undefined = undefined;
  @State bgColor: string | undefined = undefined;
  
  // 初始颜色值
  public initialFgColor: string | undefined = undefined;
  public initialBgColor: string | undefined = undefined;
  
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
  
  colorPickerController: CustomDialogController = new CustomDialogController({
    builder: ColorEditDialog({
      initialFgColor: this.fgColor,
      initialBgColor: this.bgColor,
      onConfirm: (result: ColorPickerResult) => {
        this.fgColor = result.foregroundColor;
        this.bgColor = result.backgroundColor;
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });
  
  controller: CustomDialogController
  onConfirm: (iconId: number | string, fgColor: string | undefined, bgColor: string | undefined) => void = () => {
  }
  onCancel: () => void = () => {
  }

  aboutToAppear(): void {
    this.fgColor = this.initialFgColor;
    this.bgColor = this.initialBgColor;
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
        // 图标和颜色选择
        Row() {
          // 图标选择按钮
          Button() {
            Image(IconUtils.getIconResourcePath(this.selectedIconId))
              .width(32)
              .height(32)
              .objectFit(ImageFit.Contain)
          }
          .width(56)
          .height(56)
          .margin({ right: 12 })
          .borderRadius(12)
          .backgroundColor($r("app.color.card_bg"))
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

          // 颜色选择按钮
          Button() {
            Image($r('app.media.ic_color'))
              .width(32)
              .height(32)
              .fillColor(this.fgColor || $r('app.color.text_primary'))
          }
          .width(56)
          .height(56)
          .borderRadius(12)
          .backgroundColor(this.bgColor || $r("app.color.card_bg"))
          .onClick(() => {
            // 每次打开时重新创建对话框控制器以获取最新的颜色值
            this.colorPickerController = new CustomDialogController({
              builder: ColorEditDialog({
                initialFgColor: this.fgColor,
                initialBgColor: this.bgColor,
                onConfirm: (result: ColorPickerResult) => {
                  this.fgColor = result.foregroundColor;
                  this.bgColor = result.backgroundColor;
                }
              }),
              alignment: DialogAlignment.Bottom,
              customStyle: true,
              autoCancel: false
            });
            this.colorPickerController.open();
          })

          Blank()
        }
        .width('100%')
        .height(80)
        .padding({ left: 24, right: 24 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r("app.color.bg_primary"))

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
          .borderRadius(20)

        Button($r("app.string.confirm_button_text"))
          .enabled(this.newGroupName.trim().length > 0)
          .onClick(() => {
            this.controller.close()
            if (this.onConfirm) {
              this.onConfirm(this.selectedIconId, this.fgColor, this.bgColor)
            }
          })
          .backgroundColor(this.newGroupName.trim().length > 0 ? $r("app.color.button_bg_blue") : $r("app.color.button_bg_disabled"))
          .fontColor($r('app.color.button_text'))
          .width('45%')
          .height(40)
          .borderRadius(20)
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
