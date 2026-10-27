/**
 * TOTP二维码导出弹窗
 * 将兼容层归一的 otpauth:// URI 编码为二维码展示，供认证器 App 扫码迁移
 */
import { TotpAlgorithm, TotpConfig, TotpService, TotpType } from '../services/TotpService';
import { TotpQrHelper } from '../common/utils/TotpQrHelper';
import { ClipboardUtils } from '../common/utils/ClipboardUtils';
import { ResourceManager, UIUtils, DialogWindowHelper } from '../common/utils';

const QR_SIZE: number = 260;
const QR_QUIET_ZONE: number = 12;

@CustomDialog
export struct TotpQrDialog {
  @State qrContent: string = '';
  @State errorMessage: string = '';
  @State dialogWidth: string | number = '100%';
  otpAuthUrl: string = '';
  entryTitle: string = '';
  private parsedConfig: TotpConfig | null = null;
  controller: CustomDialogController;
  private windowHelper: DialogWindowHelper = new DialogWindowHelper();

  aboutToAppear() {
    // 注册窗口大小变化监听
    this.windowHelper.register(this.getUIContext(), () => {
      this.updateDialogWidth();
    });
    // 计算弹框宽度
    this.updateDialogWidth();

    this.buildQrContent();
  }

  aboutToDisappear() {
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
   * 构建二维码内容（解析失败/超长为错误态，不渲染残缺二维码）
   */
  private buildQrContent(): void {
    const content: string | null = TotpQrHelper.buildQrContent(this.otpAuthUrl, this.entryTitle);
    if (content === null) {
      this.qrContent = '';
      this.errorMessage = ResourceManager.getString($r('app.string.totp_qr_invalid_uri'));
      this.parsedConfig = TotpService.getInstance().parseUri(this.otpAuthUrl);
      return;
    }
    this.qrContent = content;
    this.errorMessage = '';
    this.parsedConfig = TotpService.getInstance().parseUri(content);
  }

  /**
   * 标题：发行者 > 条目标题 > 通用标题
   */
  private getDialogTitle(): ResourceStr {
    if (this.parsedConfig) {
      const issuer = (this.parsedConfig.issuer ?? '').trim();
      if (issuer !== '') {
        return issuer;
      }
    }
    return this.entryTitle !== '' ? this.entryTitle : $r('app.string.totp_qr_dialog_title');
  }

  /**
   * 参数摘要：issuer: name
   */
  private getSummaryText(): string {
    if (!this.parsedConfig) {
      return '';
    }
    const issuer = (this.parsedConfig.issuer ?? '').trim();
    const name = (this.parsedConfig.name ?? '').trim();
    if (issuer !== '' && name !== '') {
      return `${issuer}: ${name}`;
    }
    return issuer !== '' ? issuer : name;
  }

  /**
   * 参数徽标：算法 · 位数 · 周期
   */
  private getBadgeText(): string {
    if (!this.parsedConfig) {
      return '';
    }
    const algorithm = this.parsedConfig.algorithm ?? TotpAlgorithm.SHA1;
    const digits = this.parsedConfig.digits ?? 6;
    const period = this.parsedConfig.period ?? 30;
    return `${algorithm} · ${digits} · ${period}s`;
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text(this.getDialogTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .onClick(() => {
          this.controller.close();
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)

      // 二维码区域（显式黑码白底，不随深浅色反转）
      if (this.errorMessage === '') {
        Column() {
          QRCode(this.qrContent)
            .color('#ff000000')
            .backgroundColor('#ffffffff')
            .width(QR_SIZE)
            .height(QR_SIZE)
        }
        .padding(QR_QUIET_ZONE)
        .backgroundColor('#ffffffff')
        .borderRadius(12)
        .margin({ top: 8, bottom: 12 })
      } else {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 24, bottom: 24 })
      }

      // 参数摘要与徽标
      if (this.parsedConfig) {
        Row() {
          Text(this.getSummaryText())
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (this.parsedConfig.type === TotpType.STEAM) {
            Text($r('app.string.totp_type_steam'))
              .fontSize(12)
              .fontColor($r('app.color.primary'))
              .margin({ left: 8 })
          }

          Text(this.getBadgeText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      // URI 文本（长按可复制）
      if (this.qrContent !== '') {
        Text(this.qrContent)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .copyOption(CopyOptions.LocalDevice)
          .margin({ top: 8 })
      }

      // 安全警告
      Text($r('app.string.totp_qr_warning'))
        .fontSize(12)
        .fontColor($r('app.color.warn'))
        .width('100%')
        .margin({ top: 12, bottom: 16 })

      // 底部按钮
      Row() {
        Button($r('app.string.totp_qr_copy_uri'), { type: ButtonType.Normal, stateEffect: true })
          .height(40)
          .fontSize(16)
          .layoutWeight(1)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(20)
          .margin({ right: 8 })
          .enabled(this.qrContent !== '')
          .onClick(() => {
            ClipboardUtils.copyAutoClear(this.qrContent);
          })

        Button($r('app.string.close_button_text'), { type: ButtonType.Normal, stateEffect: true })
          .height(40)
          .fontSize(16)
          .layoutWeight(1)
          .fontColor($r('app.color.button_text'))
          .backgroundColor($r('app.color.button_bg_blue'))
          .borderRadius(20)
          .onClick(() => {
            this.controller.close();
          })
      }
      .width('100%')
    }
    .width(this.dialogWidth)
    .backgroundColor($r('app.color.bg_primary'))
    .borderRadius(16)
    .padding({ left: 16, right: 16, bottom: 16 })
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
