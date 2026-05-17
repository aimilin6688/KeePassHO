/**
 * KeeOtpParser 单元测试
 * 覆盖率目标：> 90%
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { KeeOtpParser } from '../../../../../../main/ets/services/otp/parsers/KeeOtpParser';
import { KdbxEntry } from 'kdbxweb';
import { IOtpFieldParser } from '../../../../../../main/ets/services/otp';

export default function KeeOtpParserTest() {
  describe('KeeOtpParser', () => {
    let parser: IOtpFieldParser;

    beforeEach(() => {
      parser = new KeeOtpParser();
    });

    /**
     * 测试解析器属性
     */
    it('has correct name and priority', 0, () => {
      expect(parser.name).assertEqual('KeeOtpParser');
      expect(parser.priority).assertEqual(30);
    });

    /**
     * 测试识别 otp 字段
     */
    it('canParse returns true for otp field with key parameter', 0, () => {
      const fieldName = 'otp';
      const fieldValue = 'key=JBSWY3DPEHPK3PXP&step=30&size=6';

      expect(parser.canParse(fieldName, fieldValue)).assertTrue();
    });

    /**
     * 测试识别 KeeOTP 字段
     */
    it('canParse returns true for KeeOTP field', 0, () => {
      const fieldName = 'KeeOTP';
      const fieldValue = 'key=JBSWY3DPEHPK3PXP';

      expect(parser.canParse(fieldName, fieldValue)).assertTrue();
    });

    /**
     * 测试忽略无效字段
     */
    it('canParse returns false for invalid field', 0, () => {
      expect(parser.canParse('otp', '')).assertFalse();
      expect(parser.canParse('otp', 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP')).assertFalse();
      expect(parser.canParse('TimeOtp-Secret', 'JBSWY3DPEHPK3PXP')).assertFalse();
    });

    /**
     * 测试解析基本 KeeOTP 格式
     */
    it('parse returns OTPURL from otp field', 0, () => {
      const fieldName = 'otp';
      const fieldValue = 'key=JBSWY3DPEHPK3PXP&step=30&size=6';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['otp', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('otpauth://totp/');
      expect(urls[0]).assertContain('secret=JBSWY3DPEHPK3PXP');
      expect(urls[0]).assertContain('period=30');
      expect(urls[0]).assertContain('digits=6');
    });

    /**
     * 测试解析 KeeOTP 字段
     */
    it('parse returns OTPURL from KeeOTP field', 0, () => {
      const fieldName = 'KeeOTP';
      const fieldValue = 'key=JBSWY3DPEHPK3PXQ&step=60&size=8';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['KeeOTP', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('secret=JBSWY3DPEHPK3PXQ');
      expect(urls[0]).assertContain('period=60');
      expect(urls[0]).assertContain('digits=8');
    });

    /**
     * 测试默认值填充
     */
    it('parse uses default values when parameters are missing', 0, () => {
      const fieldName = 'otp';
      const fieldValue = 'key=JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['otp', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('period=30');
      expect(urls[0]).assertContain('digits=6');
    });

    /**
     * 测试缺失 key 参数
     */
    it('parse returns empty array when key parameter is missing', 0, () => {
      const fieldName = 'otp';
      const fieldValue = 'step=30&size=6';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['otp', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(0);
    });

    /**
     * 测试无效格式处理
     */
    it('parse returns empty array for invalid format', 0, () => {
      const fieldName = 'otp';
      const fieldValue = 'invalid format';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['otp', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(0);
    });

    /**
     * 测试发行者编码
     */
    it('parse encodes issuer correctly', 0, () => {
      const fieldName = 'otp';
      const fieldValue = 'key=JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'Test Account'],
          ['otp', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('Test%20Account');
    });
  });
}
