/**
 * KeeTrayTotp 字段解析器
 * 支持 TOTP Seed + TOTP Settings 字段
 */
import { KdbxEntry } from 'kdbxweb';
import { IOtpFieldParser } from '../IOtpFieldParser';
import { KdbxUtils } from '../../../common/utils/KdbxUtils';

/**
 * KeeTrayTotpParser - KeeTrayTotp 字段解析器
 */
export class KeeTrayTotpParser implements IOtpFieldParser {
  readonly name = 'KeeTrayTotpParser';
  readonly priority = 30;

  /**
   * 判断是否能解析该字段
   * @param fieldName 字段名称
   * @param fieldValue 字段值
   * @returns 是否能解析
   */
  canParse(fieldName: string, fieldValue: string): boolean {
    return fieldName === 'TOTP Seed' && !!fieldValue;
  }

  /**
   * 解析指定字段的 OTP 数据
   * @param fieldName 字段名称
   * @param fieldValue 字段值（TOTP Seed 的值）
   * @param entry KeePass 条目
   * @returns OTPURL 数组
   */
  parse(fieldName: string, fieldValue: string, entry: KdbxEntry): string[] {
    if (!fieldValue) {
      return [];
    }

    // 解析配置（格式：30;6，表示步长和位数）
    const settings = this.getFieldValue(entry, 'TOTP Settings') || '30;6';
    const parts = settings.split(';');
    const period = parts[0] || '30';
    const digits = parts[1] || '6';

    // 获取发行者
    const issuer = encodeURIComponent(KdbxUtils.getFieldValueString(entry.fields, 'Title') || 'Unknown');

    // 转换为标准 OTPURL
    const otpUrl = `otpauth://totp/${issuer}?secret=${fieldValue}&period=${period}&digits=${digits}`;

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
