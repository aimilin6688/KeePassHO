/**
 * OtpUrlParser 单元测试
 * 覆盖率目标：> 90%
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { OtpUrlParser } from '../../../../../../main/ets/services/otp/parsers/OtpUrlParser';
import { KdbxEntry } from 'kdbxweb';
import { IOtpFieldParser } from '../../../../../../main/ets/services/otp';

export default function OtpUrlParserTest() {
  describe('OtpUrlParserTest', () => {
    let parser: IOtpFieldParser;

    beforeEach(() => {
      parser = new OtpUrlParser();
    });

    /**
     * 测试解析器属性
     */
    it('has correct name and priority', 0, () => {
      expect(parser.name).assertEqual('OtpUrlParser');
      expect(parser.priority).assertEqual(10);
    });

    /**
     * 测试标准 OTPURL 解析
     */
    it('canParse returns true for standard OTPURL', 0, () => {
      const fieldName = 'otp';
      const fieldValue = 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP';

      expect(parser.canParse(fieldName, fieldValue)).assertTrue();
    });

    /**
     * 测试 Steam 令牌识别
     */
    it('canParse returns true for Steam token URL', 0, () => {
      const fieldName = 'otp';
      const fieldValue = 'otpauth://totp/Steam?secret=JBSWY3DPEHPK3PXP&encoder=steam';

      expect(parser.canParse(fieldName, fieldValue)).assertTrue();
    });

    /**
     * 测试无效字段值
     */
    it('canParse returns false for invalid field value', 0, () => {
      expect(parser.canParse('otp', '')).assertFalse();
      expect(parser.canParse('otp', 'invalid')).assertFalse();
      expect(parser.canParse('otp', 'key=JBSWY3DPEHPK3PXP')).assertFalse();
    });

    /**
     * 测试解析单个 OTPURL
     */
    it('parse returns single OTPURL from field', 0, () => {
      const fieldName = 'otp';
      const fieldValue = 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['otp', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertEqual('otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP');
    });

    /**
     * 测试解析非 OTPURL 字段
     */
    it('parse returns empty array for non-OTPURL field', 0, () => {
      const fieldName = 'UserName';
      const fieldValue = 'test@example.com';
      const mockEntry = {
        fields: new Map([
          ['UserName', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(0);
    });

    /**
     * 测试 URL 字段中的 OTPURL
     */
    it('canParse returns true for OTPURL in URL field', 0, () => {
      const fieldName = 'URL';
      const fieldValue = 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP';

      expect(parser.canParse(fieldName, fieldValue)).assertTrue();
    });

    /**
     * 测试解析 URL 字段中的 OTPURL
     */
    it('parse returns OTPURL from URL field', 0, () => {
      const fieldName = 'URL';
      const fieldValue = 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['URL', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertEqual('otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP');
    });
  });
}
