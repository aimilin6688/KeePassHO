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
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 12 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => this.router.back())
        Text($r('app.string.Settings_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

      // 设置列表
      List() {
        ListItemGroup() {
          // 主题设置
          ListItem() {
            Column() {
              Row() {
                Text($r('app.string.Settings_theme'))
                  .fontSize(16)
                Blank()
                Select(ThemeConstants.THEME_OPTIONS)
                  .value(ThemeConstants.getThemeOptionByType(this.currentThemeMode))
                  .font({ size: 16 })
                  .selectedOptionFont({ size: 16 })
                  .optionFont({ size: 16 })
                  .backgroundColor($r("app.color.card_bg"))
                  .onSelect(async (index: number) => {
                    const selectedMode = ThemeConstants.THEME_OPTIONS[index].type;
                    this.applyThemeMode(selectedMode)
                  })
              }
              .width('100%')
              .height(48)
              .padding({ left: 16})
            }
          }

          // 排序方式
          ListItem() {
            Row() {
              Text($r('app.string.Settings_sort_method'))
                .fontSize(16)
              Blank()
              Select(SortConstants.SORT_OPTIONS)
                .font({ size: 16 })
                .value(SortConstants.getSortOptionByType(this.sortBy))
                .selectedOptionFont({ size: 16 })
                .optionFont({ size: 16 })
                .backgroundColor($r("app.color.card_bg"))
                .onSelect((index: number) => {
                  this.sortBy = SortConstants.SORT_OPTIONS[index].type;
                  this.settingsService.setSortBy(SortConstants.SORT_OPTIONS[index].type);
                })
            }
            .width('100%')
            .height(48)
            .padding({ left: 16 })
          }
        }
        .backgroundColor($r("app.color.card_bg"))
        .margin({ top: 12, bottom: 12 })
        .borderRadius(12)
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
        })

        // 数据库设置
        ListItemGroup() {
          // 安全设置
          ListItem() {
            Row() {
              Text($r('app.string.Settings_security'))
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
          .onClick(()=>{
            this.router.pushUrl({
              url: 'pages/SettingSecurity'
            }, router.RouterMode.Single);
          })

          // 数据库设置
          ListItem() {
            Row() {
              Text($r('app.string.Settings_database'))
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
          .onClick(()=>{
            this.router.pushUrl({
              url: 'pages/SettingDatabase'
            }, router.RouterMode.Single);
          })

        }
        .margin({ top: 12, bottom: 12 })
        .backgroundColor($r("app.color.card_bg"))
        .borderRadius(12)
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
        })

        ListItemGroup() {
          // 创建数据库
          ListItem() {
            Row() {
              Text($r("app.string.create_database"))
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
          .onClick(()=>{
            this.router.pushUrl({
              url: 'pages/open/CreateDatabase'
            }, router.RouterMode.Single);
          })

          // 更换数据库
          ListItem() {
            Row() {
              Text($r("app.string.change_database"))
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
          .onClick(()=>{
            this.router.pushUrl({
              url: 'pages/open/OpenDatabase'
            }, router.RouterMode.Single);
          })

          // 最近打开
          ListItem() {
            Row() {
              Text($r("app.string.recent_files"))
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
          .onClick(()=>{
            this.router.pushUrl({
              url: 'pages/RecentFiles'
            }, router.RouterMode.Single);
          })
        }
        .margin({ top: 12, bottom: 12 })
        .backgroundColor($r("app.color.card_bg"))
        .borderRadius(12)
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
        })

        ListItemGroup() {
          // 关于
          ListItem() {
            Row() {
              Text($r('app.string.Settings_about'))
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
          .onClick(()=>{
            this.router.pushUrl({
              url: 'pages/About'
            }, router.RouterMode.Single);
          })
        }
        .backgroundColor($r("app.color.card_bg"))
        .margin({ top: 12, bottom: 12 })
        .borderRadius(12)
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
        })
      }
      .width('100%')
      .height('auto')
      .layoutWeight(1)
      .margin({ top: 12 })
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}