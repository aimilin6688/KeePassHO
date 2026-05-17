/**
 * KeePass2 原生字段解析器
 * 支持 TimeOtp-Secret 等字段
 */
import { KdbxEntry } from 'kdbxweb';
import { IOtpFieldParser } from '../IOtpFieldParser';
import { KdbxUtils } from '../../../common/utils/KdbxUtils';

/**
 * KeePass2Parser - KeePass2 原生字段解析器
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
    return fieldName === 'TimeOtp-Secret' && !!fieldValue;
  }

  /**
   * 解析指定字段的 OTP 数据
   * @param fieldName 字段名称
   * @param fieldValue 字段值（TimeOtp-Secret 的值）
   * @param entry KeePass 条目
   * @returns OTPURL 数组
   */
  parse(fieldName: string, fieldValue: string, entry: KdbxEntry): string[] {
    if (!fieldValue) {
      return [];
    }

    // 提取配置参数
    const digits = parseInt(this.getFieldValue(entry, 'TimeOtp-Length') || '6');
    const period = parseInt(this.getFieldValue(entry, 'TimeOtp-Period') || '30');
    const algorithm = this.getFieldValue(entry, 'TimeOtp-Algorithm') || 'SHA1';

    // 获取发行者（使用 Title 字段）
    const issuer = encodeURIComponent(KdbxUtils.getFieldValueString(entry.fields, 'Title') || 'Unknown');

    // 转换为标准 OTPURL
    const otpUrl = `otpauth://totp/${issuer}?secret=${fieldValue}&algorithm=${algorithm}&digits=${digits}&period=${period}`;

    return [otpUrl];
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
