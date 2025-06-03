
@CustomDialog
struct AddGroupDialog {
  @Link showDialog: boolean
  @Link newGroupName: string
  @Link editingGroupIndex: number
  controller: CustomDialogController

  onConfirm(): void {
  }


  build() {
    Column() {
      Text(this.editingGroupIndex >= 0 ? '编辑分组' : '添加分组')
        .fontSize(20)
        .margin({ top: 10, bottom: 20 })
      
      TextInput({ placeholder: '请输入分组名称', text: this.newGroupName })
        .width('90%')
        .height(50)
        .margin({ bottom: 20 })
        .onChange((value: string) => {
          this.newGroupName = value
        })

      Row() {
        Button('取消')
          .width(120)
          .onClick(() => {
            this.showDialog = false
            this.controller.close()
          })
        Button('确定')
          .width(120)
          .onClick(() => {
            if (this.newGroupName.trim()) {
              this.onConfirm()
              this.showDialog = false
              this.controller.close()
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ bottom: 20 })
    }
    .width('90%')
    .backgroundColor(Color.White)
    .borderRadius(10)
  }
}

@Entry
@Component
struct GroupManager {
  dialogController: CustomDialogController = new CustomDialogController({
    builder: AddGroupDialog({
      showDialog: $showDialog,
      newGroupName: $newGroupName,
      editingGroupIndex: $editingGroupIndex
    })
  })
  
  @State data: Array<ItemGroup> = [
    {
      title: '组1',
      icon: $r('app.media.startIcon'),
      list: [
        { title: '项目1-1', icon: $r('app.media.startIcon') },
        { title: '项目1-2', icon: $r('app.media.startIcon') },
        { title: '项目1-3', icon: $r('app.media.startIcon') },
      ]
    },
    {
      title: '组2',
      icon: $r('app.media.startIcon'),
      list: [
        { title: '项目2-1', icon: $r('app.media.startIcon') },
        { title: '项目2-2', icon: $r('app.media.startIcon') },
        { title: '项目2-3', icon: $r('app.media.startIcon') },
      ]
    },
  ]
  @State showDialog: boolean = false
  @State newGroupName: string = ""
  @State editingGroupIndex: number = -1
  
  @Builder
  SwipeActionButtons(index: number) {
    Row() {
      Button("编辑", {type:  ButtonType.Normal})
        .width(80)
        .height(60)
        .backgroundColor('#ff4bb8f5')
        .fontColor(Color.White)
        .fontSize(14)
        .onClick(() => {
          this.editingGroupIndex = index
          this.newGroupName = this.data[index].title
          this.showDialog = true
          this.dialogController.open()
        })
      
      Button("删除", {type:  ButtonType.Normal})
        .width(80)
        .height(60)
        .backgroundColor('#fff17474')
        .fontColor(Color.White)
        .fontSize(14)
        .onClick(() => {
          AlertDialog.show({
            title: '确认删除',
            message: '确定要删除这个分组吗？',
            primaryButton: {
              value: '取消',
              action: () => {}
            },
            secondaryButton: {
              value: '删除',
              action: () => {
                this.data.splice(index, 1)
              }
            }
          })
        })
    }
  }
  
  handleAddGroup() {
    if (this.editingGroupIndex >= 0) {
      // 编辑现有分组
      this.data[this.editingGroupIndex].title = this.newGroupName
    } else {
      // 添加新分组
      this.data.push({
        title: this.newGroupName,
        icon: $r('app.media.ic_add'),
        list: []
      })
    }
    this.newGroupName = ""
    this.editingGroupIndex = -1
  }

  build() {
    Column() {
      List({ space: 8 }) {
        ForEach(this.data, (itemGroup: ItemGroup, index: number) => {
          ListItem(){
            Row() {
              Image(itemGroup.icon)
                .width(40)
                .height(40)
                .margin(10)
              Text(itemGroup.title)
                .fontSize(20)
                .textAlign(TextAlign.Start)
                .flexGrow(1)
              Image($r('app.media.ic_arrow_right'))
                .width(24)
                .height(24)
                .margin({ right: 10 })
            }
            .width('100%')
            .height(60)
            .borderRadius(8)
            .backgroundColor(Color.White)
            .padding({ left: 10, right: 10 })
          }
          .swipeAction({
            end: {
              builder: this.SwipeActionButtons(index)
            }
          })
        }, (item: ItemGroup, index: number) => `${index}-${item.title}`)
      }
      .width('100%')
      .backgroundColor('#F1F3F5')
      .padding({ left: 12, right: 12, top: 12 })
      Stack({ alignContent: Alignment.BottomEnd }) {
        Button() {
          Image($r('app.media.ic_add'))
            .width(24)
            .height(24)
        }
        .width(60)
        .height(60)
        .borderRadius(30)
        .backgroundColor('#007DFF')
        .margin({ right: 20, bottom: 20 })
        .onClick(() => {
          this.showDialog = true
          this.editingGroupIndex = -1
          this.newGroupName = ""
          this.dialogController.open()
        })
      }
      .width('100%')
      .height('100%')


    }
  }
}

interface GroupInfo {
  title: string;
  icon: Resource;
}

interface ItemGroup {
  title: string;
  icon: Resource;
  list: Array<GroupInfo>;
}