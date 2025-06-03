import { ThemeConstants, ThemeMode } from '../common/constants/ThemeConstants';
import { SettingsService } from '../services/SettingsService';
import router from '@ohos.router';
import { ConfigurationConstant, Configuration } from '@kit.AbilityKit';

@Entry
@Component
struct Settings {
  @State isGridView: boolean = false
  @State sortBy: string = 'name' // 'name' | 'time'
  @State currentThemeMode: ThemeMode = ThemeMode.SYSTEM;
  @StorageProp('currentColorMode') @Watch('onColorModeChange') currentSystemMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  private settingsService: SettingsService = SettingsService.getInstance();

  onColorModeChange(): void {
    if (this.currentThemeMode === ThemeMode.SYSTEM) {
      this.applySystemTheme();
    }
  }

  applySystemTheme(): void {
    // 系统主题变化时应用对应的主题
    if (this.currentSystemMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      // 应用深色主题
      this.applyThemeMode(ThemeMode.DARK);
    } else {
      // 应用浅色主题
      this.applyThemeMode(ThemeMode.LIGHT);
    }
  }

  async applyThemeMode(themMode: ThemeMode): Promise<void>{
    await this.settingsService.setThemeMode(themMode);
    this.currentThemeMode = themMode;
  }

  aboutToAppear() {
    this.loadSettings();
  }

  async loadSettings() {
    this.currentThemeMode = await this.settingsService.getThemeMode();
  }

  build() {
    WithTheme({ colorMode: this.currentThemeMode === ThemeMode.SYSTEM 
      ? (this.currentSystemMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ?
        ThemeColorMode.DARK: ThemeColorMode.LIGHT)
      : (this.currentThemeMode === ThemeMode.DARK ? ThemeColorMode.DARK: ThemeColorMode.LIGHT)
    }) {
      Column() {
        // 顶部导航栏
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .margin({ left: 12 })
            .onClick(() => router.back())
          Text('设置')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .margin({ left: 12 })
        }
        .width('100%')
        .height(56)
        .backgroundColor($r('app.color.card_background'))

        // 设置列表
        List() {
          // 主题设置
          ListItem() {
            Column() {
              Row() {
                Text('主题')
                  .fontSize(16)
                Blank()
                Select(ThemeConstants.THEME_OPTIONS)
                  .value(this.currentThemeMode)
                  .font({ size: 16 })
                  .selectedOptionFont({ size: 16 })
                  .optionFont({ size: 16 })
                  .onSelect(async (index: number) => {
                    const selectedMode = ThemeConstants.THEME_OPTIONS[index].value;
                    this.applyThemeMode(selectedMode)
                  })
              }
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
            }
            .backgroundColor($r('app.color.card_background'))
          }

          // 网格视图
          ListItem() {
            Row() {
              Text('网格视图')
                .fontSize(16)
                .flexGrow(1)
              Toggle({ type: ToggleType.Switch, isOn: this.isGridView })
                .onChange((isOn: boolean) => {
                  this.isGridView = isOn
                  this.settingsService.setGridView(isOn);
                })
            }
            .width('100%')
            .padding(16)
          }
          .backgroundColor($r('app.color.card_background'))

          // 排序方式
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
                      this.settingsService.setSortBy('name');
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
                      this.settingsService.setSortBy('time');
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
          .backgroundColor($r('app.color.card_background'))
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 12 })
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
          startMargin: 16,
          endMargin: 16
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_primary'))
    }
  }
}