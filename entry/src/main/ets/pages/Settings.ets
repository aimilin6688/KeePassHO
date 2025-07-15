import { ThemeConstants, ThemeMode } from '../common/constants/ThemeConstants';
import { SettingsService } from '../services/SettingsService';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { router, Router } from '@kit.ArkUI';
import { SortConstants, SortMode } from '../common/constants/SortConstants';

@Entry
@Component
struct Settings {
  @State sortBy: SortMode = SortMode.DEFAULT
  @State currentThemeMode: ThemeMode = ThemeMode.SYSTEM;


  @StorageProp('currentColorMode') @Watch('onColorModeChange') currentSystemMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  private settingsService: SettingsService = SettingsService.getInstance();
  private router: Router = this.getUIContext().getRouter();

  onColorModeChange(): void {
    // 系统主题变化时应用对应的主题
    if (this.currentThemeMode === ThemeMode.SYSTEM) {
      if (this.currentSystemMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
        // 应用深色主题
        this.applyThemeMode(ThemeMode.DARK);
      } else {
        // 应用浅色主题
        this.applyThemeMode(ThemeMode.LIGHT);
      }
    }
  }

  async applyThemeMode(themMode: ThemeMode): Promise<void> {
    this.currentThemeMode = themMode;
    await this.settingsService.setThemeMode(themMode);
  }

  async aboutToAppear() {
    this.currentThemeMode = await this.settingsService.getThemeMode();
    this.sortBy = await this.settingsService.getSortBy();
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .margin({ left: 12 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => this.router.back())
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
        ListItemGroup() {
          // 主题设置
          ListItem() {
            Column() {
              Row() {
                Text('主题')
                  .fontSize(16)
                Blank()
                Select(ThemeConstants.THEME_OPTIONS)
                  .value(ThemeConstants.getThemeOptionByType(this.currentThemeMode))
                  .font({ size: 16 })
                  .selectedOptionFont({ size: 16 })
                  .optionFont({ size: 16 })
                  .backgroundColor($r('app.color.card_background'))
                  .onSelect(async (index: number) => {
                    const selectedMode = ThemeConstants.THEME_OPTIONS[index].type;
                    this.applyThemeMode(selectedMode)
                  })
              }
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
            }
            .backgroundColor($r('app.color.card_background'))
          }

          // 排序方式
          ListItem() {
            Row() {
              Text('排序方式')
                .fontSize(16)
              Blank()
              Select(SortConstants.SORT_OPTIONS)
                .font({ size: 16 })
                .value(SortConstants.getSortOptionByType(this.sortBy))
                .selectedOptionFont({ size: 16 })
                .optionFont({ size: 16 })
                .backgroundColor($r('app.color.card_background'))
                .onSelect((index: number) => {
                  this.sortBy = SortConstants.SORT_OPTIONS[index].type;
                  this.settingsService.setSortBy(SortConstants.SORT_OPTIONS[index].type);
                })
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
          }
          .backgroundColor($r('app.color.card_background'))
        }

        ListItemGroup() {
          // 更换数据库
          ListItem() {
            Row() {
              Text('更换数据库')
                .fontSize(16)
                .flexGrow(1)
              Image($r('app.media.ic_arrow_right'))
                .width(24)
                .height(24)
                .fillColor($r('app.color.text_primary'))
            }
            .width('100%')
            .padding(16)
          }
          .backgroundColor($r('app.color.card_background'))
          .onClick(()=>{
            this.router.pushUrl({
              url: 'pages/open/OpenDatabase'
            }, router.RouterMode.Single);
          })

          // 最近打开
          ListItem() {
            Row() {
              Text('最近打开')
                .fontSize(16)
                .flexGrow(1)
              Image($r('app.media.ic_arrow_right'))
                .width(24)
                .height(24)
                .fillColor($r('app.color.text_primary'))
            }
            .width('100%')
            .padding(16)
          }
          .backgroundColor($r('app.color.card_background'))
          .onClick(()=>{
            this.router.pushUrl({
              url: 'pages/RecentFiles'
            }, router.RouterMode.Single);
          })
        }

        ListItemGroup() {
          // 关于
          ListItem() {
            Row() {
              Text('关于')
                .fontSize(16)
                .flexGrow(1)
              Image($r('app.media.ic_arrow_right'))
                .width(24)
                .height(24)
                .fillColor($r('app.color.text_primary'))
            }
            .width('100%')
            .padding(16)
          }
          .backgroundColor($r('app.color.card_background'))
          .onClick(()=>{
            this.router.pushUrl({
              url: 'pages/About'
            }, router.RouterMode.Single);
          })
        }
      }
      .width('100%')
      .height('auto')
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