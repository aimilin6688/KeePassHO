import { PromptAction } from '@kit.ArkUI';
import { KdbxUtils, FileUtils, ResourceManager, CommonUtils, FilenameUtils, StringUtils } from '../common/utils';
import { KdbxEntry, KdbxFieldReference } from 'kdbxweb';

import { Icons } from '../services/TypeDefined';
import { SettingsService } from '../services/SettingsService';
import { common } from '@kit.AbilityKit';
import { TotpPreviewComponent } from './TotpPreviewComponent';
import { ClipboardUtils } from '../common/utils/ClipboardUtils';
import { FileService } from '../services/FileService';
import { UIUtils } from '@kit.ArkUI';
import { ImageViewerDialog } from './ImageViewerDialog';
import { TotpQrDialog } from './TotpQrDialog';

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
  isTotp: boolean = false;
  otpValue: string = '';
  fileSizeStr: string = '';
  isImageFile: boolean = false;
  /** 值下方补充提示文本（如到期剩余天数），空串不渲染 */
  warningText: string = '';
  /** 提示文本颜色（已过期红 error / 临期橙 warn / 普通次级 text_secondary） */
  warningColor: ResourceColor = $r('app.color.warn');

  constructor(key: string, value: string, isProtected: boolean, isCopy: boolean,
    binaryFile?: ArrayBuffer, fileSize?: number) {
    this.key = key;
    this.value = value;
    this.isProtected = isProtected;
    this.isCopy = isCopy;
    this.showPlanText = !this.isProtected;
    // 磁盘引用附件：binaryFile 延迟异步回读，先用 fileSize 占位展示
    this.isDownload = binaryFile !== undefined || fileSize !== undefined;
    this.binaryFile = binaryFile;
    this.isImageFile = this.isDownload && FilenameUtils.isImage(key);
    if (binaryFile) {
      this.fileSizeStr = StringUtils.formatFileSize(binaryFile.byteLength);
    } else if (fileSize !== undefined) {
      this.fileSizeStr = StringUtils.formatFileSize(fileSize);
    }
    // TOTP类型
    if (KdbxUtils.isTotpUrl(value)) {
      this.isTotp = true;
      this.otpValue = value;
      // 同步读取"条目显示TOTP字段"设置，关闭时不再显示令牌明文
      this.showPlanText = SettingsService.getSync(SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP,
        SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP_DEFAULT);
    }
  }
}


@Component
export struct EntryViewFieldItem {
  @ObjectLink field: FieldView;
  @State entry: KdbxEntry | null = null;
  @State autoClearClipboardTime: number = SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT;
  @State isItemShowTotp: boolean = SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP_DEFAULT;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private imageViewerDialogController: CustomDialogController = new CustomDialogController({
    builder: ImageViewerDialog({
      binaryFile: this.field?.binaryFile ?? null,
      binaryFileName: this.field?.key ?? '',
      // 磁盘引用附件异步回读：弹窗打开时才读取当前内容
      binaryFileProvider: () => this.field?.binaryFile ?? null
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true
  });
  // TOTP 二维码导出弹窗（otpValue 构造期固化，多 TOTP 条目每行独立）
  private totpQrDialogController: CustomDialogController = new CustomDialogController({
    builder: TotpQrDialog({
      otpAuthUrl: this.field?.otpValue ?? '',
      entryTitle: this.entry ? KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_TITLE) : ''
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true
  });

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
    // 自动清理剪切板时间
    if (!key || key === SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME) {
      SettingsService.get(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, this.autoClearClipboardTime, (value) => {
        this.autoClearClipboardTime = value;
      });
    }
    // 条目是否显示TOTP字段
    if (!key || key === SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP) {
      this.isItemShowTotp = SettingsService.getSync(SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP,
        SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP_DEFAULT);
      // 同步到字段对象，保证数据与展示一致
      if (this.field && this.field.isTotp) {
        this.field.showPlanText = this.isItemShowTotp;
      }
    }
  }

  /**
   * 复制文本到剪贴板
   */
  private copyToClipboard(text: string) {
    ClipboardUtils.copy(KdbxFieldReference.resolveFieldRefsInText(text, FileService.getDatabase(), UIUtils.getTarget(this.entry) as KdbxEntry), this.autoClearClipboardTime);
  }

  /**
   * 获取字段对应的图标
   */
  private getFieldIcon(fieldView: FieldView): ResourceStr {
    if (fieldView.isDownload) {
      return $r("app.media.ic_color_paperclip");
    }
    if (fieldView.isTotp) {
      return $r("app.media.ic_color_totp");
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
      CommonUtils.showToast({ message: $r("app.string.invalid_binary_file"), duration: 2000 });
      return;
    }
    FileUtils.saveLocalFile(fieldView.key, () => {
      return new Promise((resolve, reject) => {
        if (!fieldView.binaryFile) {
          return reject(ResourceManager.getString('app.string.invalid_binary_file'));
        }
        return resolve(fieldView.binaryFile);
      });
    });
  }

  build() {
    Row() {
      // 左侧图标
      Image(this.getFieldIcon(this.field))
        .width(36)
        .height(36)
        .margin({ right: 12 })
      // 中间内容区域
      Column() {
        // 左上角小标题显示标签提示信息（附件类型突出文件名）
        Text(KdbxUtils.getFieldName(this.field.key))
          .fontSize(this.field.isDownload ? 16 : 14)
          .fontColor(this.field.isDownload ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: 4 })

        // 如果是Otp，则显示token码
        if (this.field.isTotp) {
          TotpPreviewComponent({
            isShow: this.isItemShowTotp,
            totpUrl: this.field.otpValue, onChange: (value) => {
              // 仅在允许显示时回写令牌，避免关闭后明文仍被复制
              if (this.isItemShowTotp) {
                this.field.value = value;
              }
            }
          })
            .width('100%')
        } else {
          // 左下角显示具体的值（附件类型优先显示文件大小，样式弱化）
          Text(this.field.isDownload && this.field.fileSizeStr ? this.field.fileSizeStr :
            (this.field.showPlanText ? this.field.value : '******'))
            .fontSize(this.field.isDownload ? 14 : 16)
            .fontColor(this.field.isDownload ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
            .width('100%')
            .copyOption(this.field.showPlanText ? CopyOptions.LocalDevice : CopyOptions.None)
            .textAlign(TextAlign.Start)
            .enableDataDetector(this.field.isProtected ? false : true)
        }

        // 到期剩余天数提示（M2）：已过期红色 / 临期橙色 / 远期次级色
        if (this.field.warningText !== '') {
          Text(this.field.warningText)
            .fontSize(14)
            .fontColor(this.field.warningColor)
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧显示眼镜图标
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

      // 右侧TOTP二维码导出按钮
      if (this.field.isTotp) {
        Image($r('app.media.ic_qrcode'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .margin({ left: 8, right: 8 })
          .onClick((event) => {
            this.totpQrDialogController.open();
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
    // 图片附件整行可点击预览
    .onClick(() => {
      if (this.field.isImageFile) {
        this.imageViewerDialogController.open();
      }
    })
  }
}
