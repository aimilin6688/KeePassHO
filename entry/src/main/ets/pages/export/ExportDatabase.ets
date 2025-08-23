import { PromptAction, Router } from '@kit.ArkUI';
import FileUtils from '../../common/utils/FIleUtils';
import ResourceManager from '../../common/utils/ResourceManager';
import { ContextLoadingDialog } from '../../components/ContextLoadingDialog';
import { OpenMethodButton } from '../../components/OpenMethodButton';
import { FileService } from '../../services/FileService';
import { KdbxExportService } from '../../services/kdbx/KdbxExportService';
import { DbFileParam } from '../../services/TypeDefined';
import { ExportType } from '../SettingDatabase';

@Entry
@Component
struct ExportDatabase {
  @State savingMessage: string = ResourceManager.getString($r('app.string.save_saving'));
  private exportType: ExportType = ExportType.KDBX;
  private router: Router = this.getUIContext().getRouter();
  private fileName: string = "";
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  // 带内容的进度弹框
  private savingDialogController: CustomDialogController = new CustomDialogController({
    builder: ContextLoadingDialog({
      loadingMessage: this.savingMessage,
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });

  aboutToAppear(): void {
    const params = this.router.getParams() as Record<string, string>;
    if (params) {
      this.exportType = params.exportType as ExportType;
    }
    this.createFileName();
  }

  /**
   * 创建文件名
   */
  private createFileName() {
    const dbFile: DbFileParam = FileService.getDbFileParam();
    if (!dbFile) {
      this.promptAction.showToast({ message: ResourceManager.getString($r('app.string.database_not_opened')) });
      return;
    }
    this.fileName = FileUtils.replaceExt(dbFile.fileName, "." + this.exportType.toLowerCase());
  }

  // 保存数据库文件到本地
  private saveToLocal() {
    let dialogTimeout: number = 0;
    FileUtils.saveLocalFile(this.fileName, () => {
      dialogTimeout = setTimeout(() => {
        this.savingDialogController.open();
      }, 300);
      return KdbxExportService.createExportFile(this.exportType).then(result => {
        return result.content;
      });
    }).then(() => {
      this.savingDialogController.close();
      clearTimeout(dialogTimeout);
      this.router.back();
    });
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back()
          })

        Text($r('app.string.export_database'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

      // 导出方式列表
      Scroll() {
        Column() {
          // 导出方式
          Column() {
            Text($r("app.string.export_select_way"))
              .fontSize(14)
              .opacity(0.6)
              .padding({ left: 16, top: 16, bottom: 8 })
              .fontColor($r('app.color.text_primary'))
              .alignSelf(ItemAlign.Start)

            OpenMethodButton(
              $r('app.media.ic_file'),
              $r('app.string.local_file_button_title'),
              $r("app.string.export_to_local_desc"),
              () => {
                this.saveToLocal();
              }
            )

            OpenMethodButton(
              $r("app.media.ic_webdav"),
              $r('app.string.webdav_button_title'),
              $r("app.string.export_to_webdav_desc"),
              () => {
                this.router.pushUrl({
                  url: 'pages/open/WebDAV',
                  params: {
                    exportType: this.exportType
                  }
                })
              }
            )

          }
          .backgroundColor($r("app.color.card_bg"))
          .margin({ top: 16 })
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart) // 确保内容从顶部开始显示
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
