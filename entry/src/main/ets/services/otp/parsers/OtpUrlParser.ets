/**
 * 标准 OTPURL 解析器
 * 支持 otpauth://totp/... 格式，包括 Steam 令牌
 */
import { KdbxEntry } from 'kdbxweb';
import { IOtpFieldParser } from '../IOtpFieldParser';

/**
 * OtpUrlParser - 标准 OTPURL 格式解析器
 */
export class OtpUrlParser implements IOtpFieldParser {
  readonly name = 'OtpUrlParser';
  readonly priority = 10;

  /**
   * 判断是否能解析该字段
   * @param fieldName 字段名称
   * @param fieldValue 字段值
   * @returns 是否能解析
   */
  canParse(fieldName: string, fieldValue: string): boolean {
    if (!fieldValue) {
      return false;
    }
    return fieldValue.startsWith('otpauth://totp/');
  }

  /**
   * 解析指定字段的 OTP 数据
   * @param fieldName 字段名称
   * @param fieldValue 字段值
   * @param entry KeePass 条目
   * @returns OTPURL 数组
   */
  parse(fieldName: string, fieldValue: string, entry: KdbxEntry): string[] {
    // 对于标准 OTPURL，直接返回字段值
    if (this.canParse(fieldName, fieldValue)) {
      return [fieldValue];
    }
    return [];
  }
}
