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
              Text(itemGroup.title).fontSize(20)
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
          }
        }, (item: ItemGroup) => JSON.stringify(item))
      }
    }
    .width('100%')
    .height('100%')
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