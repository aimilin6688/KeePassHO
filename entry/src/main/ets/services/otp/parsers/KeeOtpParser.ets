/**
 * KeeOTP 格式解析器
 * 支持 key=BASE32SECRET&step=30&size=6 格式
 */
import { KdbxEntry } from 'kdbxweb';
import { IOtpFieldParser } from '../IOtpFieldParser';
import { KdbxUtils } from '../../../common/utils/KdbxUtils';
import { url } from '@kit.ArkTS';

/**
 * KeeOtpParser - KeeOTP 格式解析器
 */
export class KeeOtpParser implements IOtpFieldParser {
  readonly name = 'KeeOtpParser';
  readonly priority = 30;

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
    // 支持 otp 或 KeeOTP 字段名，且值包含 key= 参数
    return (fieldName === 'otp' || fieldName === 'KeeOTP') && fieldValue.includes('key=');
  }

  /**
   * 解析指定字段的 OTP 数据
   * @param fieldName 字段名称
   * @param fieldValue 字段值
   * @param entry KeePass 条目
   * @returns OTPURL 数组
   */
  parse(fieldName: string, fieldValue: string, entry: KdbxEntry): string[] {
    if (!this.canParse(fieldName, fieldValue)) {
      return [];
    }

    try {
      // 解析查询参数格式
      const params = new url.URLParams(fieldValue);
      const secret = params.get('key');
      if (!secret) {
        return [];
      }

      const step = params.get('step') || '30';
      const size = params.get('size') || '6';

      // 获取发行者
      const issuer = encodeURIComponent(KdbxUtils.getFieldValueString(entry.fields, 'Title') || 'Unknown');

      // 转换为标准 OTPURL
      const otpUrl = `otpauth://totp/${issuer}?secret=${secret}&period=${step}&digits=${size}`;

      return [otpUrl];
    } catch (error) {
      // 静默忽略解析错误
      return [];
    }
  }
}
