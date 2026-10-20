import { PromptActionBean } from '../loading/PromptActionUtils';
import { YubiKeySlot } from '../../services/otpkey/YubiKeyNfcService';
import { NfcChallengePanel } from './NfcChallengeDialog';

/**
 * 保存前 NFC 挑战弹层参数（ComponentContent 宿主）：
 * 服务层（KdbxSaveService）经 PromptActionUtils 弹出，无需组件上下文
 */
export class NfcSaveChallengeOptions extends PromptActionBean {
  challenge: number[] = [];
  slot: YubiKeySlot = YubiKeySlot.SLOT_2;
  onChallengeResponse: (responseHex: string) => void = () => {
  };
  onCancel: () => void = () => {
  };

  constructor(dialogId: string, challenge: number[], slot: YubiKeySlot,
    onChallengeResponse: (responseHex: string) => void, onCancel: () => void) {
    super(dialogId);
    this.challenge = challenge;
    this.slot = slot;
    this.onChallengeResponse = onChallengeResponse;
    this.onCancel = onCancel;
  }
}

/**
 * 保存前 NFC 挑战弹层 builder（wrapBuilder 供 PromptActionUtils.openCustomDialog 使用）
 */
@Builder
export function NfcSaveChallengeBuilder(options: NfcSaveChallengeOptions) {
  NfcChallengePanel({
    challenge: options.challenge,
    slot: options.slot,
    onChallengeResponse: options.onChallengeResponse,
    onClose: options.onCancel
  })
}
