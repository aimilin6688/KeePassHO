import { ByteUtils } from 'kdbxweb';

/**
 * OTP 恢复模式 secret 的编码格式，取值对齐 OtpKeyProv OtpUtil.cs 的 OtpDataFmt 枚举数值
 */
export enum OtpDataFmt {
  Hex = 0,
  Base64 = 1,
  Utf8 = 2,
  Dec = 3,
  Base32 = 4
}

const FMT_HEX = 'Hex';
const FMT_BASE64 = 'Base64';
const FMT_UTF8 = 'UTF-8';
const FMT_DEC = 'Dec';
const FMT_BASE32 = 'Base32';

/**
 * OtpKeyProv 恢复模式编码解析，对齐 addons/OtpKeyProv/EncodingUtil.cs。
 * 支持 Hex / Base64 / Base32(RFC 4648) / UTF-8 / Dec（十进制整数十进制字符串）五种格式。
 */
export class EncodingUtil {
  /** UI 下拉顺序与显示名（对齐 C# EncodingUtil.Formats） */
  public static readonly FORMATS: string[] = [FMT_HEX, FMT_BASE64, FMT_UTF8, FMT_DEC, FMT_BASE32];

  private static readonly BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /**
   * 显示名 → 枚举，未知名返回 null
   */
  public static getOtpDataFormat(fmt: string | undefined): OtpDataFmt | null {
    if (!fmt) {
      return null;
    }
    switch (fmt) {
      case FMT_HEX:
        return OtpDataFmt.Hex;
      case FMT_BASE64:
        return OtpDataFmt.Base64;
      case FMT_UTF8:
        return OtpDataFmt.Utf8;
      case FMT_DEC:
        return OtpDataFmt.Dec;
      case FMT_BASE32:
        return OtpDataFmt.Base32;
      default:
        return null;
    }
  }

  /**
   * 按格式解析 secret 输入为字节，非法输入返回 null（对齐 EncodingUtil.ParseKey）
   */
  public static parseKey(key: string, fmt: OtpDataFmt): Uint8Array | null {
    if (!key) {
      return null;
    }
    const trimmed = key.trim();
    if (trimmed.length === 0) {
      return null;
    }
    switch (fmt) {
      case OtpDataFmt.Hex:
        return EncodingUtil.parseHex(trimmed);
      case OtpDataFmt.Base64:
        return EncodingUtil.parseBase64(trimmed);
      case OtpDataFmt.Base32:
        return EncodingUtil.parseBase32(trimmed);
      case OtpDataFmt.Utf8:
        return ByteUtils.stringToBytes(trimmed);
      case OtpDataFmt.Dec:
        return EncodingUtil.parseDec(trimmed);
      default:
        return null;
    }
  }

  /**
   * 按格式解析计数器（大端数值），超 8 字节或超 Number 安全整数返回 null
   */
  public static parseCounter(counter: string, fmt: OtpDataFmt): number | null {
    const bytes = EncodingUtil.parseKey(counter, fmt);
    if (!bytes || bytes.length === 0 || bytes.length > 8) {
      return null;
    }
    let value = 0;
    for (let i = 0; i < bytes.length; i++) {
      value = value * 256 + bytes[i];
    }
    return value > Number.MAX_SAFE_INTEGER ? null : value;
  }

  /** Hex：去空白，奇数长度左补 0（对齐 C# 行为） */
  private static parseHex(key: string): Uint8Array | null {
    let hex = key.replace(/[ \t\r\n]/g, '');
    if (hex.length === 0) {
      return null;
    }
    if (hex.length % 2 === 1) {
      hex = '0' + hex;
    }
    if (!/^[0-9a-fA-F]+$/.test(hex)) {
      return null;
    }
    return ByteUtils.hexToBytes(hex);
  }

  /** Base64：非法 base64 返回 null（对齐 C# try/catch 语义） */
  private static parseBase64(key: string): Uint8Array | null {
    try {
      return ByteUtils.base64ToBytes(key);
    } catch (e) {
      return null;
    }
  }

  /** Base32（RFC 4648）：8 字符一组，'=' 截断，非法字符/长度返回 null */
  private static parseBase32(key: string): Uint8Array | null {
    if (key.length % 8 !== 0) {
      return null;
    }
    const out: number[] = [];
    for (let i = 0; i < key.length; i += 8) {
      let u = 0;
      let nBits = 0;
      for (let j = 0; j < 8; j++) {
        const ch = key[i + j].toUpperCase();
        if (ch === '=') {
          break;
        }
        const value = EncodingUtil.BASE32_ALPHABET.indexOf(ch);
        if (value < 0) {
          return null;
        }
        u = u * 32 + value;
        nBits += 5;
      }
      const tooMany = nBits % 8;
      u = Math.floor(u / Math.pow(2, tooMany));
      nBits -= tooMany;
      const startIdx = out.length;
      while (nBits > 0) {
        out.push(u % 256);
        u = Math.floor(u / 256);
        nBits -= 8;
      }
      // 本组字节反转：低位在前 → 高位在前
      for (let a = startIdx, b = out.length - 1; a < b; a++, b--) {
        const t = out[a];
        out[a] = out[b];
        out[b] = t;
      }
    }
    return new Uint8Array(out);
  }

  /** Dec：十进制字符串 → 8 字节大端（对齐 C# ulong.TryParse + UInt64ToBytes + Reverse） */
  private static parseDec(key: string): Uint8Array | null {
    if (!/^[0-9]+$/.test(key)) {
      return null;
    }
    // 大数十进制除法：逐位除 256 取余，得到低位在前的字节序列
    const digits: number[] = [];
    for (let i = 0; i < key.length; i++) {
      digits.push(key.charCodeAt(i) - 48);
    }
    const bytes: number[] = [];
    while (EncodingUtil.digitsNonZero(digits)) {
      let remainder = 0;
      for (let i = 0; i < digits.length; i++) {
        const cur = remainder * 10 + digits[i];
        digits[i] = Math.floor(cur / 256);
        remainder = cur % 256;
      }
      bytes.push(remainder);
      while (digits.length > 0 && digits[0] === 0) {
        digits.shift();
      }
    }
    if (bytes.length > 8) {
      return null;
    }
    // bytes 低位在前 → 8 字节大端（LSB 落在 result 末位）
    const result = new Uint8Array(8);
    for (let i = 0; i < bytes.length; i++) {
      result[8 - bytes.length + i] = bytes[bytes.length - 1 - i];
    }
    return result;
  }

  private static digitsNonZero(digits: number[]): boolean {
    for (let i = 0; i < digits.length; i++) {
      if (digits[i] !== 0) {
        return true;
      }
    }
    return false;
  }
}
