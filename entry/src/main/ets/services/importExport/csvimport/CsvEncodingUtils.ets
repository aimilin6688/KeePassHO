import { util } from '@kit.ArkTS';

/**
 * CSV 文本编码标识（与 util.TextDecoder 编码名一致）
 */
export class CsvEncoding {
  /** 自动：跟随检测结果（向导编码下拉的默认项） */
  static readonly AUTO: string = '';
  static readonly UTF8: string = 'utf-8';
  static readonly GBK: string = 'gbk';
}

/**
 * CSV 编码工具
 * 检测策略：UTF-8 BOM → 严格 UTF-8 字节序列校验 → 回退 GBK
 * （纯 ASCII 对 UTF-8/GBK 同构，命中 UTF-8 不影响解码结果；
 *   GBK 双字节中文通常不是合法 UTF-8 序列，自动回退 GBK 解码）
 */
export class CsvEncodingUtils {
  private static readonly utf8Decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private static readonly gbkDecoder: util.TextDecoder = util.TextDecoder.create('gbk');

  /**
   * 检测字节内容的文本编码
   * @returns CsvEncoding.UTF8 / CsvEncoding.GBK
   */
  static detect(bytes: Uint8Array): string {
    if (CsvEncodingUtils.hasUtf8Bom(bytes) || CsvEncodingUtils.isValidUtf8(bytes)) {
      return CsvEncoding.UTF8;
    }
    return CsvEncoding.GBK;
  }

  /**
   * 按指定编码解码为字符串
   * @param bytes 原始字节
   * @param encoding CsvEncoding 编码名（空/未识别按 UTF-8）
   */
  static decode(bytes: Uint8Array, encoding: string): string {
    if (encoding === CsvEncoding.GBK) {
      return CsvEncodingUtils.gbkDecoder.decodeToString(bytes);
    }
    return CsvEncodingUtils.utf8Decoder.decodeToString(bytes);
  }

  /**
   * 自动检测编码并解码文件内容
   */
  static decodeAuto(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    return CsvEncodingUtils.decode(bytes, CsvEncodingUtils.detect(bytes));
  }

  /**
   * 是否带 UTF-8 BOM（EF BB BF）
   */
  static hasUtf8Bom(bytes: Uint8Array): boolean {
    return bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF;
  }

  /**
   * 严格 UTF-8 校验（RFC 3629：拒绝过长编码、UTF-16 代理区、越界码点、截断序列）
   */
  static isValidUtf8(bytes: Uint8Array): boolean {
    let i = 0;
    while (i < bytes.length) {
      const b = bytes[i];
      if (b <= 0x7F) {
        i++;
        continue;
      }
      let extra = 0;
      let minSecond = 0x80;
      let maxSecond = 0xBF;
      if (b >= 0xC2 && b <= 0xDF) {
        extra = 1;
      } else if (b === 0xE0) {
        extra = 2;
        minSecond = 0xA0;
      } else if (b >= 0xE1 && b <= 0xEC) {
        extra = 2;
      } else if (b === 0xED) {
        extra = 2;
        maxSecond = 0x9F;
      } else if (b >= 0xEE && b <= 0xEF) {
        extra = 2;
      } else if (b === 0xF0) {
        extra = 3;
        minSecond = 0x90;
      } else if (b >= 0xF1 && b <= 0xF3) {
        extra = 3;
      } else if (b === 0xF4) {
        extra = 3;
        maxSecond = 0x8F;
      } else {
        return false;
      }
      if (i + extra >= bytes.length) {
        return false;
      }
      const second = bytes[i + 1];
      if (second < minSecond || second > maxSecond) {
        return false;
      }
      for (let c = 2; c <= extra; c++) {
        const continuation = bytes[i + c];
        if (continuation < 0x80 || continuation > 0xBF) {
          return false;
        }
      }
      i += extra + 1;
    }
    return true;
  }
}
