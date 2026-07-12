/**
 * KeePass2 原生字段解析器
 * 支持 TimeOtp-Secret, TimeOtp-Secret-Base32, TimeOtp-Secret-Hex, TimeOtp-Secret-Base64 字段
 */
import { KdbxEntry } from 'kdbxweb';
import { util } from '@kit.ArkTS';
import { IOtpFieldParser } from '../IOtpFieldParser';
import { KdbxUtils } from '../../../common/utils/KdbxUtils';
import { TotpService } from '../../TotpService';

/**
 * KeePass2Parser - KeePass2 原生字段解析器
 * 支持 KeePass 2.x 的四种 TimeOtp-Secret 字段格式
 */
export class KeePass2Parser implements IOtpFieldParser {
  readonly name = 'KeePass2Parser';
  readonly priority = 20;

  /**
   * 判断是否能解析该字段
   * @param fieldName 字段名称
   * @param fieldValue 字段值
   * @returns 是否能解析
   */
  canParse(fieldName: string, fieldValue: string): boolean {
    return (fieldName === 'TimeOtp-Secret-Base32' ||
      fieldName === 'TimeOtp-Secret-Hex' ||
      fieldName === 'TimeOtp-Secret-Base64' ||
      fieldName === 'TimeOtp-Secret') && !!fieldValue;
  }

  /**
   * 解析指定字段的 OTP 数据
   * @param fieldName 字段名称
   * @param fieldValue 字段值
   * @param entry KeePass 条目
   * @returns OTPURL 数组
   */
  parse(fieldName: string, fieldValue: string, entry: KdbxEntry): string[] {
    if (!fieldValue) {
      return [];
    }

    // 将各种格式的密钥转换为 Base32
    let base32Secret: string;
    try {
      base32Secret = this.convertToBase32(fieldName, fieldValue);
    } catch (error) {
      // 转换失败，返回空数组
      return [];
    }

    // 提取配置参数
    const digits = parseInt(this.getFieldValue(entry, 'TimeOtp-Length') || '6');
    const period = parseInt(this.getFieldValue(entry, 'TimeOtp-Period') || '30');
    const algorithm = this.getFieldValue(entry, 'TimeOtp-Algorithm') || 'SHA1';

    // 获取发行者（使用 Title 字段）
    const issuer = encodeURIComponent(KdbxUtils.getFieldValueString(entry.fields, 'Title') || 'Unknown');

    // 转换为标准 OTPURL
    const otpUrl = `otpauth://totp/${issuer}?secret=${base32Secret}&algorithm=${algorithm}&digits=${digits}&period=${period}`;

    return [otpUrl];
  }

  /**
   * 根据字段名将密钥转换为 Base32 格式
   * @param fieldName 字段名称
   * @param fieldValue 字段值
   * @returns Base32 编码的密钥
   */
  private convertToBase32(fieldName: string, fieldValue: string): string {
    switch (fieldName) {
      case 'TimeOtp-Secret-Base32':
        // 已经是 Base32 格式，直接返回（移除空格和连字符）
        return fieldValue.replace(/[\s-]/g, '').toUpperCase();

      case 'TimeOtp-Secret-Hex':
        // 十六进制转 Base32
        return this.hexToBase32(fieldValue);

      case 'TimeOtp-Secret-Base64':
        // Base64 转 Base32
        return this.base64ToBase32(fieldValue);

      case 'TimeOtp-Secret':
        // UTF-8 字符串转 Base32
        return this.utf8ToBase32(fieldValue);

      default:
        throw new Error(`Unknown field name: ${fieldName}`);
    }
  }

  /**
   * 十六进制字符串转 Base32
   * @param hexString 十六进制字符串
   * @returns Base32 编码的字符串
   */
  private hexToBase32(hexString: string): string {
    // 移除空格和连字符
    const cleaned = hexString.replace(/[\s-]/g, '').toUpperCase();

    // 十六进制转字节数组
    const bytes = new Uint8Array(cleaned.length / 2);
    for (let i = 0; i < cleaned.length; i += 2) {
      bytes[i / 2] = parseInt(cleaned.substring(i, i + 2), 16);
    }

    // 字节数组转 Base32
    return TotpService.getInstance().base32Encode(bytes);
  }

  /**
   * Base64 字符串转 Base32
   * @param base64String Base64 字符串
   * @returns Base32 编码的字符串
   */
  private base64ToBase32(base64String: string): string {
    // Base64 解码为字节数组（使用 util.Base64Helper）
    const helper = new util.Base64Helper();
    const bytes = helper.decodeSync(base64String);

    // 字节数组转 Base32
    return TotpService.getInstance().base32Encode(bytes);
  }

  /**
   * UTF-8 字符串转 Base32
   * @param utf8String UTF-8 字符串
   * @returns Base32 编码的字符串
   */
  private utf8ToBase32(utf8String: string): string {
    // UTF-8 字符串转字节数组
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(utf8String);

    // 字节数组转 Base32
    return TotpService.getInstance().base32Encode(bytes);
  }

  /**
   * 获取字段值
   * @param entry KeePass 条目
   * @param fieldName 字段名称
   * @returns 字段值
   */
  private getFieldValue(entry: KdbxEntry, fieldName: string): string {
    const value = entry.fields.get(fieldName);
    return value ? KdbxUtils.getValueString(value) : '';
  }
}
