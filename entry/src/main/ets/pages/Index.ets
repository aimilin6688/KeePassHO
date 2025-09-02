import ThemeManager from '../common/utils/ThemeManager';
import { Router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RecentFilesService } from '../services/RecentFilesService';
import { DataService } from '../services/DataService';

const DOMAIN = 0x0000;
const TAG = 'Index';

@Entry
@Component
struct Index {
  private router: Router = this.getUIContext().getRouter();

  aboutToAppear() {
    // 监听主题变化
    ThemeManager.getInstance().addThemeChangeListener(() => {
      this.onThemeChanged();
    });
    const params = this.router.getParams() as Record<string, string>;
    if (!params?.notRedirect) {
      this.checkRecentFiles();
    }
  }

  /**
   * 检查是否有最近打开的文件
   */
  async checkRecentFiles() {
    try {
      // 加载最近打开的文件
      RecentFilesService.getInstance().loadMostRecentFile().then((recentFile) => {
        if (recentFile) {
          // 导航到密码输入页面
          this.router.pushUrl({
            url: 'pages/Password',
            params: {
              filePath: recentFile.filePath
            }
          });
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', `Failed to check recent files: ${error}`);
    }
  }

  aboutToDisappear() {
    // 移除主题变化监听
    ThemeManager.getInstance().removeThemeChangeListenerAll();
  }

  onThemeChanged() {
  }

  @State private updateUI: boolean = false;

  @Builder
  MainButton(icon: Resource, text: string | Resource, onClick: () => void) {
    Button() {
      Row() {
        Image(icon)
          .width(24)
          .height(24)
          .margin({ right: 8 })
        Text(text)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
    }
    .width('80%')
    .height(56)
    .borderRadius(28)
    .backgroundColor($r("app.color.card_bg"))
    .onClick(onClick)
  }

  build() {
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
            this.router.pushUrl({ url: 'pages/Settings' })
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

      // 主要内容区域
      Column() {
        // Logo或应用图标
        Image($r('app.media.startIcon'))
          .width(120)
          .height(120)
          .margin({ top: 60, bottom: 40 })

        // 欢迎文本
        Text($r('app.string.Index_welcome'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 8 })
          .fontColor($r('app.color.text_primary'))

        Text($r('app.string.Index_subtitle'))
          .fontSize(16)
          .opacity(0.6)
          .margin({ bottom: 60 })
          .fontColor($r('app.color.text_primary'))

        // 主要操作按钮
        this.MainButton($r('app.media.ic_folder_open'), $r("app.string.open_database"), () => {
          DataService.selectKdbx(this.router);
          this.router.pushUrl({ url: 'pages/open/SelectLocation' })
        })

        // 添加间距
        Column() {
          this.MainButton($r('app.media.ic_add_file'), $r('app.string.create_database'), () => {
            this.router.pushUrl({ url: 'pages/open/CreateDatabase' })
          })
        }
        .margin({ top: 24 })

        // 最近打开的文件按钮
        Column() {
          this.MainButton($r('app.media.ic_history'), $r('app.string.recent_files_title'), () => {
            this.router.pushUrl({ url: 'pages/RecentFiles' })
          })
        }
        .margin({ top: 24 })
      }
      .width('100%')
      .layoutWeight(1)
    }

    .width
    ('100%'
    )
    .height
    ('100%'
    )
    .backgroundColor
    ($r
    ("app.color.bg_primary"
    ))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
