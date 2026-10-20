import { describe, expect, it } from '@ohos/hypium';
import {
  buildChallengeApdu,
  buildSelectApdu,
  numbersToHex,
  padChallengeTo64,
  parseChallengeResponse,
  parseSelectResponse,
  YubiKeyChallengeCallbacks,
  YubiKeyNfcError,
  YubiKeyNfcErrorCode,
  YubiKeyNfcService,
  YubiKeySlot
} from '../../../../main/ets/services/otpkey/YubiKeyNfcService';

/**
 * YubiKeyNfcService 单元测试（APDU 构造 / 应答解析 / 会话状态机，无需 NFC 硬件）。
 *
 * 协议对齐 Yubico OTP/HMAC 规范与 KeePassXC 挑战-应答语义：
 * - SELECT：00 A4 04 00 07 A0 00 00 05 27 20 01（按 AID 选择 YubiKey OTP 应用）
 * - HMAC 挑战：00 01 (0x30|0x38) 00 40 <64 字节 PKCS#7 补位挑战>，
 *   INS=0x01（API 请求），P1=槽位 0x30=槽位1 / 0x38=槽位2（对齐 yubikit/ykDroid/KeePassXC）
 * - 应答：20 字节 HMAC + SW 9000
 */

/** 32 字节测试挑战（KDBX4 KDF seed 典型长度） */
const SEED_32: number[] = [
  0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
  0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
  0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
  0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f
];

/** 20 字节测试 HMAC 应答 */
const HMAC_20: number[] = [
  0xde, 0xad, 0xbe, 0xef, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
  0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff
];

/** 捕获错误码（无码时断言失败） */
function catchCode(action: () => void): YubiKeyNfcErrorCode {
  try {
    action();
  } catch (e) {
    const err = e as YubiKeyNfcError;
    return err.code;
  }
  throw new Error('expected throw but no error raised');
}

/** 回调记录器（会话状态机测试用） */
class CallbackRecorder implements YubiKeyChallengeCallbacks {
  public tagDetectedCount: number = 0;
  public successCount: number = 0;
  public successHex: string = '';
  public errorCount: number = 0;
  public lastError: YubiKeyNfcError | null = null;

  onTagDetected(): void {
    this.tagDetectedCount++;
  }

  onSuccess(responseHex: string): void {
    this.successCount++;
    this.successHex = responseHex;
  }

  onError(error: YubiKeyNfcError): void {
    this.errorCount++;
    this.lastError = error;
  }
}

/**
 * 可测子类：仅操作内存会话状态（不触 NFC SDK；elementName 保持 null，
 * stopSession 跳过 tag.off），用于验证会话状态机与回调时序
 */
class TestableYubiKeyNfcService extends YubiKeyNfcService {
  public armSession(callbacks: YubiKeyChallengeCallbacks): void {
    this.callbacks = callbacks;
    this.sessionActive = true;
    this.busy = false;
  }

  /** 模拟 APDU 交换进行中 */
  public armBusy(): void {
    this.busy = true;
  }

  public completeExchangeSuccess(responseHex: string): void {
    this.onExchangeSuccess(responseHex);
  }

  public completeExchangeFailed(e: object): void {
    this.onExchangeFailed(e);
  }

  public isSessionActive(): boolean {
    return this.sessionActive;
  }

  public isBusy(): boolean {
    return this.busy;
  }
}

export default function YubiKeyNfcServiceTest() {
  describe('YubiKeyNfcService', () => {
    it('buildSelectApdu_returnsAidSelect', 0, () => {
      const apdu: number[] = buildSelectApdu();
      expect(apdu.length).assertEqual(12);
      expect(apdu).assertDeepEquals([0x00, 0xA4, 0x04, 0x00, 0x07,
        0xA0, 0x00, 0x00, 0x05, 0x27, 0x20, 0x01]);
    });

    it('padChallengeTo64_pads32ByteSeed', 0, () => {
      const padded: number[] = padChallengeTo64(SEED_32);
      expect(padded.length).assertEqual(64);
      // 前 32 字节 = 原文
      for (let i = 0; i < 32; i++) {
        expect(padded[i]).assertEqual(SEED_32[i]);
      }
      // 尾部 PKCS#7 补位：32 字节的 0x20（64 - 32）
      for (let i = 32; i < 64; i++) {
        expect(padded[i]).assertEqual(0x20);
      }
    });

    it('padChallengeTo64_padsShortChallengeAndKeeps64Max', 0, () => {
      const short: number[] = [0xaa, 0xbb, 0xcc];
      const padded: number[] = padChallengeTo64(short);
      expect(padded.length).assertEqual(64);
      expect(padded[0]).assertEqual(0xaa);
      expect(padded[1]).assertEqual(0xbb);
      expect(padded[2]).assertEqual(0xcc);
      expect(padded[3]).assertEqual(61);
      expect(padded[63]).assertEqual(61);
      // 超长挑战截断至 64（不补位）
      const long: number[] = new Array<number>(80).fill(0x11);
      const truncated: number[] = padChallengeTo64(long);
      expect(truncated.length).assertEqual(64);
      for (let i = 0; i < 64; i++) {
        expect(truncated[i]).assertEqual(0x11);
      }
    });

    it('padChallengeTo64_exact64ByteChallengeNoPadding', 0, () => {
      const exact: number[] = new Array<number>(64).fill(0x33);
      const padded: number[] = padChallengeTo64(exact);
      expect(padded.length).assertEqual(64);
      for (let i = 0; i < 64; i++) {
        expect(padded[i]).assertEqual(0x33);
      }
    });

    it('buildChallengeApdu_slot1UsesP1_30', 0, () => {
      const apdu: number[] = buildChallengeApdu(YubiKeySlot.SLOT_1, SEED_32);
      expect(apdu.length).assertEqual(5 + 64);
      expect(apdu[0]).assertEqual(0x00); // CLA
      expect(apdu[1]).assertEqual(0x01); // INS = API 请求
      expect(apdu[2]).assertEqual(0x30); // P1 = 槽位 1
      expect(apdu[3]).assertEqual(0x00); // P2
      expect(apdu[4]).assertEqual(0x40); // Lc
      // 数据区前 32 字节 = seed 原文
      for (let i = 0; i < 32; i++) {
        expect(apdu[5 + i]).assertEqual(SEED_32[i]);
      }
      // 数据区尾部 PKCS#7 补位（32 字节 seed → 0x20）
      expect(apdu[5 + 63]).assertEqual(0x20);
    });

    it('buildChallengeApdu_slot2UsesP1_38', 0, () => {
      const apdu: number[] = buildChallengeApdu(YubiKeySlot.SLOT_2, SEED_32);
      expect(apdu.length).assertEqual(69);
      expect(apdu[1]).assertEqual(0x01);
      expect(apdu[2]).assertEqual(0x38); // P1 = 槽位 2
      expect(apdu[3]).assertEqual(0x00);
      expect(apdu[4]).assertEqual(0x40);
    });

    it('parseSelectResponse_accepts9000', 0, () => {
      // 任选一个带文件信息的应答 + 90 00
      parseSelectResponse([0x6f, 0x17, 0x90, 0x00]);
      // 仅 SW
      parseSelectResponse([0x90, 0x00]);
    });

    it('parseSelectResponse_rejectsFailureStatus', 0, () => {
      // 6A 82：应用未找到
      expect(catchCode(() => parseSelectResponse([0x6a, 0x82]))).assertEqual(YubiKeyNfcErrorCode.SELECT_FAILED);
      // 69 82：安全状态不满足
      expect(catchCode(() => parseSelectResponse([0x69, 0x82]))).assertEqual(YubiKeyNfcErrorCode.SELECT_FAILED);
      // 空应答
      expect(catchCode(() => parseSelectResponse([]))).assertEqual(YubiKeyNfcErrorCode.INVALID_RESPONSE);
    });

    it('parseChallengeResponse_returns20ByteHmac', 0, () => {
      const response: number[] = HMAC_20.concat([0x90, 0x00]);
      const hmac: number[] = parseChallengeResponse(response);
      expect(hmac.length).assertEqual(20);
      expect(hmac).assertDeepEquals(HMAC_20);
    });

    it('parseChallengeResponse_classifiesFailures', 0, () => {
      // SW 69 85：使用条件不满足（槽位未配置）
      const wrongSw: number[] = HMAC_20.concat([0x69, 0x85]);
      expect(catchCode(() => parseChallengeResponse(wrongSw)))
        .assertEqual(YubiKeyNfcErrorCode.CHALLENGE_FAILED);
      // SW 6A 80：数据域错误
      const badData: number[] = HMAC_20.concat([0x6a, 0x80]);
      expect(catchCode(() => parseChallengeResponse(badData)))
        .assertEqual(YubiKeyNfcErrorCode.CHALLENGE_FAILED);
      // SW 正确但长度不符
      const wrongLen: number[] = HMAC_20.slice(0, 18).concat([0x90, 0x00]);
      expect(catchCode(() => parseChallengeResponse(wrongLen)))
        .assertEqual(YubiKeyNfcErrorCode.INVALID_RESPONSE);
    });

    it('numbersToHex_lowerCaseHex', 0, () => {
      expect(numbersToHex([0x00, 0x0f, 0xa5, 0xff])).assertEqual('000fa5ff');
      expect(numbersToHex(HMAC_20.slice(0, 2))).assertEqual('dead');
      expect(numbersToHex([])).assertEqual('');
    });

    it('yubiKeyNfcError_isErrorWithCode', 0, () => {
      const error: YubiKeyNfcError = new YubiKeyNfcError(YubiKeyNfcErrorCode.NFC_DISABLED, 'off');
      expect(error instanceof Error).assertTrue();
      expect(error.name).assertEqual('YubiKeyNfcError');
      expect(error.code).assertEqual(YubiKeyNfcErrorCode.NFC_DISABLED);
      expect(error.message).assertEqual('off');
    });

    it('onExchangeSuccess_firesCallbackAndStopsSession', 0, () => {
      const service = new TestableYubiKeyNfcService();
      const recorder = new CallbackRecorder();
      service.armSession(recorder);
      service.armBusy();
      service.completeExchangeSuccess('aabbcc');
      // 回调触发且回调时会话已停（恢复卡模拟）
      expect(recorder.successCount).assertEqual(1);
      expect(recorder.successHex).assertEqual('aabbcc');
      expect(service.isSessionActive()).assertFalse();
      expect(service.isBusy()).assertFalse();
    });

    it('onExchangeFailed_keepsSessionAndResetsBusy', 0, () => {
      const service = new TestableYubiKeyNfcService();
      const recorder = new CallbackRecorder();
      service.armSession(recorder);
      service.armBusy();
      service.completeExchangeFailed(new YubiKeyNfcError(YubiKeyNfcErrorCode.TAG_DISCONNECTED, 'gone'));
      // 瞬时错误（移卡）：会话保持注册允许重贴，busy 复位
      expect(recorder.errorCount).assertEqual(1);
      expect(recorder.lastError?.code).assertEqual(YubiKeyNfcErrorCode.TAG_DISCONNECTED);
      expect(service.isBusy()).assertFalse();
      expect(service.isSessionActive()).assertTrue();
    });

    it('onExchangeFailed_wrapsNonYubikeyErrorAsChallengeFailed', 0, () => {
      const service = new TestableYubiKeyNfcService();
      const recorder = new CallbackRecorder();
      service.armSession(recorder);
      service.completeExchangeFailed(new Error('boom'));
      expect(recorder.errorCount).assertEqual(1);
      expect(recorder.lastError instanceof YubiKeyNfcError).assertTrue();
      expect(recorder.lastError?.code).assertEqual(YubiKeyNfcErrorCode.CHALLENGE_FAILED);
      // 会话保持，可重试
      expect(service.isSessionActive()).assertTrue();
    });

    it('cancel_dropsLateExchangeResults', 0, () => {
      const service = new TestableYubiKeyNfcService();
      const recorder = new CallbackRecorder();
      service.armSession(recorder);
      service.armBusy();
      // 用户取消会话后，迟到的成功/失败结果不得触发回调
      service.cancel();
      service.completeExchangeSuccess('aabbcc');
      service.completeExchangeFailed(new Error('late'));
      expect(recorder.successCount).assertEqual(0);
      expect(recorder.errorCount).assertEqual(0);
      expect(service.isSessionActive()).assertFalse();
      expect(service.isBusy()).assertFalse();
    });
  });
}
