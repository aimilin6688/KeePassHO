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
import { SettingDialogWrapper } from '../../components/SettingDialogWrapper';
import { SettingSecurity } from './SettingSecurity';
import { SettingDatabase } from './SettingDatabase';
import { SettingApplication } from './SettingApplication';
// import { About } from '../about/About';

const DOMAIN = 0x0000;
const TAG = 'Settings';

// Settings页面的Builder函数
@Builder
export function SettingsBuilder(name: string, param: Object): void {
  Settings({ navPathStack: NavigationManager.getInstance().getNavPathStack()! })
}

interface SettingItem {
  id: string;
  name: string;
  title: ResourceStr;
  isPageRoute?: boolean;
}

@Component
export struct Settings {
  @Prop navPathStack: NavPathStack;
  private navManager: NavigationManager = NavigationManager.getInstance();
  @State sortBy: SortMode = SortMode.DEFAULT
  @State currentThemeMode: ThemeMode = ThemeMode.SYSTEM;
  @StorageProp('currentColorMode') @Watch('onColorModeChange') currentSystemMode: ConfigurationConstant.ColorMode =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State hasCrashLog: boolean = false;
  private settingsService: SettingsService = SettingsService.getInstance();

  private settingItems: SettingItem[] = [
    {
      id: 'security',
      name: PageConstants.PAGE_SETTING_SECURITY,
      title: $r('app.string.Settings_security')
    },
    {
      id: 'database',
      name: PageConstants.PAGE_SETTING_DATABASE,
      title: $r('app.string.Settings_database')
    },
    {
      id: 'application',
      name: PageConstants.PAGE_SETTING_APPLICATION,
      title: $r('app.string.Settings_application')
    },
    {
      id: 'about',
      name: PageConstants.PAGE_ABOUT,
      title: $r('app.string.Settings_about')
    },
    {
      id: 'recentFiles',
      name: PageConstants.PAGE_RECENT_FILES,
      title: $r('app.string.recent_files'),
      isPageRoute: true
    },
  ];

  private dialogController: CustomDialogController | null = null;

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

  private handleItemClick(item: SettingItem) {
    if (item.isPageRoute) {
      // 在右侧分栏显示
      this.navPathStack.pushPathByName(item.name, null);
    } else {
      // 使用弹框展示
      this.showSettingDialog(item);
    }
  }

  private showSettingDialog(item: SettingItem) {
    const closeDialog: () => void = () => {
      if (this.dialogController) {
        this.dialogController.close();
      }
    };
    const contentBuilder: () => void = () => {
      this.SettingDialogContentBuilder(item.name);
    };
    this.dialogController = new CustomDialogController({
      builder: SettingDialogWrapper({
        title: item.title,
        context: this.getUIContext(),
        content: contentBuilder,
        onClose: closeDialog
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
      autoCancel: true,
    });

    this.dialogController.open();
  }

  @Builder
  SettingDialogContentBuilder(settingName: string) {
    // 直接使用现有页面组件（最小改动）
    // 注意：这些组件需要是export的，不带@Entry
    if (settingName === PageConstants.PAGE_SETTING_SECURITY) {
      SettingSecurity();
    } else if (settingName === PageConstants.PAGE_SETTING_DATABASE) {
      SettingDatabase({ navPathStack: this.navPathStack });
    } else if (settingName === PageConstants.PAGE_SETTING_APPLICATION) {
      SettingApplication();
    } else if (settingName === PageConstants.PAGE_ABOUT) {
      // About 组件有语法错误，暂时显示占位符
      Column() {
        Text('设置项: ' + settingName)
          .fontSize(16)
          .padding(20)
      }
      // About();
    }
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
          .onClick(() => this.navManager.navigateBackToPreviousRoot())
        Text($r('app.string.Settings_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(40)

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
          .onClick(() => {
            this.navPathStack.pushPathByName('CreateDatabase', null);
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
          .onClick(() => {
            DataService.selectKdbx();
            this.navPathStack.pushPathByName('SelectLocation', null);
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
