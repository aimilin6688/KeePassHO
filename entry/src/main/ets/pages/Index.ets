import { CommonUtils, ThemeManager } from '../common/utils';
import { Router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RecentFilesService } from '../services/RecentFilesService';
import { DataService } from '../services/DataService';
import { RecentFile } from '../services/TypeDefined';
import { Constants } from '../common/constants/Constants';

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
      // 优化：使用预加载的最近文件信息
      this.checkRecentFilesOptimized();
    }
  }

  /**
   * 检查是否有最近打开的文件（优化版）
   * 优先使用预加载数据，避免重复读取 preferences
   */
  private checkRecentFilesOptimized(): void {
    // 1. 优先使用预加载的最近文件
    const preloadedRecentFile = AppStorage.get<RecentFile>(Constants.APP_STORAGE_PRELOAD_RECENT_FILE);
    if (preloadedRecentFile) {
      hilog.info(DOMAIN, TAG, 'Using preloaded recent file: %{public}s', preloadedRecentFile.filePath);
      this.navigateToPassword(preloadedRecentFile.filePath);
      return;
    }

    // 2. 等待预加载完成（最多等待500ms）
    this.waitForPreloadAndNavigate();
  }

  /**
   * 等待预加载完成
   */
  private waitForPreloadAndNavigate(): void {
    const maxWaitTime = 500; // 最大等待时间
    const checkInterval = 50; // 检查间隔
    let waitedTime = 0;

    const checkAndNavigate = (): void => {
      const preloadedRecentFile = AppStorage.get<RecentFile>(Constants.APP_STORAGE_PRELOAD_RECENT_FILE);
      const preloadReady = AppStorage.get<boolean>(Constants.APP_STORAGE_PRELOAD_READY);

      if (preloadedRecentFile) {
        this.navigateToPassword(preloadedRecentFile.filePath);
        return;
      }

      if (preloadReady) {
        // 预加载完成但没有最近文件，显示首页
        hilog.info(DOMAIN, TAG, 'No recent file, showing home page');
        return;
      }

      waitedTime += checkInterval;
      if (waitedTime < maxWaitTime) {
        // 继续等待
        setTimeout(checkAndNavigate, checkInterval);
      } else {
        // 超时，回退到原始方式
        hilog.info(DOMAIN, TAG, 'Preload timeout, fallback to loadMostRecentFile');
        this.checkRecentFiles();
      }
    };

    setTimeout(checkAndNavigate, checkInterval);
  }

  /**
   * 导航到密码页面
   */
  private navigateToPassword(filePath: string): void {
    CommonUtils.pushUrl({
      url: 'pages/Password',
      params: {
        filePath: filePath
      }
    });
  }

  /**
   * 检查是否有最近打开的文件（原始方法，作为回退）
   */
  async checkRecentFiles() {
    try {
      // 加载最近打开的文件
      RecentFilesService.getInstance().loadMostRecentFile().then((recentFile) => {
        if (recentFile) {
          this.navigateToPassword(recentFile.filePath);
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
            CommonUtils.pushUrl({ url: 'pages/setting/Settings' })
          })
      }
      .width('100%')
      .height(40)

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
          CommonUtils.pushUrl({ url: 'pages/open/SelectLocation' })
        })

        // 添加间距
        Column() {
          this.MainButton($r('app.media.ic_add_file'), $r('app.string.create_database'), () => {
            CommonUtils.pushUrl({ url: 'pages/open/CreateDatabase' })
          })
        }
        .margin({ top: 24 })

        // 最近打开的文件按钮
        Column() {
          this.MainButton($r("app.media.ic_clock"), $r('app.string.recent_files_title'), () => {
            CommonUtils.pushUrl({ url: 'pages/RecentFiles' })
          })
        }
        .margin({ top: 24 })
      }
      .width('100%')
      .layoutWeight(1)
    }

    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
