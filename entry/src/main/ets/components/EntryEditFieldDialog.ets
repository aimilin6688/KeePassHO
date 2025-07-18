import {CustomField} from "../services/TypeDefined";

/**
 * 条目编辑字段对话框组件
 */
@CustomDialog
export struct EntryEditFieldDialog {
  @Link isEditing: boolean;
  @Link fieldKey: string;
  @Link fieldValue: string;
  @Link isProtected: boolean;

  public onConfirm: (customField: CustomField) => void = ()=>{};
  private controller: CustomDialogController;

  @State tempKey: string = '';
  @State tempValue: string = '';
  @State tempProtected: boolean = false;
  @State showPassword: boolean = false;

  private promptAction = this.getUIContext().getPromptAction();

  aboutToAppear() {
    // 初始化临时变量
    this.tempKey = this.fieldKey;
    this.tempValue = this.fieldValue;
    this.tempProtected = this.isProtected;
  }

  /**
   * 确认操作
   */
  private confirm() {
    // 验证字段名称
    if (!this.tempKey || this.tempKey.trim() === '') {
      this.promptAction.showToast({
        message: '字段名称不能为空',
        duration: 2000
      });
      return;
    }

    // 更新外部变量
    this.fieldKey = this.tempKey;
    this.fieldValue = this.tempValue;
    this.isProtected = this.tempProtected;

    // 调用确认回调
    this.onConfirm({key:this.fieldKey, value:this.fieldValue, isProtected:this.isProtected});

    // 关闭对话框
    this.controller.close();
  }

  /**
   * 取消操作
   */
  private cancel() {
    this.controller.close();
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text(this.isEditing ? '编辑自定义字段' : '添加自定义字段')
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
          this.cancel();
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .borderRadius({ topLeft: 16, topRight: 16 })

      // 字段名称
      Column() {
        Text('字段名称')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 8 })
          .alignSelf(ItemAlign.Start)

        TextInput({ text: this.tempKey, placeholder: '请输入字段名称' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .borderRadius(8)
          .margin({ bottom: 16 })
          .onChange((value) => {
            this.tempKey = value;
          })
      }
      .width('100%')

      // 字段值
      Column() {
        Text('字段值')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 8 })
          .alignSelf(ItemAlign.Start)

        Row() {
          TextInput({
            text: this.tempValue,
            placeholder: '请输入字段值',
          })
            .type(this.tempProtected && !this.showPassword ? InputType.Password : InputType.Normal)
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(8)
            .onChange((value) => {
              this.tempValue = value;
            })
        }
        .width('100%')
        .height(48)
        .margin({ bottom: 16 })
      }
      .width('100%')

      // 保护字段选项
      Row() {
        Checkbox({ name: 'protectField', group: 'fieldOptions' })
          .select(this.tempProtected)
          .onChange((value) => {
            this.tempProtected = value;
          })

        Text('保护字段值')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
          .onClick(() => {
            this.tempProtected = !this.tempProtected;
          })
      }
      .width('100%')
      .margin({ bottom: 24 })

      // 按钮
      Row() {
        Button('取消')
          .width('45%')
          .height(40)
          .fontSize(16)
          .backgroundColor(Color.Gray)
          .fontColor(Color.White)
          .borderRadius(16)
          .onClick(() => {
            this.cancel();
          })

        Button('确定')
          .width('45%')
          .height(40)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.button_blue'))
          .borderRadius(16)
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
      .padding({ top: 16})
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
    .padding({ left: 24, right: 24, bottom: 16 })
  }
}
