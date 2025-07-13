import { pasteboard } from "@kit.BasicServicesKit";
import { PromptAction } from "@kit.ArkUI";
import KdbxUtils from "../common/utils/KdbxUtils";
import { KdbxEntry } from "kdbxweb";

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

  constructor(key: string, value: string, isProtected: boolean, isCopy: boolean) {
    this.key = key;
    this.value = value;
    this.isProtected = isProtected;
    this.isCopy = isCopy;
    this.showPlanText = !this.isProtected;
  }
}


@Component
export struct EntryViewFieldItem {
  @ObjectLink field: FieldView;
  @State entry:KdbxEntry | null = null;

  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  /**
   * 复制文本到剪贴板
   */
  private copyToClipboard(text: string) {
    let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    // 获取系统剪贴板实例
    const pasteboardData = pasteboard.createData('text/plain', text);
    // 将数据写入剪贴板
    systemPasteboard.setData(pasteboardData, (error, data) => {
      if (error) {
        console.error(`复制到剪贴板失败: ${error}`);
        this.promptAction.showToast({ message: `复制失败: ${error}` });
      } else {
        this.promptAction.showToast({ message: '已复制', duration: 2000 });
      }
    });
  }

  /**
   * 获取字段对应的图标
   */
  private getFieldIcon(key: string): ResourceStr {
    switch (key) {
      case KdbxUtils.FIELD_TITLE:
    return $r('app.media.ic_title');
      case KdbxUtils.FIELD_USERNAME:
    return $r('app.media.ic_user');
      case KdbxUtils.FIELD_PASSWORD:
    return $r('app.media.ic_password');
      case KdbxUtils.FIELD_URL:
    return $r('app.media.ic_url');
      case KdbxUtils.FIELD_NOTES:
    return $r('app.media.ic_notes');
      case KdbxUtils.GROUP_NAME:
        return this.getGroupIcon();
      case KdbxUtils.FIELD_CREATION_TIME:
        return $r('sys.media.ohos_ic_public_clock');
      case KdbxUtils.FIELD_LASTMOD_TIME:
        return $r('sys.media.ohos_ic_public_clock');
      default:
      return $r('app.media.ic_note');
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
    return $r('app.media.ic_folder');
  }


  build(){
    Row() {
      // 左侧图标
      Image(this.getFieldIcon(this.field.key))
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
          .textOverflow({ overflow: TextOverflow.None })
          .maxLines(this.field.isProtected ? 1 : 10)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧复制按钮
      if (this.field.value && this.field.isProtected) {
        Image(this.field.showPlanText ? $r('app.media.ic_eye_off') : $r('app.media.ic_eye'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .margin({ right: 15 })
          .onClick((event) => {
            this.field.showPlanText = !this.field.showPlanText;
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
          })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(8)
    .padding(12)
    .margin({ bottom: 8 })
    .onClick(() => {
      if (this.field.value && this.field.isCopy) {
        this.copyToClipboard(this.field.value);
      }
    })
  }

}