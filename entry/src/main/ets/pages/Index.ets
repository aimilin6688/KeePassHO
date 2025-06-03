@Entry
@Component
struct GroupManager {
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

  build() {
    Column() {
      List() {
        ForEach(this.data, (itemGroup: ItemGroup) => {
          ListItem(){
            Row() {
              Image(itemGroup.icon)
                .width(40)
                .height(40)
                .margin(10)
              Text(itemGroup.title).fontSize(20).textAlign(TextAlign.Start).width(100)
              Image($r('app.media.startIcon')) // 使用已存在的图标资源
                .width(20)
                .height(20)
                .margin({ left: 10 })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
        }, (item: ItemGroup) => JSON.stringify(item))
      }
      Stack({ alignContent: Alignment.BottomEnd }) {
        Button() {
          Image($r('app.media.foreground')) // 使用现有图标资源
            .width(24)
            .height(24)
        }
        .width(60)
        .height(60)
        .margin({ right: 20, bottom: 20 })
        .onClick(() => {
          this.showDialog = true
          this.editingGroupIndex = -1
          this.newGroupName = ""
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