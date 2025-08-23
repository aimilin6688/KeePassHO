import { Router } from '@kit.ArkUI';
import { ByteUtils } from 'kdbxweb';
import FileUtils from '../../common/utils/FIleUtils';
import { OpenMethodButton } from '../../components/OpenMethodButton';
import { FileService } from '../../services/FileService';
import { KdbxCsvService } from '../../services/kdbx/KdbxCsvService';
import { DbFileParam } from '../../services/TypeDefined';
import { ExportType } from '../SettingDatabase';

@Entry
@Component
struct ExportDatabase {
  private exportType: ExportType = ExportType.KDBX;
  private router: Router = this.getUIContext().getRouter();

  aboutToAppear() {
    const params = this.router.getParams() as Record<string, string>;
    this.exportType = params.exportType as ExportType;
  }

  // 保存数据库文件到本地
  private saveToLocal() {
    let dbFile: DbFileParam = FileService.getDbFileParam();
    const kdbx = dbFile.database;
    if (ExportType.KDBX === this.exportType) {
      kdbx.save().then(result => {
        FileUtils.saveLocalFile(dbFile.fileName, result);
      });
    }
    if (ExportType.XML === this.exportType) {
      kdbx.saveXml(true, false).then(result => {
        FileUtils.saveLocalFile(FileUtils.replaceExt(dbFile.fileName, ".xml"), ByteUtils.stringToBuffer(result));
      });
    }
    if(ExportType.CSV === this.exportType){
      KdbxCsvService.export(kdbx).then(result=>{
        FileUtils.saveLocalFile(FileUtils.replaceExt(dbFile.fileName, ".csv"), result);
      })
    }
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
                this.router.pushUrl({ url: 'pages/open/WebDAV' })
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
