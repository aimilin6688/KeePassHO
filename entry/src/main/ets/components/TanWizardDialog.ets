import { ResourceManager, UIUtils, DialogWindowHelper } from '../common/utils';

/**
 * TAN 批量添加向导（P2-4 M3，对齐 KeePass TanWizardForm）：
 * - TAN 文本：多行粘贴，按"字符集之外的字符"切分为多个 TAN
 * - 字符集：默认 A-Za-z0-9-（KeePass 默认值）
 * - 起始序号：写入 UserName 字段，默认 1
 * - 实时预览将创建的 TAN 数量
 */
@CustomDialog
export struct TanWizardDialog {
  @State tanText: string = '';
  @State charset: string = '';
  @State startIndexText: string = '1';
  @State tanCount: number = 0;
  @State dialogWidth: string | number = '100%';

  controller: CustomDialogController
  private windowHelper: DialogWindowHelper = new DialogWindowHelper();
  onConfirm: (tans: Array<string>, startIndex: number) => void = () => {
  }
  onCancel: () => void = () => {
  }

  aboutToAppear(): void {
    // 注册窗口大小变化监听
    this.windowHelper.register(this.getUIContext(), () => {
      this.updateDialogWidth();
    });
    this.updateDialogWidth();
    this.charset = ResourceManager.getString($r('app.string.tan_wizard_charset_default'));
    this.refreshPreview();
  }

  aboutToDisappear(): void {
    this.windowHelper.unregister();
  }

  /**
   * 更新弹框宽度
   */
  private updateDialogWidth(): void {
    const widthConfig = UIUtils.calculateDialogWidth(this.getUIContext(), this.windowHelper.windowWidth);
    this.dialogWidth = widthConfig.width;
  }

  /**
   * 按字符集解析 TAN 片段（字符集之外的字符作为分隔符，对齐 KeePass TanWizardForm）
   */
  private parseTans(): Array<string> {
    const charset = this.charset.trim();
    if (!charset || !this.tanText) {
      return [];
    }
    const separator = new RegExp('[^' + charset + ']+', 'g');
    return this.tanText.split(separator).filter((tan: string) => tan.length > 0);
  }

  /**
   * 解析起始序号（非法输入回退 1）
   */
  private parseStartIndex(): number {
    const parsed = parseInt(this.startIndexText, 10);
    if (isNaN(parsed) || parsed < 0) {
      return 1;
    }
    return parsed;
  }

  /**
   * 刷新预览计数
   */
  private refreshPreview(): void {
    this.tanCount = this.parseTans().length;
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r('app.string.tan_wizard_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)

        Blank()

        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor('#666666')
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .onClick(() => {
          this.controller.close()
          if (this.onCancel) {
            this.onCancel()
          }
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r("app.color.bg_primary"))
      .borderRadius({ topLeft: 16, topRight: 16 })

      // 输入区域
      Scroll() {
        Column() {
          // TAN 文本
          Column() {
            Text($r('app.string.tan_wizard_text_label'))
              .fontSize(14)
              .fontColor($r("app.color.text_secondary"))
              .width('100%')
              .margin({ bottom: 8 })
            TextArea({ placeholder: $r('app.string.tan_wizard_text_placeholder'), text: this.tanText })
              .width('100%')
              .height(120)
              .padding(12)
              .fontSize(16)
              .backgroundColor($r("app.color.card_bg"))
              .borderRadius(12)
              .onChange((value: string) => {
                this.tanText = value;
                this.refreshPreview();
              })
          }
          .width('100%')
          .margin({ bottom: 16 })

          // 字符集
          Column() {
            Text($r('app.string.tan_wizard_charset_label'))
              .fontSize(14)
              .fontColor($r("app.color.text_secondary"))
              .width('100%')
              .margin({ bottom: 8 })
            TextInput({ text: this.charset })
              .width('100%')
              .height(48)
              .padding({ left: 12, right: 12 })
              .fontSize(16)
              .backgroundColor($r("app.color.card_bg"))
              .borderRadius(12)
              .onChange((value: string) => {
                this.charset = value.trim();
                this.refreshPreview();
              })
          }
          .width('100%')
          .margin({ bottom: 16 })

          // 起始序号
          Column() {
            Text($r('app.string.tan_wizard_start_index_label'))
              .fontSize(14)
              .fontColor($r("app.color.text_secondary"))
              .width('100%')
              .margin({ bottom: 8 })
            TextInput({ text: this.startIndexText })
              .width('100%')
              .height(48)
              .padding({ left: 12, right: 12 })
              .fontSize(16)
              .backgroundColor($r("app.color.card_bg"))
              .borderRadius(12)
              .type(InputType.Number)
              .onChange((value: string) => {
                this.startIndexText = value.trim();
              })
          }
          .width('100%')

          // 预览 / 错误提示
          Text(this.tanCount > 0
            ? ResourceManager.getString($r('app.string.tan_wizard_preview'), this.tanCount, this.parseStartIndex())
            : $r('app.string.tan_wizard_empty_error'))
            .fontSize(14)
            .fontColor(this.tanCount > 0 ? $r("app.color.text_secondary") : $r("app.color.error"))
            .width('100%')
            .margin({ top: 12 })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16 })
      }
      .layoutWeight(1)
      .constraintSize({ maxHeight: 360 })
      .scrollBarBarState(BarState.Auto)
      .width('100%')
      .backgroundColor($r("app.color.bg_primary"))

      // 底部按钮
      Row() {
        Button($r('app.string.cancel_button_text'))
          .onClick(() => {
            this.controller.close()
            if (this.onCancel) {
              this.onCancel()
            }
          })
          .backgroundColor(Color.Gray)
          .fontColor(Color.White)
          .width('45%')
          .height(40)
          .borderRadius(20)

        Button($r("app.string.confirm_button_text"))
          .enabled(this.tanCount > 0)
          .onClick(() => {
            const tans = this.parseTans();
            if (tans.length === 0) {
              return;
            }
            this.controller.close()
            this.onConfirm(tans, this.parseStartIndex())
          })
          .backgroundColor(this.tanCount > 0 ? $r("app.color.button_bg_blue") : $r("app.color.button_bg_disabled"))
          .fontColor($r('app.color.button_text'))
          .width('45%')
          .height(40)
          .borderRadius(20)
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: 16,
        bottom: 30
      })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor($r("app.color.bg_primary"))
    }
    .width(this.dialogWidth)
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
