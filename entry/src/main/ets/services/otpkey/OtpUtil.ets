import { ByteUtils, CryptoEngine, KeyEncryptorAes, Salsa20 } from 'kdbxweb';
import { OtpEncryptedData } from './OtpInfo';

/**
 * OtpKeyProv 密钥派生工具，对齐 addons/OtpKeyProv/OtpUtil.cs：
 * - KeyFromOtps：OTP 码 ':' 连接 → UTF-8 → SHA-256 → AES-KDF 变换 → 再 SHA-256，得 32 字节派生密钥；
 * - EncryptData/DecryptData：'s20://' 前缀 + Base64，Salsa20（IV 取前 8 字节）；
 * - DecryptSecret：v2 逐项解密 + PlainTextHash 校验；
 * - EncryptSecret：v2 创建流程（随机 IV / 变换密钥，默认 10000 轮）。
 */
export class OtpUtil {
  private static readonly S20_PREFIX = 's20://';

  /**
   * OTP 码派生 32 字节密钥（对齐 OtpUtil.KeyFromOtps，码两侧空白去除）
   */
  public static async keyFromOtps(otps: string[], otpsOffset: number, otpsCount: number,
    trfKey32: Uint8Array, trfRounds: number): Promise<Uint8Array> {
    const parts: string[] = [];
    for (let i = otpsOffset; i < otpsOffset + otpsCount; i++) {
      parts.push(otps[i].trim());
    }
    const data = ByteUtils.stringToBytes(parts.join(':'));
    if (data.length === 0) {
      throw new Error('empty otp input');
    }
    return OtpUtil.hashAndTransform(data, trfKey32, trfRounds);
  }

  /**
   * SHA-256 → AES-KDF 变换 → SHA-256（对齐 OtpUtil.HashAndTransform）
   */
  public static async hashAndTransform(data: Uint8Array, trfKey32: Uint8Array,
    rounds: number): Promise<Uint8Array> {
    const hash1 = new Uint8Array(await CryptoEngine.sha256(ByteUtils.arrayToBuffer(data)));
    const transformed = await KeyEncryptorAes.encrypt(hash1, trfKey32, rounds);
    return new Uint8Array(await CryptoEngine.sha256(ByteUtils.arrayToBuffer(transformed)));
  }

  /**
   * Salsa20 加密为 's20://' + Base64（对齐 OtpUtil.EncryptData，IV 取前 8 字节，不修改入参）
   */
  public static encryptData(data: Uint8Array, key32: Uint8Array, iv16: Uint8Array): string {
    const enc = new Uint8Array(data);
    OtpUtil.xorWithSalsa20(enc, key32, iv16);
    return OtpUtil.S20_PREFIX + ByteUtils.bytesToBase64(enc);
  }

  /**
   * 解密 's20://' 数据（对齐 OtpUtil.DecryptData，非 s20 前缀返回 null）
   */
  public static decryptData(data: string, key32: Uint8Array, iv16: Uint8Array): Uint8Array | null {
    if (!data.startsWith(OtpUtil.S20_PREFIX)) {
      return null;
    }
    const enc = ByteUtils.base64ToBytes(data.substring(OtpUtil.S20_PREFIX.length));
    OtpUtil.xorWithSalsa20(enc, key32, iv16);
    return enc;
  }

  /**
   * v2 逐项解密 + PlainTextHash 校验（对齐 OtpUtil.DecryptSecret，任何失败返回 null）
   */
  public static async decryptSecret(d: OtpEncryptedData, otps: string[],
    otpsOffset: number, otpsCount: number): Promise<Uint8Array | null> {
    try {
      const trfKey32 = ByteUtils.base64ToBytes(d.transformationKey);
      const key32 = await OtpUtil.keyFromOtps(otps, otpsOffset, otpsCount, trfKey32, d.transformationRounds);
      const iv = ByteUtils.base64ToBytes(d.iv);
      const secret = OtpUtil.decryptData(d.cipherText, key32, iv);
      if (!secret) {
        return null;
      }
      const hashTrfKey32 = ByteUtils.base64ToBytes(d.plainTextHashTransformationKey);
      const hash = await OtpUtil.hashAndTransform(secret, hashTrfKey32, d.plainTextHashTransformationRounds);
      return OtpUtil.arraysEqual(hash, ByteUtils.base64ToBytes(d.plainTextHash)) ? secret : null;
    } catch (e) {
      return null;
    }
  }

  /**
   * v2 创建流程（对齐 OtpUtil.EncryptSecret）：随机 IV16 / 变换密钥，默认 10000 轮
   */
  public static async encryptSecret(secret: Uint8Array, otps: string[],
    otpsOffset: number, otpsCount: number): Promise<OtpEncryptedData> {
    const d = new OtpEncryptedData();

    const iv16 = ByteUtils.randomData(16);
    d.iv = ByteUtils.bytesToBase64(iv16);

    const trfKey32 = ByteUtils.randomData(32);
    d.transformationKey = ByteUtils.bytesToBase64(trfKey32);
    d.transformationRounds = OtpEncryptedData.DEFAULT_TRANSFORMATION_ROUNDS;

    const key32 = await OtpUtil.keyFromOtps(otps, otpsOffset, otpsCount, trfKey32, d.transformationRounds);
    d.cipherText = OtpUtil.encryptData(secret, key32, iv16);

    const hashTrfKey32 = ByteUtils.randomData(32);
    d.plainTextHashTransformationKey = ByteUtils.bytesToBase64(hashTrfKey32);
    d.plainTextHashTransformationRounds = OtpEncryptedData.DEFAULT_TRANSFORMATION_ROUNDS;
    const hash = await OtpUtil.hashAndTransform(secret, hashTrfKey32, d.plainTextHashTransformationRounds);
    d.plainTextHash = ByteUtils.bytesToBase64(hash);
    return d;
  }

  /** 就地 Salsa20 XOR（IV 取前 8 字节） */
  private static xorWithSalsa20(data: Uint8Array, key32: Uint8Array, iv16: Uint8Array): void {
    if (data.length === 0) {
      return;
    }
    const salsa = new Salsa20(key32, iv16.subarray(0, 8));
    const stream = salsa.getBytes(data.length);
    for (let i = 0; i < data.length; i++) {
      data[i] ^= stream[i];
    }
  }

  private static arraysEqual(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }
}
