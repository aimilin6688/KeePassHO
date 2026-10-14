import { ByteUtils } from 'kdbxweb';

/**
 * KDBX 文件头解析失败错误（携带原因码，供 UI 映射 i18n 提示）
 */
export class KdbxHeaderParseError extends Error {
  public readonly code: KdbxHeaderParseErrorCode;

  constructor(code: KdbxHeaderParseErrorCode, message: string) {
    super(code + ': ' + message);
    this.name = 'KdbxHeaderParseError';
    this.code = code;
  }
}

/**
 * 解析失败原因码
 */
export enum KdbxHeaderParseErrorCode {
  /** 数据不足（文件被截断） */
  TRUNCATED = 'TRUNCATED',
  /** 签名不符（非 KDBX 文件） */
  BAD_SIGNATURE = 'BAD_SIGNATURE',
  /** KDBX3 不支持挑战-应答（XC 两阶段流程仅支持 KDBX4） */
  KDBX3_NOT_SUPPORTED = 'KDBX3_NOT_SUPPORTED',
  /** 不支持的版本（<3 或 >4） */
  UNSUPPORTED_VERSION = 'UNSUPPORTED_VERSION',
  /** v4 外层头部缺少 KdfParameters（字段 11） */
  NO_KDF_PARAMETERS = 'NO_KDF_PARAMETERS',
  /** VarDictionary 结构损坏或版本不支持 */
  BAD_VAR_DICTIONARY = 'BAD_VAR_DICTIONARY',
  /** KDF 参数缺少种子（'S'，Argon2 salt / AES-KDF seed 同键） */
  NO_KDF_SEED = 'NO_KDF_SEED',
}

/**
 * KDBX 文件头预解析结果
 */
export interface KdbxHeaderInfo {
  versionMajor: number;
  versionMinor: number;
  /** KDF seed 原文（挑战-应答的挑战值，主线程阶段一提取） */
  kdfSeed: ArrayBuffer;
  /** KDF 算法 UUID hex（诊断用，无法解析时为空串） */
  kdfUuidHex: string;
}

/** 文件签名与外层字段常量（对齐 kdbxweb defs/consts、KdbxHeader 字段表） */
const FILE_MAGIC: number = 0x9aa2d903;
const SIG2_KDBX: number = 0xb54bfb67;
const OUTER_FIELD_END_OF_HEADER: number = 0;
const OUTER_FIELD_KDF_PARAMETERS: number = 11;
/** VarDictionary 值类型：字节数组 */
const VAR_DICT_TYPE_BYTES: number = 0x42;
/** KDF 参数键 'S'（Argon2 salt 与 AES-KDF seed 序列化后同键） */
const KDF_KEY_SEED: number[] = [0x53];
/** KDF 参数键 '$UUID'（算法标识，16 字节） */
const KDF_KEY_UUID: number[] = [0x24, 0x55, 0x55, 0x49, 0x44];

/**
 * KDBX 文件头预解析器（主线程，YubiKey 挑战-应答两阶段流程的阶段一）：
 * 仅解析签名/版本/外层头部 KdfParameters，提取 KDF seed 作为挑战值原文，
 * 供上层驱动硬件应答（NFC 贴卡）后经 challengeResponseHex 通道完成阶段二加载。
 *
 * 字节布局（KDBX4，对齐 kdbxweb KdbxHeader / VarDictionary）：
 * - 签名：0x9AA2D903 / 0xB54BFB67（LE u32 × 2）
 * - 版本：minor u16 LE + major u16 LE（4 = KDBX4）
 * - 外层字段：id u8 + 长度 u32 LE + 数据，id 0 结束；字段 11 = KdfParameters
 * - VarDictionary：版本 u16 LE（主版本须为 1）+ 条目流（type u8，0 结束；
 *   keyLen i32 LE + key + valLen i32 LE + value）
 *
 * 不做文件 IO：调用方传入与阶段二加载相同的字节（同一读取会话/缓存），
 * 避免两阶段读到不同版本文件导致应答失配（见解锁方式计划风险表）。
 */
export class KdbxHeaderReader {
  /**
   * 解析 KDBX 文件头，提取 KDF seed
   * @param data KDBX 文件完整字节（与后续加载共用同一份）
   * @returns 头部信息（版本 + KDF seed + 算法 UUID）
   * @throws KdbxHeaderParseError 解析失败（原因见 KdbxHeaderParseErrorCode）
   */
  public static readHeader(data: ArrayBuffer): KdbxHeaderInfo {
    const view = new DataView(data);
    if (data.byteLength < 12) {
      throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.TRUNCATED, 'header too short');
    }
    const sig1 = view.getUint32(0, true);
    const sig2 = view.getUint32(4, true);
    if (sig1 !== FILE_MAGIC || sig2 !== SIG2_KDBX) {
      throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.BAD_SIGNATURE, 'not a kdbx file');
    }
    const versionMinor = view.getUint16(8, true);
    const versionMajor = view.getUint16(10, true);
    if (versionMajor === 3) {
      // KDBX3 的挑战值为 masterSeed 且无 KdfParameters，两阶段流程不支持
      throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.KDBX3_NOT_SUPPORTED,
        'kdbx3 is not supported by challenge-response');
    }
    if (versionMajor < 3 || versionMajor > 4) {
      throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.UNSUPPORTED_VERSION,
        'unsupported version: ' + versionMajor);
    }

    let pos = 12;
    let kdfParameters: ArrayBuffer | undefined = undefined;
    while (true) {
      if (pos + 5 > data.byteLength) {
        throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.TRUNCATED, 'outer header truncated');
      }
      const fieldId = view.getUint8(pos);
      const size = view.getUint32(pos + 1, true);
      pos += 5;
      if (fieldId === OUTER_FIELD_END_OF_HEADER) {
        break;
      }
      if (pos + size > data.byteLength) {
        throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.TRUNCATED, 'outer field overflow');
      }
      if (fieldId === OUTER_FIELD_KDF_PARAMETERS && kdfParameters === undefined) {
        kdfParameters = data.slice(pos, pos + size);
      }
      pos += size;
    }
    if (kdfParameters === undefined) {
      throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.NO_KDF_PARAMETERS,
        'kdf parameters field missing');
    }
    return KdbxHeaderReader.parseKdfParameters(kdfParameters, versionMajor, versionMinor);
  }

  private static parseKdfParameters(dict: ArrayBuffer, versionMajor: number,
    versionMinor: number): KdbxHeaderInfo {
    const view = new DataView(dict);
    if (dict.byteLength < 2) {
      throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.BAD_VAR_DICTIONARY, 'dict too short');
    }
    // 版本低字节忽略、高字节为主版本（对齐 kdbxweb VarDictionary.readVersion，须为 1）
    if (view.getUint8(1) !== 0x01) {
      throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.BAD_VAR_DICTIONARY,
        'unsupported dict version');
    }
    let pos = 2;
    let seed: ArrayBuffer | undefined = undefined;
    let uuid: ArrayBuffer | undefined = undefined;
    while (true) {
      if (pos + 1 > dict.byteLength) {
        throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.BAD_VAR_DICTIONARY,
          'dict entry truncated');
      }
      const type = view.getUint8(pos);
      pos += 1;
      if (type === 0) {
        break;
      }
      if (pos + 4 > dict.byteLength) {
        throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.BAD_VAR_DICTIONARY,
          'dict key length truncated');
      }
      const keyLen = view.getInt32(pos, true);
      pos += 4;
      if (keyLen <= 0 || pos + keyLen > dict.byteLength) {
        throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.BAD_VAR_DICTIONARY, 'bad key length');
      }
      const keyStart = pos;
      pos += keyLen;
      if (pos + 4 > dict.byteLength) {
        throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.BAD_VAR_DICTIONARY,
          'dict value length truncated');
      }
      const valLen = view.getInt32(pos, true);
      pos += 4;
      if (valLen < 0 || pos + valLen > dict.byteLength) {
        throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.BAD_VAR_DICTIONARY, 'bad value length');
      }
      const valStart = pos;
      pos += valLen;
      if (type === VAR_DICT_TYPE_BYTES) {
        if (seed === undefined && KdbxHeaderReader.bytesEqual(dict, keyStart, keyLen, KDF_KEY_SEED)) {
          seed = dict.slice(valStart, valStart + valLen);
        } else if (uuid === undefined &&
          KdbxHeaderReader.bytesEqual(dict, keyStart, keyLen, KDF_KEY_UUID)) {
          uuid = dict.slice(valStart, valStart + valLen);
        }
      }
    }
    if (seed === undefined || seed.byteLength === 0) {
      throw new KdbxHeaderParseError(KdbxHeaderParseErrorCode.NO_KDF_SEED, 'kdf seed missing');
    }
    const uuidHex = uuid === undefined ? '' : ByteUtils.bytesToHex(uuid);
    return {
      versionMajor: versionMajor,
      versionMinor: versionMinor,
      kdfSeed: seed,
      kdfUuidHex: uuidHex,
    };
  }

  private static bytesEqual(source: ArrayBuffer, offset: number, length: number,
    expected: number[]): boolean {
    if (length !== expected.length) {
      return false;
    }
    const view = new DataView(source);
    for (let i = 0; i < length; i++) {
      if (view.getUint8(offset + i) !== expected[i]) {
        return false;
      }
    }
    return true;
  }
}
