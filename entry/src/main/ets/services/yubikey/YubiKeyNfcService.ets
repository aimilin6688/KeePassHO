import { tag, nfcController } from '@kit.ConnectivityKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'YubiKeyNfcService';

/**
 * YubiKey 挑战槽位（与 KeePassXC 数据库安全设置中配置的 HMAC 槽位一致）
 * 事实默认：YubiKey 出厂 OTP 占用槽位 1（短按），挑战-应答通常配置在槽位 2（长按）
 */
export enum YubiKeySlot {
  /** 槽位 1（短按） */
  SLOT_1 = 1,
  /** 槽位 2（长按） */
  SLOT_2 = 2
}

/**
 * YubiKey NFC 挑战-应答错误码
 */
export enum YubiKeyNfcErrorCode {
  /** 设备不支持 NFC */
  NFC_UNAVAILABLE = 'nfc_unavailable',
  /** NFC 开关未打开 */
  NFC_DISABLED = 'nfc_disabled',
  /** 读到的标签不支持 ISO-DEP（非 YubiKey） */
  NOT_ISO_DEP = 'not_iso_dep',
  /** 选择 YubiKey 应用（SELECT AID）被拒绝 */
  SELECT_FAILED = 'select_failed',
  /** HMAC 挑战指令执行失败 */
  CHALLENGE_FAILED = 'challenge_failed',
  /** 应答格式不符合预期 */
  INVALID_RESPONSE = 'invalid_response',
  /** 通信中断（贴卡中断/中途移开） */
  TAG_DISCONNECTED = 'tag_disconnected'
}

/**
 * YubiKey NFC 挑战-应答错误
 */
export class YubiKeyNfcError extends Error {
  readonly code: YubiKeyNfcErrorCode;

  constructor(code: YubiKeyNfcErrorCode, message: string) {
    super(message);
    this.name = 'YubiKeyNfcError';
    this.code = code;
  }
}

/**
 * 挑战-应答会话回调
 */
export interface YubiKeyChallengeCallbacks {
  /** 读到标签（开始 APDU 交换，UI 切换"正在读取"态） */
  onTagDetected: () => void;
  /** 挑战成功（返回 HMAC 应答的小写 hex，40 字符） */
  onSuccess: (responseHex: string) => void;
  /** 会话内错误（会话保持注册，可重贴重试；致命错误不会走到这里） */
  onError: (error: YubiKeyNfcError) => void;
}

/** YubiKey OTP 应用 AID：A0 00 00 05 27 20 01 */
const YUBIKEY_AID: number[] = [0xA0, 0x00, 0x00, 0x05, 0x27, 0x20, 0x01];

/** HMAC-SHA1 应答长度（字节） */
const HMAC_RESPONSE_LENGTH: number = 20;

/** 挑战值补零长度（HMAC-SHA1 块大小） */
const CHALLENGE_PAD_LENGTH: number = 64;

/** APDU 状态字 9000（成功） */
const SW_OK: number = 0x9000;

/**
 * 构造 SELECT（按 AID 选择）YubiKey OTP 应用的 APDU
 * 纯函数，便于无硬件单元测试
 */
export function buildSelectApdu(): number[] {
  const apdu: number[] = [0x00, 0xA4, 0x04, 0x00, YUBIKEY_AID.length];
  return apdu.concat(YUBIKEY_AID);
}

/**
 * 挑战值补零至 64 字节（YubiKey HMAC 槽位挑战语义）
 * @param challenge 挑战原文（KDBX4 KDF seed）
 */
export function padChallengeTo64(challenge: number[]): number[] {
  const padded: number[] = [];
  const length = Math.min(challenge.length, CHALLENGE_PAD_LENGTH);
  for (let i = 0; i < length; i++) {
    padded.push(challenge[i] & 0xFF);
  }
  for (let i = length; i < CHALLENGE_PAD_LENGTH; i++) {
    padded.push(0);
  }
  return padded;
}

/**
 * 构造 HMAC 挑战 APDU：00 INS 00 00 40 <64 字节补零挑战>
 * INS：槽位 1 = 0x30，槽位 2 = 0x38
 */
export function buildChallengeApdu(slot: YubiKeySlot, challenge: number[]): number[] {
  const ins = slot === YubiKeySlot.SLOT_1 ? 0x30 : 0x38;
  const apdu: number[] = [0x00, ins, 0x00, 0x00, CHALLENGE_PAD_LENGTH];
  return apdu.concat(padChallengeTo64(challenge));
}

/**
 * 从应答尾部解析状态字
 */
function statusWordOf(response: number[]): number {
  if (response.length < 2) {
    return -1;
  }
  return (response[response.length - 2] << 8) | response[response.length - 1];
}

/**
 * 校验 SELECT 应答（成功 = SW 9000）
 * @throws YubiKeyNfcError SELECT_FAILED / INVALID_RESPONSE
 */
export function parseSelectResponse(response: number[]): void {
  if (response.length < 2) {
    throw new YubiKeyNfcError(YubiKeyNfcErrorCode.INVALID_RESPONSE, 'Empty select response');
  }
  if (statusWordOf(response) !== SW_OK) {
    throw new YubiKeyNfcError(YubiKeyNfcErrorCode.SELECT_FAILED,
      `Select AID rejected, SW=${statusWordOf(response).toString(16)}`);
  }
}

/**
 * 解析 HMAC 挑战应答（20 字节 HMAC + SW 9000）
 * @returns 20 字节 HMAC 应答
 * @throws YubiKeyNfcError CHALLENGE_FAILED / INVALID_RESPONSE
 */
export function parseChallengeResponse(response: number[]): number[] {
  const sw = statusWordOf(response);
  if (sw !== SW_OK) {
    throw new YubiKeyNfcError(YubiKeyNfcErrorCode.CHALLENGE_FAILED,
      `Challenge rejected, SW=${sw.toString(16)}`);
  }
  if (response.length !== HMAC_RESPONSE_LENGTH + 2) {
    throw new YubiKeyNfcError(YubiKeyNfcErrorCode.INVALID_RESPONSE,
      `Unexpected response length: ${response.length}`);
  }
  return response.slice(0, HMAC_RESPONSE_LENGTH);
}

/**
 * 字节数组转小写 hex 字符串
 */
export function numbersToHex(bytes: number[]): string {
  let hex = '';
  for (const b of bytes) {
    hex += (b < 0x10 ? '0' : '') + (b & 0xFF).toString(16);
  }
  return hex;
}

/**
 * 把 NFC SDK 抛出的 BusinessError 映射为 YubiKeyNfcError
 */
function mapBusinessError(error: BusinessError): YubiKeyNfcError {
  // 3100201 标签状态异常 / 3100204 标签 I/O 失败：贴卡中断或中途移开
  if (error.code === 3100201 || error.code === 3100204) {
    return new YubiKeyNfcError(YubiKeyNfcErrorCode.TAG_DISCONNECTED, error.message);
  }
  return new YubiKeyNfcError(YubiKeyNfcErrorCode.CHALLENGE_FAILED, error.message);
}

/**
 * YubiKey NFC 挑战-应答服务
 *
 * 会话生命周期由调用方（NfcChallengeDialog）驱动：
 * startChallenge → （可多次重贴，onError 后会话保持）→ 成功后自动结束 / cancel 结束
 */
export class YubiKeyNfcService {
  private static instance: YubiKeyNfcService = new YubiKeyNfcService();

  /** 会话是否处于读卡器模式 */
  private sessionActive: boolean = false;
  /** 单次 APDU 交换进行中（防同卡重复分发重入） */
  private busy: boolean = false;
  private elementName: bundleManager.ElementName | null = null;
  private challenge: number[] = [];
  private slot: YubiKeySlot = YubiKeySlot.SLOT_2;
  private callbacks: YubiKeyChallengeCallbacks | null = null;

  public static getInstance(): YubiKeyNfcService {
    return YubiKeyNfcService.instance;
  }

  /**
   * 开始挑战-应答会话：进入读卡器模式，读到 YubiKey 后执行
   * SELECT AID + HMAC 挑战两步 APDU 交换
   * @param context UIAbility 上下文（ElementName 来源）
   * @param challenge 挑战原文（KDBX 头预解析得到的 KDF seed 字节）
   * @param slot YubiKey HMAC 槽位
   * @param callbacks 会话回调（致命错误经 onError 上报且会话未建立）
   */
  public startChallenge(context: common.UIAbilityContext, challenge: number[], slot: YubiKeySlot,
    callbacks: YubiKeyChallengeCallbacks): void {
    // 重入保护：先结束旧会话
    this.stopSession();
    if (!canIUse('SystemCapability.Communication.NFC.Tag') || !nfcController.isNfcAvailable()) {
      callbacks.onError(new YubiKeyNfcError(YubiKeyNfcErrorCode.NFC_UNAVAILABLE, 'NFC not available'));
      return;
    }
    if (!nfcController.isNfcOpen()) {
      callbacks.onError(new YubiKeyNfcError(YubiKeyNfcErrorCode.NFC_DISABLED, 'NFC is off'));
      return;
    }
    const abilityInfo: bundleManager.AbilityInfo = context.abilityInfo;
    this.elementName = {
      bundleName: abilityInfo.bundleName,
      moduleName: abilityInfo.moduleName,
      abilityName: abilityInfo.name
    };
    this.challenge = challenge;
    this.slot = slot;
    this.callbacks = callbacks;
    this.busy = false;
    try {
      const discTech: number[] = [tag.NFC_A, tag.NFC_B];
      tag.on('readerMode', this.elementName, discTech, (error: BusinessError, tagInfo: tag.TagInfo) => {
        this.handleTagDiscovered(error, tagInfo);
      });
      this.sessionActive = true;
      hilog.info(DOMAIN, TAG, 'Challenge session started, slot=%{public}d', slot);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'tag.on readerMode failed: %{public}d %{public}s', err.code, err.message);
      this.callbacks = null;
      callbacks.onError(mapBusinessError(err));
    }
  }

  /**
   * 结束挑战-应答会话（退出读卡器模式，恢复卡模拟）；未开启时安全空操作
   */
  public cancel(): void {
    this.stopSession();
  }

  private stopSession(): void {
    this.busy = false;
    if (!this.sessionActive) {
      return;
    }
    this.sessionActive = false;
    const elementName = this.elementName;
    this.callbacks = null;
    if (elementName !== null) {
      try {
        tag.off('readerMode', elementName);
      } catch (e) {
        const err = e as BusinessError;
        hilog.warn(DOMAIN, TAG, 'tag.off readerMode failed: %{public}d %{public}s', err.code, err.message);
      }
    }
    hilog.info(DOMAIN, TAG, 'Challenge session stopped');
  }

  private handleTagDiscovered(error: BusinessError, tagInfo: tag.TagInfo): void {
    if (!this.sessionActive || this.busy || !tagInfo) {
      return;
    }
    const callbacks = this.callbacks;
    if (callbacks === null) {
      return;
    }
    if (error) {
      hilog.error(DOMAIN, TAG, 'readerMode dispatch error: %{public}d %{public}s', error.code, error.message);
      callbacks.onError(mapBusinessError(error));
      return;
    }
    this.busy = true;
    callbacks.onTagDetected();
    this.exchangeWithYubiKey(tagInfo)
      .then((responseHex: string) => {
        // 成功即结束会话（恢复卡模拟）
        this.stopSession();
        const cb = this.callbacks;
        if (cb !== null) {
          cb.onSuccess(responseHex);
        }
      })
      .catch((e: object) => {
        // 会话保持注册：瞬时错误（移卡）可直接重贴重试
        this.busy = false;
        const yubikeyError: YubiKeyNfcError = e instanceof YubiKeyNfcError
          ? e as YubiKeyNfcError
          : new YubiKeyNfcError(YubiKeyNfcErrorCode.CHALLENGE_FAILED, `${e}`);
        hilog.warn(DOMAIN, TAG, 'YubiKey exchange failed: %{public}s', yubikeyError.message);
        const cb = this.callbacks;
        if (cb !== null) {
          cb.onError(yubikeyError);
        }
      });
  }

  /**
   * 与 YubiKey 完成 SELECT + HMAC 挑战两步 APDU 交换
   * @returns HMAC 应答的小写 hex
   */
  private async exchangeWithYubiKey(tagInfo: tag.TagInfo): Promise<string> {
    const technologies: number[] = tagInfo.technology;
    let hasIsoDep: boolean = false;
    for (const tech of technologies) {
      if (tech === tag.ISO_DEP) {
        hasIsoDep = true;
        break;
      }
    }
    if (!hasIsoDep) {
      throw new YubiKeyNfcError(YubiKeyNfcErrorCode.NOT_ISO_DEP, 'Tag is not ISO-DEP');
    }
    const isoDep: tag.IsoDepTag = tag.getIsoDep(tagInfo);
    try {
      isoDep.connect();
      const selectResponse: number[] = await isoDep.transmit(buildSelectApdu());
      parseSelectResponse(selectResponse);
      const challengeResponse: number[] = await isoDep.transmit(buildChallengeApdu(this.slot, this.challenge));
      const hmac: number[] = parseChallengeResponse(challengeResponse);
      return numbersToHex(hmac);
    } catch (e) {
      if (e instanceof YubiKeyNfcError) {
        throw e;
      }
      throw mapBusinessError(e as BusinessError);
    }
  }
}
