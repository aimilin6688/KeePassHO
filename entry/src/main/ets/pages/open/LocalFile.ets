import picker from '@ohos.file.picker';
import common from '@ohos.app.ability.common';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { StorageType } from '../../services/kdbx/interfaces';
import promptAction from '@ohos.promptAction';
import { Router } from '@kit.ArkUI';

@Entry
@Component
struct LocalFile {
  @State selectedFile: string = '';
  @State isLoading: boolean = false;
  private context = this.getUIContext().getHostContext()  as common.UIAbilityContext;
  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.LOCAL);
  private router: Router = this.getUIContext().getRouter();

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
        this.loadKdbxFile(this.selectedFile);
      }
    } catch (error) {
      console.error(`Failed to pick file: ${error}`);
      promptAction.showToast({
        message: `选择文件失败: ${error}`,
        duration: 2000
      });
    }
  }

  /**
   * 加载KDBX文件
   * @param path 文件路径
   */
  async loadKdbxFile(path: string) {
    this.isLoading = true;
    try {
      // 获取文件信息
      const fileInfo = await this.fileManager.getKdbxFileInfo(path);
      console.info(`Loading KDBX file: ${fileInfo.name}, size: ${fileInfo.size} bytes`);
      
      // 加载文件内容
      const content = await this.fileManager.loadKdbxFile(path);
      console.info(`KDBX file loaded successfully, content size: ${content.byteLength} bytes`);
      
      // 导航到密码输入页面，并传递文件内容
      this.router.pushUrl({
        url: 'pages/open/Password',
        params: {
          filePath: path,
          fileContent: content,
          fileName: fileInfo.name
        }
      });
    } catch (error) {
      console.error(`Failed to load KDBX file: ${error}`);
      promptAction.showToast({
        message: `加载文件失败: ${error}`,
        duration: 2000
      });
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back()
          })

        Text('选择本地文件')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r('app.color.card_background'))

      // 主要内容区域
      Column() {
        if (this.isLoading) {
          // 加载中状态
          LoadingProgress()
            .width(50)
            .height(50)
            .color($r('app.color.text_primary'))
          
          Text('正在加载文件...')
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
          
          Button('重新选择文件')
            .margin({ top: 24 })
            .onClick(() => this.openFilePicker())
        } else {
          // 未选择文件状态
          Image($r('app.media.ic_add_file'))
            .width(80)
            .height(80)
            .margin({ top: 60 })
            .fillColor($r('app.color.text_secondary'))
          
          Text('点击选择KDBX文件')
            .fontSize(16)
            .margin({ top: 16 })
            .fontColor($r('app.color.text_primary'))
          
          Button('选择文件')
            .margin({ top: 24 })
            .onClick(() => this.openFilePicker())
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background_primary'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
