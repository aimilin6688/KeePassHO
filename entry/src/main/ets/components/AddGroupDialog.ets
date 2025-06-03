@CustomDialog
export struct AddGroupDialog {
  @Link showDialog: boolean
  @Link newGroupName: string
  @Link editingGroupIndex: number
  controller: CustomDialogController
  @Prop onConfirm: () => void

  aboutToAppear() {
    if (!this.controller) {
      console.error('AddGroupDialog: controller is required')
    }
  }

  build() {
    Column() {
      Text(this.editingGroupIndex === -1 ? '添加分组' : '编辑分组')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 10, bottom: 20 })

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
            this.showDialog = false
            this.newGroupName = ''
          })
          .backgroundColor(0xffffff)
          .fontColor(Color.Black)

        Button('确定')
          .width(120)
          .enabled(this.newGroupName.length > 0)
          .onClick(() => {
            if (this.newGroupName.trim()) {
              this.onConfirm()
              this.controller.close()
              this.showDialog = false
            }
          })
          .backgroundColor(this.newGroupName.length > 0 ? 0x317aff : 0xcccccc)
          .fontColor(Color.White)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ bottom: 20 })
    }
    .width('90%')
    .backgroundColor(Color.White)
    .borderRadius(10)
    .padding(20)
  }
}
