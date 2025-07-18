import { PromptAction, Router } from '@kit.ArkUI';
import { RecentFilesService } from '../services/RecentFilesService';
import { RecentFile } from '../services/TypeDefined';


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
      this.recentFiles = await RecentFilesService.getInstance().getRecentFiles();
    } catch (error) {
      console.error(`加载最近文件列表失败: ${error}`);
      this.promptAction.showToast({
        message: '加载最近文件列表失败',
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
        message: '文件不存在或已被移动',
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
        message: '已清除所有记录',
        duration: 2000
      });
    } catch (error) {
      console.error(`清除记录失败: ${error}`);
      this.promptAction.showToast({
        message: '清除记录失败',
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
        message: '已移除记录',
        duration: 2000
      });
    } catch (error) {
      console.error(`移除记录失败: ${error}`);
      this.promptAction.showToast({
        message: '移除记录失败',
        duration: 2000
      });
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .margin({ right: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back();
          })
        Text('最近打开的文件')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('清除全部')
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
          Text('没有最近打开的文件记录')
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
                Image($r('app.media.ic_file'))
                  .width(40)
                  .height(40)
                  .fillColor($r('app.color.text_primary'))
                  .margin({ right: 16 })
                Column() {
                  Text(file.fileName)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
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
              .padding(16)
              .borderRadius(8)
              .onClick(() => {
                this.openFile(file);
              })
            }
            .margin({ bottom: 8 })
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
  }
}
