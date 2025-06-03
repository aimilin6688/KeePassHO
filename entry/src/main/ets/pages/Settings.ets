import settingsService from '../services/SettingsService';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct Settings {
  @State isDarkMode: boolean = false
  @State isGridView: boolean = false
  @State sortBy: string = 'name' // 'name' | 'time'

  aboutToAppear() {
    // 初始化设置服务并加载设置
    settingsService.init().then(() => {
      this.loadSettings();
    });
  }

  async loadSettings() {
    this.isDarkMode = await settingsService.isDarkMode();
    this.isGridView = await settingsService.isGridView();
    this.sortBy = await settingsService.getSortBy();
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_arrow_right'))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .rotate({ angle: 180 })
          .onClick(() => {
            router.back()
          })
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Color.White)

      // 设置列表
      List() {
        ListItem() {
          Row() {
            Text('深色模式')
              .fontSize(16)
              .flexGrow(1)
            Toggle({ type: ToggleType.Switch, isOn: this.isDarkMode })
              .onChange((isOn: boolean) => {
                this.isDarkMode = isOn
                settingsService.setDarkMode(isOn);
                // 应用主题变化
                // TODO: 实现主题切换逻辑
              })
          }
          .width('100%')
          .padding(16)
        }
        .backgroundColor(Color.White)

        ListItem() {
          Row() {
            Text('网格视图')
              .fontSize(16)
              .flexGrow(1)
            Toggle({ type: ToggleType.Switch, isOn: this.isGridView })
              .onChange((isOn: boolean) => {
                this.isGridView = isOn
                settingsService.setGridView(isOn);
              })
          }
          .width('100%')
          .padding(16)
        }
        .backgroundColor(Color.White)

        ListItem() {
          Column() {
            Text('排序方式')
              .fontSize(16)
              .width('100%')
              .margin({ bottom: 8 })
            Row() {
              Radio({ value: 'name', group: 'sortBy' })
                .checked(this.sortBy === 'name')
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.sortBy = 'name'
                    settingsService.setSortBy('name');
                  }
                })
              Text('按名称')
                .fontSize(14)
                .margin({ left: 8, right: 16 })
              Radio({ value: 'time', group: 'sortBy' })
                .checked(this.sortBy === 'time')
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.sortBy = 'time'
                    settingsService.setSortBy('time');
                  }
                })
              Text('按时间')
                .fontSize(14)
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .padding(16)
        }
        .backgroundColor(Color.White)
      }
      .width('100%')
      .margin({ top: 12 })
      .divider({
        strokeWidth: 1,
        color: '#F1F3F5'
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}
