import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { KdbxHeader } from '../../../../main/ets/kdbx/KdbxHeader';
import { Binary, VariantDictionaryItem } from '../../../../main/ets/kdbx/models/KdbxTypes';

export default function KdbxHeaderUnitTest() {
  describe('KdbxHeader', () => {
    let header: KdbxHeader;

    beforeAll(() => {
      // 测试套件开始前的设置
    });

    beforeEach(() => {
      // 每个测试用例开始前的设置
      header = new KdbxHeader();
    });

    afterEach(() => {
      // 每个测试用例结束后的清理
    });

    afterAll(() => {
      // 测试套件结束后的清理
    });

    it('should create header with default values', 0, () => {
      expect(header).not().assertUndefined();
      expect(header.getModel()).not().assertUndefined();
      expect(header.getModel().version).assertEqual(4);
    });

    it('should initialize with correct default KDF parameters', 0, () => {
      const model = header.getModel();
      expect(model.kdfParameters).not().assertUndefined();
      expect(model.kdfParameters?.uuid).not().assertUndefined();
      expect(model.kdfParameters?.salt).not().assertUndefined();
      expect(model.kdfParameters?.parallelism).assertUndefined();
      expect(model.kdfParameters?.memory).assertUndefined();
      expect(model.kdfParameters?.iterations).assertEqual(0);
    });

    it('should process and write string custom data', 0, () => {
      // 创建测试数据
      const customData = new Map<string, VariantDictionaryItem>();
      customData.set('testKey', {
        type: 0x05, // String type
        value: 'testValue'
      });
      header.getModel().publicCustomData = customData;

      // 写入数据
      const binary = header.writePublicCustomData();

      // 创建新header并处理数据
      const newHeader = new KdbxHeader();
      newHeader.processPublicCustomData(binary);

      // 验证结果
      const result = newHeader.getModel().publicCustomData;
      expect(result).not().assertUndefined();
      expect(result?.get('testKey')).not().assertUndefined();
      expect(result?.get('testKey')?.value).assertDeepEquals('testValue');
    });

    it('should process and write numeric custom data', 0, () => {
      const customData = new Map<string, VariantDictionaryItem>();
      customData.set('intKey', {
        type: 0x00, // UInt32 type
        value: 12345
      });
      header.getModel().publicCustomData = customData;

      const binary = header.writePublicCustomData();
      const newHeader = new KdbxHeader();
      newHeader.processPublicCustomData(binary);

      const result = newHeader.getModel().publicCustomData;
      expect(result?.get('intKey')?.value).assertEqual(12345);
    });

    it('should process and write boolean custom data', 0, () => {
      const customData = new Map<string, VariantDictionaryItem>();
      customData.set('boolKey', {
        type: 0x02, // Bool type
        value: true
      });
      header.getModel().publicCustomData = customData;

      const binary = header.writePublicCustomData();
      const newHeader = new KdbxHeader();
      newHeader.processPublicCustomData(binary);

      const result = newHeader.getModel().publicCustomData;
      expect(result?.get('boolKey')?.value).assertEqual(true);
    });

    it('should handle multiple custom data entries', 0, () => {
      const customData = new Map<string, VariantDictionaryItem>();
      customData.set('stringKey', { type: 0x05, value: 'string value' });
      customData.set('intKey', { type: 0x00, value: 12345 });
      customData.set('boolKey', { type: 0x02, value: true });
      header.getModel().publicCustomData = customData;

      const binary = header.writePublicCustomData();
      const newHeader = new KdbxHeader();
      newHeader.processPublicCustomData(binary);

      const result = newHeader.getModel().publicCustomData;
      expect(result?.size).assertEqual(3);
      expect(result?.get('stringKey')?.value).assertEqual('string value');
      expect(result?.get('intKey')?.value).assertEqual(12345);
      expect(result?.get('boolKey')?.value).assertEqual(true);
    });

    it('should handle KDBX3.1 format', 0, () => {
      const header3 = new KdbxHeader();
      header3.getModel().version = 3;

      // 验证KDBX3.1特定的设置
      expect(header3.getModel().version).assertEqual(3);
      expect(header3.getModel().kdfParameters).not().assertUndefined();
    });

    it('should handle KDBX4 format', 0, () => {
      const header4 = new KdbxHeader();
      header4.getModel().version = 4;

      // 验证KDBX4特定的设置
      expect(header4.getModel().version).assertEqual(4);
      expect(header4.getModel().kdfParameters).not().assertUndefined();
    });

    it('should handle invalid custom data gracefully', 0, () => {
      // 创建无效的二进制数据
      const invalidData = new Uint8Array([0x01, 0x02, 0x03]); // 无效的格式

      // 处理无效数据不应抛出错误
      header.processPublicCustomData(invalidData);
      expect(header.getModel().publicCustomData?.size).assertEqual(0);
    });

    it('should handle unknown value types in custom data', 0, () => {
      const customData = new Map<string, VariantDictionaryItem>();
      customData.set('validType', {
        type: 0x05, // 有效的字符串类型
        value: 'valid value'
      });
      customData.set('invalidType', {
        type: 0xFF, // 未知类型
        value: 'some value'
      });
      header.getModel().publicCustomData = customData;

      const binary = header.writePublicCustomData();
      // 现在应该包含有效数据的二进制表示
      expect(binary.length).assertLarger(0);
      
      const newHeader = new KdbxHeader();
      newHeader.processPublicCustomData(binary);

      const result = newHeader.getModel().publicCustomData;
      // 验证只有有效的数据被处理
      expect(result?.size).assertEqual(1);
      expect(result?.has('validType')).assertTrue();
      expect(result?.has('invalidType')).assertFalse();
      expect(result?.get('validType')?.value).assertEqual('valid value');
    });

    it('should correctly handle binary data in custom data', 0, () => {
      const binaryData = new Uint8Array([1, 2, 3, 4, 5]);
      const customData = new Map<string, VariantDictionaryItem>();
      customData.set('binaryKey', {
        type: 0x06, // ByteArray type
        value: binaryData
      });
      header.getModel().publicCustomData = customData;

      const binary = header.writePublicCustomData();
      const newHeader = new KdbxHeader();
      newHeader.processPublicCustomData(binary);

      const result = newHeader.getModel().publicCustomData;
      const resultBinary = result?.get('binaryKey')?.value as Binary;
      expect(resultBinary.length).assertEqual(binaryData.length);
      for (let i = 0; i < binaryData.length; i++) {
        expect(resultBinary[i]).assertEqual(binaryData[i]);
      }
    });

    it('should handle empty binary data', 0, () => {
      const customData = new Map<string, VariantDictionaryItem>();
      customData.set('emptyBinary', {
        type: 0x06,
        value: new Uint8Array(0)
      });
      header.getModel().publicCustomData = customData;

      const binary = header.writePublicCustomData();
      const newHeader = new KdbxHeader();
      newHeader.processPublicCustomData(binary);

      const result = newHeader.getModel().publicCustomData;
      const resultBinary = result?.get('emptyBinary')?.value;
      expect((resultBinary as Binary).length).assertEqual(0);
    });

    it('should generate random fields correctly', 0, async () => {
      await header.generateRandomFields();
      const model = header.getModel();

      // 验证随机字段是否已生成
      expect(model.masterSeed).not().assertUndefined();
      expect(model.masterSeed.length).assertLarger(0);

      expect(model.encryptionIV).not().assertUndefined();
      expect(model.encryptionIV.length).assertLarger(0);

      expect(model.kdfParameters?.salt).not().assertUndefined();
      expect(model.kdfParameters?.salt.length).assertLarger(0);
    });

    it('should set and get cipher UUID correctly', 0, () => {
      const testUuid = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
      header.getModel().cipherId = testUuid;

      const retrievedUuid = header.getModel().cipherId;
      expect(retrievedUuid).not().assertUndefined();
      expect(retrievedUuid.length).assertEqual(testUuid.length);

      for (let i = 0; i < testUuid.length; i++) {
        expect(retrievedUuid[i]).assertEqual(testUuid[i]);
      }
    });

    it('should set and get compression flag correctly', 0, () => {
      // 默认应该是启用压缩的
      expect(header.getModel().compressionFlags).assertEqual(1);

      // 设置为不压缩
      header.getModel().compressionFlags = 0;
      expect(header.getModel().compressionFlags).assertEqual(0);

      // 重新设置为压缩
      header.getModel().compressionFlags = 1;
      expect(header.getModel().compressionFlags).assertEqual(1);
    });

    it('should set and get KDF parameters correctly', 0, () => {
      const kdfParams = header.getModel().kdfParameters;

      if (kdfParams) {
        // 设置新的KDF参数
        kdfParams.iterations = 10000;
        kdfParams.memory = 16 * 1024 * 1024; // 16MB
        kdfParams.parallelism = 4;

        // 验证参数是否正确设置
        expect(kdfParams.iterations).assertEqual(10000);
        expect(kdfParams.memory).assertEqual(16 * 1024 * 1024);
        expect(kdfParams.parallelism).assertEqual(4);
      }
    });

    it('should handle different KDF types', 0, () => {
      // 测试AES-KDF
      const aesKdfUuid =
        new Uint8Array([0x7c, 0x02, 0xbb, 0x82, 0x79, 0xa7, 0x4a, 0xc0, 0x92, 0x7d, 0x11, 0x4a, 0x00, 0x64, 0x82,
          0x38]);
      const kdfParameters = header.getModel().kdfParameters;
      if (kdfParameters === undefined) {
        expect(kdfParameters).not().assertUndefined();
        return;
      }
      kdfParameters.uuid = aesKdfUuid;
      kdfParameters.rounds = 10000;

      expect(kdfParameters.uuid).not().assertUndefined();
      expect(kdfParameters.rounds).assertEqual(10000);

      // 测试Argon2d
      const argon2dUuid =
        new Uint8Array([0xef, 0x63, 0x6d, 0xdf, 0x8c, 0x29, 0x44, 0x4b, 0x91, 0xf7, 0xa9, 0xa4, 0x03, 0xe3, 0x0a,
          0x0c]);
      kdfParameters.uuid = argon2dUuid;
      kdfParameters.iterations = 3;
      kdfParameters.memory = 64 * 1024 * 1024;
      kdfParameters.parallelism = 2;

      expect(kdfParameters.uuid).not().assertUndefined();
      expect(kdfParameters.iterations).assertEqual(3);
      expect(kdfParameters.memory).assertEqual(64 * 1024 * 1024);
      expect(kdfParameters.parallelism).assertEqual(2);
    });

    it('should handle complete header setup and serialization', 0, async () => {
      // 设置完整的头部
      await header.generateRandomFields();
      header.getModel().version = 4;
      header.getModel().compressionFlags = 1;

      // 添加自定义数据
      const customData = new Map<string, VariantDictionaryItem>();
      customData.set('testString', { type: 0x05, value: 'test value' });
      customData.set('testNumber', { type: 0x00, value: 12345 });
      header.getModel().publicCustomData = customData;

      // 验证所有字段是否正确设置
      expect(header.getModel().version).assertEqual(4);
      expect(header.getModel().compressionFlags).assertEqual(1);
      expect(header.getModel().masterSeed).not().assertUndefined();
      expect(header.getModel().encryptionIV).not().assertUndefined();
      expect(header.getModel().kdfParameters).not().assertUndefined();
      expect(header.getModel().publicCustomData?.size).assertEqual(2);
    });
  });
}