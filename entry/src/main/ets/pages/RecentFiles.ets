import { PromptAction, Router } from '@kit.ArkUI';
import { RecentFilesService } from '../services/RecentFilesService';
import { RecentFile } from '../services/TypeDefined';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageType } from '../services/kdbx/interfaces/StorageType';

const DOMAIN = 0x0000;
const TAG = 'RecentFiles';

@Entry
@Component
struct RecentFiles {
  @State recentFiles: RecentFile [] = [];
  @State isLoading: boolean = true;
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  aboutToAppear() {
    this.loadRecentFiles();
  }

  /**
   * 加载最近打开的文件列表
   */
  async loadRecentFiles() {
    try {
      this.isLoading = true;
      this.recentFiles = await RecentFilesService.getRecentFiles();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'load recent file error: %{public}s', error.message);
      this.promptAction.showToast({
        message: $r('app.string.load_recent_files_failed'),
        duration: 2000
      });
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 打开选中的文件
   * @param filePath 文件路径
   * @param fileName 文件名
   */
  async openFile(recentFile: RecentFile) {
    let recentFilesService: RecentFilesService = RecentFilesService.getInstance();
    // 检查文件是否存在
    const fileExists = await recentFilesService.checkFileExists(recentFile);
    if (!fileExists) {
      this.promptAction.showToast({
        message: $r('app.string.file_not_exists'),
        duration: 2000
      });
      // 移除不存在的文件记录
      await recentFilesService.removeRecentFile(recentFile);
      // 重新加载列表
      this.loadRecentFiles();
      return;
    }
    // 导航到密码输入页面
    this.router.pushUrl({
      url: 'pages/Password',
      params: {
        filePath: recentFile.filePath
      }
    });
  }

  /**
   * 清除所有记录
   */
  async clearAllRecords() {
    try {
      await RecentFilesService.getInstance().clearRecentFiles();
      this.recentFiles = [];
      this.promptAction.showToast({
        message: $r('app.string.all_records_cleared'),
        duration: 2000
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'clear records error: %{public}s', error.message);
      this.promptAction.showToast({
        message: $r('app.string.clear_records_failed'),
        duration: 2000
      });
    }
  }

  /**
   * 移除单个记录
   * @param filePath 文件路径
   */
  async removeRecord(recentFile: RecentFile) {
    try {
      await RecentFilesService.getInstance().removeRecentFile(recentFile);
      // 重新加载列表
      this.loadRecentFiles();
      this.promptAction.showToast({
        message: $r('app.string.record_removed'),
        duration: 2000
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'remove records error: %{public}s', error.message);
      this.promptAction.showToast({
        message: $r('app.string.remove_record_failed'),
        duration: 2000
      });
    }
  }

  private getStorageTypeIcon(storageType: StorageType): ResourceStr {
    switch (storageType) {
      case StorageType.LOCAL:
        return $r('app.media.ic_file');
      case StorageType.WEBDAV:
        return $r('app.media.ic_webdav');
    }
    return $r('app.media.ic_file');
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ right: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back();
          })
        Text($r('app.string.recent_files_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button($r('app.string.clear_all_button'))
          .fontSize(14)
          .fontColor('#E84026')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.clearAllRecords();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      // 文件列表
      if (this.isLoading) {
        LoadingProgress()
          .width(50)
          .height(50)
      } else if (this.recentFiles.length === 0) {
        Column() {
          Image($r('app.media.ic_empty'))
            .width(100)
            .height(100)
            .margin({ bottom: 16 })
          Text($r('app.string.no_recent_files'))
            .fontSize(16)
            .fontColor('#999999')
        }
        .width('100%')
        .height('80%')
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.recentFiles, (file: RecentFile) => {
            ListItem() {
              Row() {
                Image(this.getStorageTypeIcon(file.storageType))
                  .width(40)
                  .height(40)
                  .fillColor($r('app.color.text_primary'))
                  .margin({ right: 16 })
                Column() {
                  Text(file.fileName)
                    .fontSize(16)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .margin({ bottom: 4 })
                  Text(file.filePath)
                    .fontSize(14)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button() {
                  Image($r('app.media.ic_delete'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.text_primary'))
                }
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.removeRecord(file);
                })
              }
              .width('100%')
              .height(60)
              .padding({ left: 10, right: 10 })
              .borderRadius(8)
              .backgroundColor($r("app.color.card_bg"))
              .onClick(() => {
                this.openFile(file);
              })
            }
            .margin({ bottom: 8 })
          })
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .padding({
          left: 12,
          right: 12,
          top: 12
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP,SafeAreaEdge.BOTTOM])
  }
}
