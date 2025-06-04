@CustomDialog
export struct AddGroupDialog {
  @Link newGroupName: string
  @Link editingGroupIndex: number
  controller: CustomDialogController
  onConfirm: () => void = () => {
  }
  onCancel: () => void = () => {
  }

  build() {
    Column() {
      Text(this.editingGroupIndex === -1 ? '添加分组' : '编辑分组')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 10, bottom: 20 })
        .backgroundColor($r('app.color.background_primary'))

      TextInput({
        placeholder: '请输入分组名称',
        text: this.newGroupName
      })
        .height(40)
        .width('90%')
        .margin({ bottom: 20 })
        .onChange((value: string) => {
          this.newGroupName = value.trim()
        })

      Row() {
        Button('取消')
          .width(120)
          .onClick(() => {
            this.controller.close()
            this.newGroupName = ''
            if (this.onCancel) {
              this.onCancel()
            }
          })
          .backgroundColor(Color.Gray)
          .fontColor(Color.White)

        Button('确定')
          .width(120)
          .enabled(this.newGroupName.trim().length > 0)
          .onClick(() => {
            this.controller.close()
            if (this.onConfirm) {
              this.onConfirm()
            }
          })
          .backgroundColor(this.newGroupName.trim().length > 0 ? $r('app.color.accent') : $r('app.color.button_disabled_background'))
          .fontColor(Color.White)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ bottom: 20 })
      .backgroundColor($r('app.color.background_primary'))
    }
    .width('100%')
    .backgroundColor($r('app.color.background_primary'))
    .borderRadius(10)
  }
}
