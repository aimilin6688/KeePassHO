import { fileShare, picker } from '@kit.CoreFileKit';
import common from '@ohos.app.ability.common';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { StorageType } from '../../services/kdbx/interfaces';
import { PromptAction, Router } from '@kit.ArkUI';
import FileUtils from '../../common/utils/FIleUtils';
import { LocalFileStorageConfig } from '../../services/kdbx/interfaces/StorageConfig';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { DataService } from '../../services/DataService';

const DOMAIN = 0x0000;
const TAG = 'LocalFile';

@Entry
@Component
struct LocalFile {
  @State selectedFile: string = '';
  @State isLoading: boolean = false;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.LOCAL);
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  /**
   * 打开文件选择器
   */
  async openFilePicker() {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.context);
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['.kdbx']; // 只显示kdbx文件
      options.maxSelectNumber = 1; // 只允许选择一个文件

      const result = await documentPicker.select(options);
      if (result && result.length > 0) {
        this.selectedFile = result[0];
        this.loadData(this.selectedFile);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to pick file: %{public}s,  stack: %{public}s`, error.message, error.stack);
      this.promptAction.showToast({
        message: error.message,
        duration: 2000
      });
    }
  }

  /**
   * 加载KDBX文件
   * @param path 文件路径
   */
  async loadData(path: string) {
    this.isLoading = true;
    // 永久授权文件访问权限
    FileUtils.persistPermission(path, fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE).then(async () => {
      // 获取文件信息
      const fileInfo = await this.fileManager.getInfo(path);
      hilog.info(DOMAIN, TAG, `Loading KDBX file: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
      // 本地配置信息
      const storageConfig = new LocalFileStorageConfig(fileInfo.size);
      // 设置数据服务
      DataService.readData(this.router, {
        filePath: path,
        fileName: fileInfo.name,
        storageType: StorageType.LOCAL,
        storageConfig: storageConfig
      });
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to load KDBX file: %{public}s, stack:%{public}s', error.message, error.stack);
      this.promptAction.showToast({
        message: error.message,
        duration: 3000
      });
    }).finally(() => {
      this.isLoading = false;
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

        Text($r('app.string.select_local_file'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

      // 主要内容区域
      Column() {
        if (this.isLoading) {
          // 加载中状态
          LoadingProgress()
            .width(50)
            .height(50)
            .color($r('app.color.text_primary'))

          Text($r('app.string.loading_message'))
            .fontSize(16)
            .margin({ top: 16 })
            .fontColor($r('app.color.text_primary'))
        } else if (this.selectedFile) {
          // 已选择文件状态
          Image($r('app.media.ic_file'))
            .width(64)
            .height(64)
            .margin({ top: 40 })

          Text(this.selectedFile.split('/').pop() || '')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('80%')

          Button($r('app.string.reselect_file'))
            .margin({ top: 24 })
            .onClick(() => this.openFilePicker())
        } else {
          // 未选择文件状态
          Image($r('app.media.ic_add_file'))
            .width(80)
            .height(80)
            .margin({ top: 60 })
            .fillColor($r('app.color.text_secondary'))

          Text($r('app.string.LocalFile_click_to_select'))
            .fontSize(16)
            .margin({ top: 16 })
            .fontColor($r('app.color.text_primary'))

          Button($r('app.string.select_local_file'))
            .margin({ top: 24 })
            .onClick(() => this.openFilePicker())
        }
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
