/**
 * KeePass2Parser 单元测试
 * 覆盖率目标：> 90%
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { KeePass2Parser } from '../../../../../../main/ets/services/otp/parsers/KeePass2Parser';
import { KdbxEntry } from 'kdbxweb';
import { IOtpFieldParser } from '../../../../../../main/ets/services/otp';

export default function KeePass2ParserTest() {
  describe('KeePass2Parser', () => {
    let parser: IOtpFieldParser;

    beforeEach(() => {
      parser = new KeePass2Parser();
    });

    /**
     * 测试解析器属性
     */
    it('has correct name and priority', 0, () => {
      expect(parser.name).assertEqual('KeePass2Parser');
      expect(parser.priority).assertEqual(20);
    });

    /**
     * 测试识别 TimeOtp-Secret 字段
     */
    it('canParse returns true for TimeOtp-Secret field', 0, () => {
      const fieldName = 'TimeOtp-Secret';
      const fieldValue = 'JBSWY3DPEHPK3PXP';

      expect(parser.canParse(fieldName, fieldValue)).assertTrue();
    });

    /**
     * 测试忽略无效字段
     */
    it('canParse returns false for invalid field', 0, () => {
      expect(parser.canParse('otp', 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP')).assertFalse();
      expect(parser.canParse('TimeOtp-Secret', '')).assertFalse();
      expect(parser.canParse('TOTP Seed', 'JBSWY3DPEHPK3PXP')).assertFalse();
    });

    /**
     * 测试解析基本 KeePass2 字段
     */
    it('parse returns OTPURL from TimeOtp-Secret field', 0, () => {
      const fieldName = 'TimeOtp-Secret';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['TimeOtp-Secret', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('otpauth://totp/');
      expect(urls[0]).assertContain('secret=JBSWY3DPEHPK3PXP');
      expect(urls[0]).assertContain('algorithm=SHA1');
      expect(urls[0]).assertContain('digits=6');
      expect(urls[0]).assertContain('period=30');
    });

    /**
     * 测试自定义参数
     */
    it('parse respects custom parameters', 0, () => {
      const fieldName = 'TimeOtp-Secret';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['TimeOtp-Secret', fieldValue],
          ['TimeOtp-Length', '8'],
          ['TimeOtp-Period', '60'],
          ['TimeOtp-Algorithm', 'SHA256']
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('digits=8');
      expect(urls[0]).assertContain('period=60');
      expect(urls[0]).assertContain('algorithm=SHA256');
    });

    /**
     * 测试缺失字段处理
     */
    it('parse returns empty array when fieldValue is empty', 0, () => {
      const fieldName = 'TimeOtp-Secret';
      const fieldValue = '';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['TimeOtp-Length', '8']
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(0);
    });

    /**
     * 测试默认值填充
     */
    it('parse uses default values when optional fields are missing', 0, () => {
      const fieldName = 'TimeOtp-Secret';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['TimeOtp-Secret', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('algorithm=SHA1');
      expect(urls[0]).assertContain('digits=6');
      expect(urls[0]).assertContain('period=30');
    });

    /**
     * 测试发行者编码
     */
    it('parse encodes issuer correctly', 0, () => {
      const fieldName = 'TimeOtp-Secret';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'Test Account'],
          ['TimeOtp-Secret', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('Test%20Account');
    });

    /**
     * 测试缺失 Title 字段
     */
    it('parse uses Unknown as issuer when Title is missing', 0, () => {
      const fieldName = 'TimeOtp-Secret';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['TimeOtp-Secret', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('Unknown');
    });
  });
}
