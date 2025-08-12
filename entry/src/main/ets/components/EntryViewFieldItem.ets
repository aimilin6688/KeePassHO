import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { PromptAction } from '@kit.ArkUI';
import KdbxUtils from '../common/utils/KdbxUtils';
import { KdbxEntry } from 'kdbxweb';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { Icons } from '../services/TypeDefined';
import { SettingsService } from '../services/SettingsService';
import FileUtils from '../common/utils/FIleUtils';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'EntryViewFieldItem';

/**
 * 构建字段项
 */
@Observed
export class FieldView {
  key: string;
  value: string;
  isProtected: boolean;
  isCopy: boolean;
  showPlanText: boolean;
  isDownload: boolean;
  binaryFile?: ArrayBuffer | undefined;

  constructor(key: string, value: string, isProtected: boolean, isCopy: boolean, binaryFile?: ArrayBuffer) {
    this.key = key;
    this.value = value;
    this.isProtected = isProtected;
    this.isCopy = isCopy;
    this.showPlanText = !this.isProtected;
    this.isDownload = binaryFile !== undefined;
    this.binaryFile = binaryFile;
  }
}


@Component
export struct EntryViewFieldItem {
  @ObjectLink field: FieldView;
  @State entry: KdbxEntry | null = null;
  @State autoClearClipboardTime: number = SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private timeOutObj: number = -1;
  private systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  aboutToAppear(): void {
    this.initSettings();
    // 监听排序方式变化
    SettingsService.registerObserver(this.initSettings);
  }

  aboutToDisappear(): void {
    SettingsService.unregisterObserver(this.initSettings);
  }

  /**
   * 初始化系统配置参数
   */
  private initSettings = (key?: string) => {
    if (!key || key === SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME) {
      SettingsService.get(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, this.autoClearClipboardTime, (value) => {
        this.autoClearClipboardTime = value;
      });
    }
  }

  /**
   * 复制文本到剪贴板
   */
  private copyToClipboard(text: string) {
    // 获取系统剪贴板实例
    const pasteboardData = pasteboard.createData('text/plain', text);
    // 将数据写入剪贴板
    this.systemPasteboard.setData(pasteboardData, (error, data) => {
      if (error) {
        hilog.error(DOMAIN, TAG, 'Failed to copy to clipboard: %{public}s %{public}s %{public}s %{public}s', error.message, error.code, error.name, error.stack);
        this.promptAction.showToast({ message: $r("app.string.copy_failed") });
      } else {
        this.clearClipboard(pasteboardData);
        this.promptAction.showToast({ message: $r("app.string.copied"), duration: 2000 });
      }
    });
  }

  /**
   * 清理剪切板数据
   * @param pasteData
   */
  private clearClipboard(pasteData?: pasteboard.PasteData) {
    try {
      if (this.autoClearClipboardTime <= 0) {
        return;
      }
      if (this.timeOutObj != -1) {
        clearTimeout(this.timeOutObj);
        this.timeOutObj = -1;
      }
      this.timeOutObj = setTimeout(() => {
        pasteboard.getSystemPasteboard().clearData();
      }, 1000 * this.autoClearClipboardTime);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to clear clipboard: ${error}`)
    }
  }

  /**
   * 获取字段对应的图标
   */
  private getFieldIcon(fieldView: FieldView): ResourceStr {
    if (fieldView.isDownload) {
      return $r("app.media.ic_paperclip");
    }
    const key = fieldView.key;
    switch (key) {
      case KdbxUtils.FIELD_TITLE:
        return $r("app.media.ic_color_title");
      case KdbxUtils.FIELD_USERNAME:
        return $r("app.media.ic_color_user");
      case KdbxUtils.FIELD_PASSWORD:
        return $r("app.media.ic_color_password");
      case KdbxUtils.FIELD_URL:
        return $r("app.media.ic_color_url");
      case KdbxUtils.FIELD_NOTES:
        return $r("app.media.ic_color_notes");
      case KdbxUtils.FIELD_TAGS:
        return $r("app.media.ic_color_tag");
      case KdbxUtils.GROUP_NAME:
        return this.getGroupIcon();
      case KdbxUtils.FIELD_CREATION_TIME:
        return $r("app.media.ic_color_clock");
      case KdbxUtils.FIELD_LASTMOD_TIME:
        return $r("app.media.ic_color_clock");
      case KdbxUtils.FIELD_EXPIRY_TIME:
        return $r("app.media.C45_Expired");
      default:
        return $r("app.media.ic_color_note");
    }
  }

  /**
   * 获取分组图标
   */
  private getGroupIcon(): ResourceStr {
    // 如果有自定义图标，返回自定义图标
    if (this.entry?.parentGroup) {
      let group = this.entry?.parentGroup;
      return KdbxUtils.getIcon(group.icon, group.customIcon, $r('app.media.ic_folder'));
    }
    // 否则返回默认分组图标
    return KdbxUtils.getIcon(Icons.Folder, undefined, $r('app.media.ic_folder'));
  }

  /**
   * 下载附件信息
   * @param fieldView
   */
  private downloadFile(fieldView: FieldView) {
    if (!fieldView.binaryFile || fieldView.binaryFile.byteLength <= 0) {
      this.promptAction.showToast({ message: $r("app.string.invalid_binary_file"), duration: 2000 });
      return;
    }
    // 使用文件选择器让用户选择保存位置
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fieldView.key];

    // 显示文件保存对话框
    documentPicker.save(options).then(async (result) => {
      hilog.info(DOMAIN, TAG, `Selected URIs: ${result}`);
      if (result && result.length > 0 && fieldView.binaryFile) {
        FileUtils.saveFile(result[0], fieldView.binaryFile).then(result => {
          this.promptAction.showToast({ message: $r("app.string.save_success") });
        });
      }
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, `Failed to show document save dialog: ${err.message}`, err.stack);
      this.promptAction.showToast({ message: $r('app.string.CreateDatabase_location_failed', err.message) });
    })
  }

  build() {
    Row() {
      // 左侧图标
      Image(this.getFieldIcon(this.field))
        .width(32)
        .height(32)
        .margin({ right: 12 })

      // 中间内容区域
      Column() {
        // 左上角小标题显示标签提示信息
        Text(KdbxUtils.getFieldName(this.field.key))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: 4 })

        // 左下角显示具体的值
        Text(this.field.showPlanText ? this.field.value : '******')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .copyOption(this.field.showPlanText ? CopyOptions.LocalDevice : CopyOptions.None)
          .textAlign(TextAlign.Start)
          .enableDataDetector(this.field.isProtected ? false : true)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧复制按钮
      if (this.field.value && this.field.isProtected) {
        Image(this.field.showPlanText ? $r('app.media.ic_eye_off') : $r('app.media.ic_eye'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .margin({ left: 8, right: 8 })
          .onClick((event) => {
            this.field.showPlanText = !this.field.showPlanText;
            return false;
          })
      }

      // 右侧复制按钮
      if (this.field.value && this.field.isCopy) {
        Image($r('app.media.ic_copy'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick((event) => {
            this.copyToClipboard(this.field.value);
            return false;
          })
      }

      // 右侧下载按钮
      if (this.field.isDownload) {
        Image($r('app.media.ic_download'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick((event) => {
            this.downloadFile(this.field);
            return false;
          })
      }
    }
    .width('100%')
    .backgroundColor($r("app.color.card_bg"))
    .borderRadius(8)
    .padding(12)
    .margin({ bottom: 8 })
  }
}