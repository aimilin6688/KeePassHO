/**
 * OtpCompatibilityManager 单元测试
 * 覆盖率目标：> 95%
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { OtpCompatibilityManager } from '../../../../../main/ets/services/otp/OtpCompatibilityManager';
import { IOtpFieldParser } from '../../../../../main/ets/services/otp/IOtpFieldParser';
import { KdbxEntry } from 'kdbxweb';

// Mock 解析器类（用于测试）
class MockParser implements IOtpFieldParser {
  name: string = 'MockParser';
  priority: number = 100;

  canParse(fieldName: string, fieldValue: string): boolean {
    return false;
  }

  parse(fieldName: string, fieldValue: string, entry: KdbxEntry): string[] {
    return [];
  }
}

export default function OtpCompatibilityManagerTest() {
  describe('OtpCompatibilityManagerTest', () => {

    beforeEach(() => {
      // 每个测试前重置单例
      OtpCompatibilityManager.resetInstance();
    });

    afterEach(() => {
      OtpCompatibilityManager.resetInstance();
    });

    /**
     * 测试单例模式
     */
    it('getInstance returns singleton instance', 0, () => {
      const instance1 = OtpCompatibilityManager.getInstance();
      const instance2 = OtpCompatibilityManager.getInstance();
      expect(instance1).assertEqual(instance2);
    });

    /**
     * 测试自动注册机制
     */
    it('automatically registers default parsers on construction', 0, () => {
      const manager = OtpCompatibilityManager.getInstance();
      const parsers = manager.getParsers();

      expect(parsers.length).assertEqual(4);

      // 验证解析器名称
      const parserNames: string[] = parsers.map((p: IOtpFieldParser): string => p.name);
      expect(parserNames).assertContain('OtpUrlParser');
      expect(parserNames).assertContain('KeePass2Parser');
      expect(parserNames).assertContain('KeeOtpParser');
      expect(parserNames).assertContain('KeeTrayTotpParser');
    });

    /**
     * 测试优先级排序
     */
    it('parsers are sorted by priority', 0, () => {
      const manager = OtpCompatibilityManager.getInstance();
      const parsers = manager.getParsers();

      // 验证优先级排序（数字越小优先级越高）
      expect(parsers[0].priority).assertEqual(10);  // OtpUrlParser
      expect(parsers[1].priority).assertEqual(20);  // KeePass2Parser
      expect(parsers[2].priority).assertEqual(30);  // KeeOtpParser
      expect(parsers[3].priority).assertEqual(30);  // KeeTrayTotpParser
    });

    /**
     * 测试注册自定义解析器
     */
    it('can register custom parser', 0, () => {
      const manager = OtpCompatibilityManager.getInstance();

      // 创建自定义解析器
      const customParser = new MockParser();
      customParser.name = 'CustomParser';
      customParser.priority = 5;

      manager.registerParser(customParser);
      const parsers = manager.getParsers();

      expect(parsers.length).assertEqual(5);
      expect(parsers[0].name).assertEqual('CustomParser');
      expect(parsers[0].priority).assertEqual(5);
    });

    /**
     * 测试字段去重逻辑
     * 同一个字段只被解析一次，即使多个解析器都能处理
     */
    it('field is only parsed once even if multiple parsers can handle it', 0, () => {
      const manager = OtpCompatibilityManager.getInstance();

      // 创建模拟的 KdbxEntry
      const mockEntry = {
        fields: new Map([
          ['otp', 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP']
        ])
      } as KdbxEntry;

      const urls = manager.extractOtpUrls(mockEntry);

      // 应该只返回一个 URL（虽然 OtpUrlParser 和 KeeOtpParser 都能处理）
      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertEqual('otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP');
    });

    /**
     * 测试静默忽略解析错误
     */
    it('silently ignores parsing errors', 0, () => {
      const manager = OtpCompatibilityManager.getInstance();

      // 创建包含无效字段的模拟条目
      const mockEntry = {
        fields: new Map([
          ['invalidField', 'invalidValue']
        ])
      } as KdbxEntry;

      const urls = manager.extractOtpUrls(mockEntry);

      // 应该返回空数组，不抛出异常
      expect(urls.length).assertEqual(0);
    });

    /**
     * 测试返回的解析器列表是副本（不影响原始数据）
     */
    it('getParsers returns a copy of parsers array', 0, () => {
      const manager = OtpCompatibilityManager.getInstance();
      const parsers1 = manager.getParsers();
      const parsers2 = manager.getParsers();

      // 修改一个数组不应影响另一个
      const newParser = new MockParser();
      newParser.name = 'Test';
      newParser.priority = 100;
      parsers1.push(newParser);

      expect(parsers1.length).assertEqual(5);
      expect(parsers2.length).assertEqual(4);
    });

    /**
     * 测试空条目处理
     */
    it('handles empty entry gracefully', 0, () => {
      const manager = OtpCompatibilityManager.getInstance();

      const mockEntry = {
        fields: new Map()
      } as KdbxEntry;

      const urls = manager.extractOtpUrls(mockEntry);

      expect(urls.length).assertEqual(0);
    });

    /**
     * 测试多字段解析
     */
    it('can parse multiple OTP fields from same entry', 0, () => {
      const manager = OtpCompatibilityManager.getInstance();

      const mockEntry = {
        fields: new Map([
          ['otp', 'otpauth://totp/Test1?secret=JBSWY3DPEHPK3PXP'],
          ['URL', 'otpauth://totp/Test2?secret=JBSWY3DPEHPK3PXQ']
        ])
      } as KdbxEntry;

      const urls = manager.extractOtpUrls(mockEntry);

      expect(urls.length).assertEqual(2);
    });
  });
}
