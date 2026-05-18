/**
 * KeeTrayTotpParser 单元测试
 * 覆盖率目标：> 90%
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { KeeTrayTotpParser } from '../../../../../../main/ets/services/otp/parsers/KeeTrayTotpParser';
import { KdbxEntry } from 'kdbxweb';
import { IOtpFieldParser } from '../../../../../../main/ets/services/otp';

export default function KeeTrayTotpParserTest() {
  describe('KeeTrayTotpParserTest', () => {
    let parser: IOtpFieldParser;

    beforeEach(() => {
      parser = new KeeTrayTotpParser();
    });

    /**
     * 测试解析器属性
     */
    it('has correct name and priority', 0, () => {
      expect(parser.name).assertEqual('KeeTrayTotpParser');
      expect(parser.priority).assertEqual(30);
    });

    /**
     * 测试识别 TOTP Seed 字段
     */
    it('canParse returns true for TOTP Seed field', 0, () => {
      const fieldName = 'TOTP Seed';
      const fieldValue = 'JBSWY3DPEHPK3PXP';

      expect(parser.canParse(fieldName, fieldValue)).assertTrue();
    });

    /**
     * 测试忽略无效字段
     */
    it('canParse returns false for invalid field', 0, () => {
      expect(parser.canParse('otp', 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP')).assertFalse();
      expect(parser.canParse('TOTP Seed', '')).assertFalse();
      expect(parser.canParse('TimeOtp-Secret', 'JBSWY3DPEHPK3PXP')).assertFalse();
    });

    /**
     * 测试解析基本 KeeTrayTotp 字段
     */
    it('parse returns OTPURL from TOTP Seed and TOTP Settings', 0, () => {
      const fieldName = 'TOTP Seed';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['TOTP Seed', fieldValue],
          ['TOTP Settings', '30;6']
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
     * 测试自定义配置
     */
    it('parse respects custom TOTP Settings', 0, () => {
      const fieldName = 'TOTP Seed';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['TOTP Seed', fieldValue],
          ['TOTP Settings', '60;8']
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('period=60');
      expect(urls[0]).assertContain('digits=8');
    });

    /**
     * 测试缺失 TOTP Settings 字段
     */
    it('parse uses default settings when TOTP Settings is missing', 0, () => {
      const fieldName = 'TOTP Seed';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['TOTP Seed', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('period=30');
      expect(urls[0]).assertContain('digits=6');
    });

    /**
     * 测试缺失 fieldValue
     */
    it('parse returns empty array when fieldValue is empty', 0, () => {
      const fieldName = 'TOTP Seed';
      const fieldValue = '';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['TOTP Settings', '30;6']
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(0);
    });

    /**
     * 测试部分 TOTP Settings
     */
    it('parse handles partial TOTP Settings', 0, () => {
      const fieldName = 'TOTP Seed';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['TOTP Seed', fieldValue],
          ['TOTP Settings', '60']
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('period=60');
      expect(urls[0]).assertContain('digits=6');
    });

    /**
     * 测试发行者编码
     */
    it('parse encodes issuer correctly', 0, () => {
      const fieldName = 'TOTP Seed';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'Test Account'],
          ['TOTP Seed', fieldValue]
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
      const fieldName = 'TOTP Seed';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['TOTP Seed', fieldValue]
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('Unknown');
    });

    /**
     * 测试空 TOTP Settings
     */
    it('parse handles empty TOTP Settings', 0, () => {
      const fieldName = 'TOTP Seed';
      const fieldValue = 'JBSWY3DPEHPK3PXP';
      const mockEntry = {
        fields: new Map([
          ['Title', 'TestAccount'],
          ['TOTP Seed', fieldValue],
          ['TOTP Settings', '']
        ])
      } as KdbxEntry;

      const urls = parser.parse(fieldName, fieldValue, mockEntry);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertContain('period=30');
      expect(urls[0]).assertContain('digits=6');
    });
  });
}
