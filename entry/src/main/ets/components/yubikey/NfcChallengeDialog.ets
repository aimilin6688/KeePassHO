import { common } from '@kit.AbilityKit';
import { ResourceManager } from '../../common/utils';
import {
  YubiKeyChallengeCallbacks,
  YubiKeyNfcError,
  YubiKeyNfcErrorCode,
  YubiKeyNfcService,
  YubiKeySlot
} from '../../services/otpkey/YubiKeyNfcService';

const TAG = 'NfcChallengeDialog';

/**
 * YubiKey NFC 挑战-应答贴卡面板（纯组件：可宿于 @CustomDialog 或 ComponentContent）
 *
 * 生命周期驱动 NFC 读卡器会话：
 * - aboutToAppear：开启挑战会话（进入读卡器模式）
 * - 错误态保持会话：可重贴重试（Retry 重新开启）
 * - 成功/取消/aboutToDisappear：结束会话（退出读卡器模式，恢复卡模拟）
 *
 * 弹层关闭由宿主负责：onChallengeResponse / onClose 触发后由宿主关闭所在弹层
 */
@Component
export struct NfcChallengePanel {
  // waiting | verifying | error
  @State status: string = 'waiting';
  @State errorText: string = '';
  public challenge: number[] = [];
  public slot: YubiKeySlot = YubiKeySlot.SLOT_2;
  public onChallengeResponse: (responseHex: string) => void = () => {
  };
  public onClose: () => void = () => {
  };

  aboutToAppear() {
    this.startSession();
  }

  aboutToDisappear() {
    YubiKeyNfcService.getInstance().cancel();
  }

  /**
   * 开启（或重开）挑战会话
   */
  private startSession(): void {
    this.status = 'waiting';
    this.errorText = '';
    const callbacks: YubiKeyChallengeCallbacks = {
      onTagDetected: () => {
        this.status = 'verifying';
      },
      onSuccess: (responseHex: string) => {
        this.onChallengeResponse(responseHex);
      },
      onError: (error: YubiKeyNfcError) => {
        this.status = 'error';
        this.errorText = this.errorTextOf(error);
      }
    };
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    YubiKeyNfcService.getInstance().startChallenge(context, this.challenge, this.slot, callbacks);
  }

  /**
   * 错误码 → 提示文案
   */
  private errorTextOf(error: YubiKeyNfcError): string {
    switch (error.code) {
      case YubiKeyNfcErrorCode.NFC_UNAVAILABLE:
        return ResourceManager.getString($r('app.string.yubikey_nfc_error_unavailable'));
      case YubiKeyNfcErrorCode.NFC_DISABLED:
        return ResourceManager.getString($r('app.string.yubikey_nfc_error_disabled'));
      case YubiKeyNfcErrorCode.NOT_ISO_DEP:
        return ResourceManager.getString($r('app.string.yubikey_nfc_error_not_iso_dep'));
      case YubiKeyNfcErrorCode.SELECT_FAILED:
        return ResourceManager.getString($r('app.string.yubikey_nfc_error_select'));
      case YubiKeyNfcErrorCode.INVALID_RESPONSE:
        return ResourceManager.getString($r('app.string.yubikey_nfc_error_invalid'));
      case YubiKeyNfcErrorCode.TAG_DISCONNECTED:
        return ResourceManager.getString($r('app.string.yubikey_nfc_error_disconnected'));
      default:
        return ResourceManager.getString($r('app.string.yubikey_nfc_error_challenge'));
    }
  }

  build() {
    Column({ space: 16 }) {
      // 顶部标题栏（与其他对话框统一样式：标题左侧对齐、关闭按钮右侧）
      Row() {
        Text($r('app.string.yubikey_nfc_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)

      // NFC 感应图形
      Stack() {
        Circle()
          .width(88)
          .height(88)
          .fillOpacity(0)
          .stroke($r('app.color.button_bg_blue'))
          .strokeWidth(2)
        Circle()
          .width(64)
          .height(64)
          .fillOpacity(0)
          .stroke($r('app.color.button_bg_blue'))
          .strokeWidth(2)
          .opacity(0.5)
        Text('NFC')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.button_bg_blue'))
      }
      .margin({ top: 8, bottom: 8 })

      // 状态文案
      if (this.status === 'verifying') {
        Text($r('app.string.yubikey_nfc_verifying'))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      } else if (this.status === 'error') {
        Text(this.errorText)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .margin({ left: 8, right: 8 })
      } else {
        Text($r('app.string.yubikey_nfc_waiting'))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ left: 8, right: 8 })
      }

      // 按钮组
      Row({ space: 12 }) {
        Button($r('app.string.cancel_button_text'))
          .layoutWeight(1)
          .height(40)
          .fontSize(16)
          .fontColor($r('app.color.button_text'))
          .borderRadius(20)
          .backgroundColor($r('app.color.bg_secondary'))
          .id('btn_nfc_challenge_cancel')
          .onClick(() => {
            this.onClose();
          })

        Button($r('app.string.retry_button_text'))
          .layoutWeight(1)
          .height(40)
          .fontSize(16)
          .fontColor($r('app.color.button_text'))
          .borderRadius(20)
          .backgroundColor($r('app.color.button_bg_blue'))
          .id('btn_nfc_challenge_retry')
          .enabled(this.status === 'error')
          .opacity(this.status === 'error' ? 1 : 0.4)
          .onClick(() => {
            this.startSession();
          })
      }
      .width('100%')
      .margin({ top: 8, bottom: 8 })
    }
    .width('86%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 24, right: 24, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.bg_primary'))
    .borderRadius(24)
    .shadow(ShadowStyle.OUTER_DEFAULT_LG)
  }
}

/**
 * YubiKey NFC 挑战-应答贴卡弹层（@CustomDialog 宿主，解锁页使用）
 * 对外 API 与历史版本保持一致：challenge / slot / onChallengeResponse / onCancel
 */
@CustomDialog
export struct NfcChallengeDialog {
  public challenge: number[] = [];
  public slot: YubiKeySlot = YubiKeySlot.SLOT_2;
  public onChallengeResponse: (responseHex: string) => void = () => {
  };
  public onCancel: () => void = () => {
  };
  private controller: CustomDialogController;

  build() {
    NfcChallengePanel({
      challenge: this.challenge,
      slot: this.slot,
      onChallengeResponse: (responseHex: string) => {
        this.controller.close();
        this.onChallengeResponse(responseHex);
      },
      onClose: () => {
        this.controller.close();
        this.onCancel();
      }
    })
  }
}
