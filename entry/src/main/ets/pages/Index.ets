import { AddGroupDialog } from '../components/AddGroupDialog';
import router from '@ohos.router';
import ThemeManager from '../common/utils/ThemeManager';
import { KdbxGroup, KdbxUuid, KdbxTimes } from 'kdbxweb'

@Entry
@Component
struct Index {
  @State newGroupName: string | undefined = ""
  @State editingGroupIndex: number = -1
  @State data: Array<KdbxGroup> = [
    {
      uuid: KdbxUuid.random(),
      name: '组1',
      icon: 11,
      times: {
        creationTime: new Date(),
        lastModTime: new Date(),
      } as KdbxTimes
    } as KdbxGroup,
    {
      uuid:KdbxUuid.random(),
      name: '组2',
      icon: 12,
      times: {
        creationTime: new Date(),
        lastModTime: new Date(),
      } as KdbxTimes
    } as KdbxGroup
  ]
  dialogController: CustomDialogController = new CustomDialogController({
    builder: AddGroupDialog({
      newGroupName: this.newGroupName,
      editingGroupIndex: this.editingGroupIndex,
      onConfirm: (): void => this.handleAddGroup(),
      onCancel: (): void => {
        this.newGroupName = "";
        this.editingGroupIndex = -1;
      }
    }),
    alignment: DialogAlignment.Default,
    autoCancel: true
  })

  @Builder
  SwipeActionButtons(index: number) {
    Row() {
      Button("编辑", { type: ButtonType.Normal })
        .width(80)
        .height(60)
        .backgroundColor($r('app.color.accent'))
        .fontColor(Color.White)
        .fontSize(14)
        .onClick(() => {
          this.editingGroupIndex = index
          this.newGroupName = this.data[index].name;
          this.dialogController.open()
        })

      Button("删除", { type: ButtonType.Normal })
        .width(80)
        .height(60)
        .backgroundColor($r('app.color.danger'))
        .fontColor(Color.White)
        .fontSize(14)
        .onClick(() => {
          AlertDialog.show({
            title: '确认删除',
            message: '确定要删除这个分组吗？',
            primaryButton: {
              value: '取消',
              action: () => {
              }
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
    if (this.newGroupName === undefined ||  !this.newGroupName.trim()) {
      return
    }

    if (this.editingGroupIndex >= 0 && this.editingGroupIndex < this.data.length) {
      let oldData = this.data[this.editingGroupIndex]
      // 编辑现有分组
      this.data.splice(this.editingGroupIndex, 1, {
        'uuid': oldData.uuid,
        'name': this.newGroupName.trim(),
        'icon': oldData.icon,
        'times': {
          creationTime: oldData.times.creationTime,
          lastModTime: new Date(),
        } as KdbxTimes
      } as KdbxGroup)
    } else {
      // 添加新分组
      this.data.push({
        uuid: KdbxUuid.random(),
        name: this.newGroupName.trim(),
        'times': {
          creationTime: new Date(),
          lastModTime: new Date(),
        } as KdbxTimes
      } as KdbxGroup)
    }

    // 重置状态
    this.newGroupName = ""
    this.editingGroupIndex = -1
  }

  aboutToAppear() {
    // 监听主题变化
    ThemeManager.getInstance().addThemeChangeListener(() => {
      this.onThemeChanged();
    });
  }

  aboutToDisappear() {
    // 移除主题变化监听
    ThemeManager.getInstance().removeThemeChangeListenerAll();
  }

  onThemeChanged() {
    // 强制组件刷新以应用新主题
    this.data = [...this.data];
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Text('KeePassHO')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .margin({ left: 16 })
            .fontColor($r('app.color.text_primary'))
          Blank()
          Image($r('app.media.ic_settings'))
            .width(24)
            .height(24)
            .margin({ right: 16 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/Settings' })
            })
        }
        .width('100%')
        .height(56)
        .backgroundColor($r('app.color.card_background'))

        List({ space: 8 }) {
          ForEach(this.data, (itemGroup: KdbxGroup, index: number) => {
            ListItem() {
              Row() {
                Image(itemGroup.icon)
                  .width(40)
                  .height(40)
                  .margin(10)
                Text(itemGroup.name)
                  .fontSize(20)
                  .textAlign(TextAlign.Start)
                  .flexGrow(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(24)
                  .height(24)
                  .margin({ right: 10 })
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .height(60)
              .borderRadius(8)
              .backgroundColor($r('app.color.card_background'))
              .padding({ left: 10, right: 10 })
            }
            .swipeAction({
              end: {
                builder: this.SwipeActionButtons(index)
              }
            })
          }, (item: KdbxGroup, index: number) => `${index}-${item.name}`)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_primary'))
        .padding({ left: 12, right: 12, top: 12 })
        .scrollBar(BarState.Auto)
      }
      .width('100%')

      Button() {
        Image($r('app.media.ic_add'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
      }
      .width(60)
      .height(60)
      .borderRadius(30)
      .backgroundColor($r('app.color.accent'))
      .position({ right: 12, bottom: 12 })
      .onClick(() => {
        this.editingGroupIndex = -1
        this.newGroupName = ""
        this.dialogController.open()
      })
    }
    .width('100%')
    .height('100%')
  }
}