import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/**
 * RFC 4226 HMAC-based OTP（HOTP）生成器，对齐 KeePassLib2Android Cryptography/HmacOtp.cs。
 * 仅用于 OtpKeyProv 密钥创建 / 前瞻窗口（LookAhead）场景，与解锁页 TOTP（TotpService）无关。
 */
export class HmacOtp {
  private static readonly DIGITS_POWER: number[] = [
    1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000
  ];
  private static readonly DOUBLE_DIGITS: number[] = [0, 2, 4, 6, 8, 1, 3, 5, 7, 9];

  /**
   * 生成 HOTP 码
   * @param secret HMAC 密钥
   * @param factor 计数器（RFC 4226 的移动因子）
   * @param codeDigits 码位数（不含校验位）
   * @param addChecksum 是否追加 Luhn 校验位（RFC 4226 Annex D）
   * @param truncationOffset 固定截断偏移（-1 表示动态截断）
   */
  public static async generate(secret: Uint8Array, factor: number, codeDigits: number,
    addChecksum: boolean, truncationOffset: number): Promise<string> {
    // 计数器 → 8 字节大端（不用位运算，兼容 2^31 以上计数器）
    const text = new Uint8Array(8);
    let f = factor;
    for (let i = 7; i >= 0; i--) {
      text[i] = f % 256;
      f = Math.floor(f / 256);
    }

    // HMAC-SHA1
    const keyBlob: cryptoFramework.DataBlob = { data: secret };
    const keyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
    const symKey = await keyGenerator.convertKey(keyBlob);
    const mac = cryptoFramework.createMac('SHA1');
    await mac.init(symKey);
    await mac.update({ data: text });
    const hash = (await mac.doFinal()).data;

    // 动态截断
    let offset = hash[hash.length - 1] & 0xf;
    if (truncationOffset >= 0 && truncationOffset < hash.length - 4) {
      offset = truncationOffset;
    }
    const binary = ((hash[offset] & 0x7f) << 24) |
      ((hash[offset + 1] & 0xff) << 16) |
      ((hash[offset + 2] & 0xff) << 8) |
      (hash[offset + 3] & 0xff);

    let otp = binary % HmacOtp.DIGITS_POWER[codeDigits];
    if (addChecksum) {
      otp = otp * 10 + HmacOtp.calculateChecksum(otp, codeDigits);
    }
    const digits = addChecksum ? codeDigits + 1 : codeDigits;
    return otp.toString().padStart(digits, '0');
  }

  /**
   * Luhn 校验位（RFC 4226 Annex D），对齐 HmacOtp.CalculateChecksum
   */
  private static calculateChecksum(num: number, digits: number): number {
    let doubleDigit = true;
    let total = 0;
    let n = num;
    let d = digits;
    while (d > 0) {
      let digit = n % 10;
      n = Math.floor(n / 10);
      if (doubleDigit) {
        digit = HmacOtp.DOUBLE_DIGITS[digit];
      }
      total += digit;
      doubleDigit = !doubleDigit;
      d--;
    }
    let result = total % 10;
    if (result !== 0) {
      result = 10 - result;
    }
    return result;
  }
}
