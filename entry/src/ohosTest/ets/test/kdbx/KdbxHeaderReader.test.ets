import { describe, expect, it } from '@ohos/hypium';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { ByteUtils, Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import {
  KdbxHeaderParseError,
  KdbxHeaderParseErrorCode,
  KdbxHeaderReader
} from '../../../../main/ets/services/kdbx/KdbxHeaderReader';

/**
 * KdbxHeaderReader（KDBX 头预解析，YubiKey 挑战-应答两阶段流程阶段一）单元测试。
 *
 * 字节布局对齐 kdbxweb KdbxHeader / VarDictionary（KDBX4 规范）：
 * - 外层字段：id u8 + 长度 u32 LE + 数据，id 0 结束；字段 11 = KdfParameters
 * - VarDictionary：版本 u16 LE（0x0100）+ 条目（type u8，0 结束；keyLen i32；key；valLen i32；value）
 * - KDF seed 键 'S'（Argon2 salt 与 AES-KDF seed 同键），'$UUID' 为 16 字节算法标识
 *
 * E2E：kdbxweb 建带挑战-应答回调的库 → save → 预解析提取 KDF seed →
 * 模拟 YubiKey HMAC-SHA1 应答 → 经 challengeResponseHex 语义（固定应答回调）两阶段重开成功。
 */

/** E2E 测试主密码 */
const TEST_PASSWORD: string = 'Header-Reader-Test-123';

/** HMAC-SHA1（YubiKey 挑战-应答模拟：response = HMAC-SHA1(slotSecret, challenge)） */
async function hmacSha1(key: Uint8Array, message: Uint8Array): Promise<Uint8Array> {
  const keyBlob: cryptoFramework.DataBlob = { data: key };
  const keyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
  const symKey = await keyGenerator.convertKey(keyBlob);
  const mac = cryptoFramework.createMac('SHA1');
  await mac.init(symKey);
  await mac.update({ data: message });
  return (await mac.doFinal()).data;
}

/** YubiKey HMAC 槽位挑战语义：挑战补零至 64 字节（KeePassXC slot challenge） */
function padChallengeTo64(challenge: ArrayBuffer): Uint8Array {
  const padded = new Uint8Array(64);
  const bytes = new Uint8Array(challenge);
  padded.set(bytes.subarray(0, Math.min(64, bytes.length)));
  return padded;
}

/** 固定应答回调（每次调用返回副本，镜像 ChallengeResponseXcStrategy 两阶段语义） */
function fixedResponseOf(response: Uint8Array): (challenge: ArrayBuffer) => Promise<Uint8Array> {
  return (_challenge: ArrayBuffer): Promise<Uint8Array> => {
    const copy = new Uint8Array(response.length);
    copy.set(response);
    return Promise.resolve(copy);
  };
}

/** 向字节数组尾部追加 LE i32 */
function pushInt32LE(target: number[], value: number): void {
  target.push(value & 0xff);
  target.push((value >>> 8) & 0xff);
  target.push((value >>> 16) & 0xff);
  target.push((value >>> 24) & 0xff);
}

/** 合成 KdfParameters VarDictionary 字节（可注入 seed / uuid，含跳过条目） */
function buildKdfDict(seed: number[] | null, uuid: number[] | null): Uint8Array {
  const parts: number[] = [0x00, 0x01];
  if (uuid !== null) {
    parts.push(0x42);
    pushInt32LE(parts, 5);
    parts.push(0x24, 0x55, 0x55, 0x49, 0x44);
    pushInt32LE(parts, uuid.length);
    for (const b of uuid) {
      parts.push(b);
    }
  }
  // 干扰条目：String 'I' → 'abc'，验证非 Bytes 类型跳过
  parts.push(0x18);
  pushInt32LE(parts, 1);
  parts.push(0x49);
  pushInt32LE(parts, 3);
  parts.push(0x61, 0x62, 0x63);
  if (seed !== null) {
    parts.push(0x42);
    pushInt32LE(parts, 1);
    parts.push(0x53);
    pushInt32LE(parts, seed.length);
    for (const b of seed) {
      parts.push(b);
    }
  }
  parts.push(0x00);
  const out = new Uint8Array(parts.length);
  for (let i = 0; i < parts.length; i++) {
    out[i] = parts[i];
  }
  return out;
}

/** 合成 v4 KDBX 文件头字节（12 字节签名/版本 + 可选字段 11 + 完整 EndOfHeader 字段） */
function buildSyntheticV4Header(kdfDict: Uint8Array | null): ArrayBuffer {
  const kdfFieldBytes = kdfDict === null ? 0 : 5 + kdfDict.length;
  // EndOfHeader：id u8 + 长度 u32 LE + 数据 0x0D0A0D0A（对齐真实 KDBX4 布局）
  const endFieldBytes = 9;
  const buf = new ArrayBuffer(12 + kdfFieldBytes + endFieldBytes);
  const view = new DataView(buf);
  view.setUint32(0, 0x9aa2d903, true);
  view.setUint32(4, 0xb54bfb67, true);
  view.setUint16(8, 1, true);
  view.setUint16(10, 4, true);
  let pos = 12;
  if (kdfDict !== null) {
    view.setUint8(pos, 11);
    view.setUint32(pos + 1, kdfDict.length, true);
    new Uint8Array(buf, pos + 5).set(kdfDict);
    pos += kdfFieldBytes;
  }
  view.setUint8(pos, 0);
  view.setUint32(pos + 1, 4, true);
  view.setUint32(pos + 5, 0x0d0ad0a, true);
  return buf;
}

/** 期望抛出指定原因码 */
function expectParseError(data: ArrayBuffer, expectedCode: KdbxHeaderParseErrorCode): void {
  let caught: KdbxHeaderParseErrorCode | null = null;
  try {
    KdbxHeaderReader.readHeader(data);
  } catch (e) {
    const err = e as KdbxHeaderParseError;
    caught = err.code;
  }
  expect(caught).assertEqual(expectedCode);
}

export default function KdbxHeaderReaderTest() {
  describe('KdbxHeaderReaderTest', () => {
    it('synthetic v4 header: extracts seed, uuid and skips non-Bytes entries', 0, () => {
      const seed: number[] = [0xaa, 0xbb, 0xcc, 0xdd];
      const uuid: number[] = [];
      for (let i = 0; i < 16; i++) {
        uuid.push(0x31 + i);
      }
      const info = KdbxHeaderReader.readHeader(buildSyntheticV4Header(buildKdfDict(seed, uuid)));
      expect(info.versionMajor).assertEqual(4);
      expect(info.versionMinor).assertEqual(1);
      expect(ByteUtils.bytesToHex(info.kdfSeed)).assertEqual('aabbccdd');
      expect(info.kdfUuidHex).assertEqual('3132333435363738393a3b3c3d3e3f40');
    });

    it('E2E: two-phase unlock with precomputed challenge-response (v4)', 0, async () => {
      // 模拟 YubiKey HMAC 槽位密钥
      const slotSecret = new Uint8Array(20);
      for (let i = 0; i < slotSecret.length; i++) {
        slotSecret[i] = 0x5a ^ i;
      }
      // 阶段〇：创建带挑战-应答回调的库（回调模拟硬件在线应答），保存
      const createCred = new KdbxCredentials(ProtectedValue.fromString(TEST_PASSWORD), null,
        (challenge: ArrayBuffer): Promise<Uint8Array> => {
          return hmacSha1(slotSecret, padChallengeTo64(challenge));
        });
      const db = Kdbx.create(createCred, 'CrDb');
      const saved = await db.save();

      // 阶段一：主线程预解析文件头，提取 KDF seed（挑战值原文）
      const info = KdbxHeaderReader.readHeader(saved);
      expect(info.versionMajor).assertEqual(4);
      expect(info.kdfSeed.byteLength).assertEqual(32);
      expect(info.kdfUuidHex.length).assertEqual(32);

      // 模拟硬件阶段：以预解析 seed 计算 HMAC-SHA1 应答，经 hex 通道传递
      const response = await hmacSha1(slotSecret, padChallengeTo64(info.kdfSeed));
      const challengeResponseHex = ByteUtils.bytesToHex(response);
      expect(challengeResponseHex.length).assertEqual(40);

      // 阶段二：固定应答回调两阶段重开（challengeResponseHex 语义）
      const reopened = await Kdbx.load(saved, new KdbxCredentials(
        ProtectedValue.fromString(TEST_PASSWORD), null,
        fixedResponseOf(ByteUtils.hexToBytes(challengeResponseHex))));
      expect(reopened.header.versionMajor).assertEqual(4);
      expect(reopened.meta.name).assertEqual('CrDb');

      // 反例：错误应答（不同槽位密钥）解锁必须失败
      const wrongSecret = new Uint8Array(20).fill(0x77);
      const wrongResponse = await hmacSha1(wrongSecret, padChallengeTo64(info.kdfSeed));
      let wrongThrew = false;
      try {
        await Kdbx.load(saved, new KdbxCredentials(ProtectedValue.fromString(TEST_PASSWORD), null,
          fixedResponseOf(wrongResponse)));
      } catch (e) {
        wrongThrew = true;
      }
      expect(wrongThrew).assertTrue();
    });

    it('rejects KDBX3 with KDBX3_NOT_SUPPORTED', 0, () => {
      const buf = new ArrayBuffer(12);
      const view = new DataView(buf);
      view.setUint32(0, 0x9aa2d903, true);
      view.setUint32(4, 0xb54bfb67, true);
      view.setUint16(8, 1, true);
      view.setUint16(10, 3, true);
      expectParseError(buf, KdbxHeaderParseErrorCode.KDBX3_NOT_SUPPORTED);
    });

    it('rejects unsupported major version (5.x)', 0, () => {
      const buf = new ArrayBuffer(12);
      const view = new DataView(buf);
      view.setUint32(0, 0x9aa2d903, true);
      view.setUint32(4, 0xb54bfb67, true);
      view.setUint16(8, 0, true);
      view.setUint16(10, 5, true);
      expectParseError(buf, KdbxHeaderParseErrorCode.UNSUPPORTED_VERSION);
    });

    it('rejects non-KDBX data with BAD_SIGNATURE', 0, () => {
      expectParseError(new ArrayBuffer(64), KdbxHeaderParseErrorCode.BAD_SIGNATURE);
    });

    it('rejects truncated header with TRUNCATED', 0, () => {
      expectParseError(new ArrayBuffer(8), KdbxHeaderParseErrorCode.TRUNCATED);
    });

    it('rejects v4 header without KdfParameters field', 0, () => {
      expectParseError(buildSyntheticV4Header(null), KdbxHeaderParseErrorCode.NO_KDF_PARAMETERS);
    });

    it('rejects KDF dict without seed with NO_KDF_SEED', 0, () => {
      const uuid: number[] = [];
      for (let i = 0; i < 16; i++) {
        uuid.push(0x31 + i);
      }
      expectParseError(buildSyntheticV4Header(buildKdfDict(null, uuid)),
        KdbxHeaderParseErrorCode.NO_KDF_SEED);
    });

    it('rejects unsupported VarDictionary version with BAD_VAR_DICTIONARY', 0, () => {
      const badDict = new Uint8Array([0x00, 0x02, 0x00]);
      expectParseError(buildSyntheticV4Header(badDict),
        KdbxHeaderParseErrorCode.BAD_VAR_DICTIONARY);
    });
  });
}
