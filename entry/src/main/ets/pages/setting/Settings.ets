import { ThemeConstants, ThemeMode } from '../../common/constants/ThemeConstants';
import { SettingsService } from '../../services/SettingsService';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SortConstants, SortMode } from '../../common/constants/SortConstants';
import { DataService } from '../../services/DataService';
import { CommonUtils, NavigationManager, ShareUtils } from '../../common/utils';
import { CrashLogService } from '../../services/CrashLogService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PageConstants } from '../../common/constants/PageConstants';

const DOMAIN = 0x0000;
const TAG = 'Settings';

// Settings页面的Builder函数
@Builder
export function SettingsBuilder(name: string, param: Object): void {
  Settings()
}

interface SettingItem {
  id: string;
  name: string;
  title: ResourceStr;
  isPageRoute?: boolean;
}

@Component
export struct Settings {
  private navManager: NavigationManager = NavigationManager.getInstance();
  @State sortBy: SortMode = SortMode.DEFAULT
  @State currentThemeMode: ThemeMode = ThemeMode.SYSTEM;
  @StorageProp('currentColorMode') @Watch('onColorModeChange') currentSystemMode: ConfigurationConstant.ColorMode =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State hasCrashLog: boolean = false;
  @State currentRightPageName: string = ''; // 已废弃：以 NavPathStack 实际栈顶判断去重
  private settingsService: SettingsService = SettingsService.getInstance();

  private settingItems: SettingItem[] = [
    {
      id: 'security',
      name: PageConstants.PAGE_SETTING_SECURITY,
      title: $r('app.string.Settings_security'),
      isPageRoute: true
    },
    {
      id: 'database',
      name: PageConstants.PAGE_SETTING_DATABASE,
      title: $r('app.string.Settings_database'),
      isPageRoute: true
    },
    {
      id: 'application',
      name: PageConstants.PAGE_SETTING_APPLICATION,
      title: $r('app.string.Settings_application'),
      isPageRoute: true
    },
  ];

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
    // 检查是否有崩溃日志
    this.hasCrashLog = await CrashLogService.getInstance().hasCrashLog();
  }

  /**
   * 分享崩溃日志
   * 只有用户真正完成分享后才删除日志文件
   */
  private async shareCrashLog() {
    try {
      const logPath = await CrashLogService.getInstance().getLatestCrashLogPath();
      if (logPath) {
        const success = await ShareUtils.shareFileWithCallback(
          CommonUtils.getContext(),
          logPath,
          // 分享完成回调 - 用户真正完成分享后才触发
          async () => {
            hilog.info(DOMAIN, TAG, 'Crash log shared successfully, clearing logs');
            // 分享成功后清除崩溃日志
            await CrashLogService.getInstance().clearCrashLog();
            this.hasCrashLog = false;
          },
          'KeePassHO Crash Log'
        );
        if (!success) {
          hilog.error(DOMAIN, TAG, 'Failed to show share panel');
        }
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to share crash log: %{public}s', err.message);
    }
  }

  /**
   * 入栈页面：若右侧导航栈顶已是该页面，则不再重复打开
   */
  private pushPageOnce(pageName: string, param: Object = new Object()): void {
    const stack = this.navManager.getNavPathStack();
    if (!stack) {
      hilog.error(DOMAIN, TAG, 'navPathStack is null');
      return;
    }
    // 使用真实栈顶判断，避免 ListItemGroup 内直接 push 的页面不同步状态导致误判
    const allPathNames: string[] = stack.getAllPathName();
    const topName: string = allPathNames.length > 0 ? allPathNames[allPathNames.length - 1] : '';
    if (topName === pageName) {
      hilog.info(DOMAIN, TAG, 'Page %{public}s already at top, skipping push', pageName);
      return;
    }
    stack.pushPathByName(pageName, param);
  }

  private handleItemClick(item: SettingItem) {
    this.pushPageOnce(item.name);
    this.currentRightPageName = item.name;
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Stack() {
          Image($r("app.media.ic_angle_left"))
            .width(28)
            .height(28)
            .fillColor($r('app.color.text_primary'))
        }
        .margin({ left: 16 })
        .id('btn_settings_back')
        .onClick(() => this.navManager.navigateBackToPreviousRoot())
        Text($r('app.string.Settings_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
      }
      .width('100%')
      .height(48)

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
              .padding({ left: 16 })
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

        // 设置项列表（使用弹框显示）
        ListItemGroup() {
          ForEach(this.settingItems, (item: SettingItem) => {
            ListItem() {
              Row() {
                Text(item.title)
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
            .onClick(() => this.handleItemClick(item))
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
          .id('menu_create_database')
          .onClick(() => {
            this.pushPageOnce(PageConstants.PAGE_CREATE_DATABASE);
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
          .id('menu_change_database')
          .onClick(() => {
            DataService.selectKdbx();
            this.pushPageOnce(PageConstants.PAGE_SELECT_LOCATION);
          })

          // 最近打开
          ListItem() {
            Row() {
              Text($r('app.string.recent_files'))
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
          .onClick(() => {
            this.pushPageOnce(PageConstants.PAGE_RECENT_FILES);
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
          // 崩溃日志
          if (this.hasCrashLog) {
            ListItem() {
              Row() {
                Text($r('app.string.crash_log_title'))
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
            .onClick(() => {
              this.shareCrashLog();
            })
          }
        }
        .backgroundColor($r("app.color.card_bg"))
        .margin({ top: 12, bottom: 12 })
        .borderRadius(12)
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
        })

        // 关于
        ListItemGroup() {
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
          .onClick(() => {
            this.pushPageOnce(PageConstants.PAGE_ABOUT);
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
      .padding({ left: 12, right: 12, top: 4 })
      .clipContent(ContentClipMode.SAFE_AREA)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
