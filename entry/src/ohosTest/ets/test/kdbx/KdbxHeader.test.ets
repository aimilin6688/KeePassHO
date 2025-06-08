import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { CompressionFlags, HeaderFieldID, InnerRandomStreamID, KdbxVersion } from '../../../../main/ets/kdbx/KdbxFormat';
import { KdbxHeader } from '../../../../main/ets/kdbx/KdbxHeader';
import { Binary } from '../../../../main/ets/kdbx/models/KdbxTypes';

import { KdbxUtils } from '../../../../main/ets/kdbx/utils/KdbxUtils';


// 创建测试用的二进制数据
function createTestHeaderData(version: number = KdbxVersion.V4): Binary {
  const chunks: number[][] = [];

  // 添加密码加密ID
  chunks.push([HeaderFieldID.CIPHER_ID]);
  chunks.push([16, 0]); // 长度
  chunks.push(Array(16).fill(0x01)); // 数据

  // 添加压缩标志
  chunks.push([HeaderFieldID.COMPRESSION_FLAGS]);
  chunks.push([4, 0]); // 长度
  chunks.push([CompressionFlags.GZIP, 0, 0, 0]); // 数据

  // 添加主种子
  chunks.push([HeaderFieldID.MASTER_SEED]);
  chunks.push([32, 0]); // 长度
  chunks.push(Array(32).fill(0x02)); // 数据

  // 添加加密IV
  chunks.push([HeaderFieldID.ENCRYPTION_IV]);
  chunks.push([16, 0]); // 长度
  chunks.push(Array(16).fill(0x03)); // 数据

  if (version < KdbxVersion.V4) {
    // KDBX3.1特有字段
    // 添加转换种子
    chunks.push([HeaderFieldID.TRANSFORM_SEED]);
    chunks.push([32, 0]); // 长度
    chunks.push(Array(32).fill(0x04)); // 数据

    // 添加转换轮数
    chunks.push([HeaderFieldID.TRANSFORM_ROUNDS]);
    chunks.push([8, 0]); // 长度
    chunks.push([0xA0, 0x86, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]); // 数据 (100000)

    // 添加保护流密钥
    chunks.push([HeaderFieldID.PROTECTED_STREAM_KEY]);
    chunks.push([32, 0]); // 长度
    chunks.push(Array(32).fill(0x05)); // 数据

    // 添加流起始字节
    chunks.push([HeaderFieldID.STREAM_START_BYTES]);
    chunks.push([32, 0]); // 长度
    chunks.push(Array(32).fill(0x06)); // 数据
  } else {
    // KDBX4特有字段
    // 添加KDF参数
    chunks.push([HeaderFieldID.KDF_PARAMETERS]);
    const kdfData = [
      0x04, // UInt32类型
      0x0A, // 名称长度
      ...Array.from('iterations').map(c => c.charCodeAt(0)), // 名称
      0x04, // 值长度
      0xA0, 0x86, 0x01, 0x00// 值 (100000)
    ];
    chunks.push([kdfData.length, 0]); // 长度
    chunks.push(kdfData); // 数据
  }

  // 添加内部随机流ID
  chunks.push([HeaderFieldID.INNER_RANDOM_STREAM_ID]);
  chunks.push([4, 0]); // 长度
  chunks.push([InnerRandomStreamID.CHACHA20, 0, 0, 0]); // 数据

  // 添加结束标记
  chunks.push([HeaderFieldID.END]);

  // 合并所有数据块
  const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }

  return result;
}

// 创建不完整的头部数据
function createIncompleteHeaderData(): Binary {
  const chunks: number[][] = [];

  // 只添加部分必需字段
  chunks.push([HeaderFieldID.CIPHER_ID]);
  chunks.push([16, 0]);
  chunks.push(Array(16).fill(0x01));

  chunks.push([HeaderFieldID.COMPRESSION_FLAGS]);
  chunks.push([4, 0]);
  chunks.push([CompressionFlags.GZIP, 0, 0, 0]);

  // 缺少其他必需字段

  chunks.push([HeaderFieldID.END]);

  const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }

  return result;
}

// 创建损坏的头部数据
function createCorruptedHeaderData(): Binary {
  const chunks: number[][] = [];

  // 添加字段但长度与实际数据不匹配
  chunks.push([HeaderFieldID.CIPHER_ID]);
  chunks.push([32, 0]); // 声明32字节长度
  chunks.push(Array(16).fill(0x01)); // 实际只有16字节

  chunks.push([HeaderFieldID.END]);

  const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }

  return result;
}

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
      expect(header.version).assertEqual(KdbxVersion.V4);
      expect(header.cipherId).assertInstanceOf('Uint8Array');
      expect(header.cipherId.length).assertEqual(16);
      expect(header.compressionFlags).assertEqual(CompressionFlags.GZIP);
      expect(header.masterSeed).assertInstanceOf('Uint8Array');
      expect(header.masterSeed.length).assertEqual(32);
      expect(header.encryptionIV).assertInstanceOf('Uint8Array');
      expect(header.encryptionIV.length).assertEqual(16);

      // KDBX4特有字段
      expect(header.kdfParameters).not().assertUndefined();
      expect(header.innerRandomStreamId).assertEqual(InnerRandomStreamID.CHACHA20);

      // KDBX3.1字段应该未定义
      expect(header.transformSeed).assertUndefined();
      expect(header.transformRounds).assertUndefined();
      expect(header.protectedStreamKey).assertUndefined();
      expect(header.streamStartBytes).assertUndefined();
    });

    it('should create KDBX3.1 header', 0, () => {
      header = new KdbxHeader(KdbxVersion.V3_1);

      expect(header.version).assertEqual(KdbxVersion.V3_1);
      expect(header.transformSeed).assertInstanceOf('Uint8Array');
      expect(header.transformSeed?.length).assertEqual(32);
      expect(header.transformRounds).assertEqual(100000);
      expect(header.protectedStreamKey).assertInstanceOf('Uint8Array');
      expect(header.protectedStreamKey?.length).assertEqual(32);
      expect(header.streamStartBytes).assertInstanceOf('Uint8Array');
      expect(header.streamStartBytes?.length).assertEqual(32);
      expect(header.innerRandomStreamId).assertEqual(InnerRandomStreamID.SALSA20);

      // KDBX4字段应该未定义
      expect(header.kdfParameters).assertUndefined();
    });

    it('should generate random fields', 0, () => {
      const originalMasterSeed = new Uint8Array(header.masterSeed);
      const originalEncryptionIV = new Uint8Array(header.encryptionIV);

      header.generateRandomFields();

      // 验证字段已被随机化
      expect(header.masterSeed).not().assertDeepEquals(originalMasterSeed);
      expect(header.encryptionIV).not().assertDeepEquals(originalEncryptionIV);
    });

    it('should read KDBX4 header from binary', 0, () => {
      const data = createTestHeaderData(KdbxVersion.V4);
      const offset = header.readFromBinary(data);

      expect(offset).assertLarger(0);
      expect(header.cipherId).assertDeepEquals(new Uint8Array(Array(16).fill(0x01)));
      expect(header.compressionFlags).assertEqual(CompressionFlags.GZIP);
      expect(header.masterSeed).assertDeepEquals(new Uint8Array(Array(32).fill(0x02)));
      expect(header.encryptionIV).assertDeepEquals(new Uint8Array(Array(16).fill(0x03)));
      expect(header.innerRandomStreamId).assertEqual(InnerRandomStreamID.CHACHA20);
      expect(header.kdfParameters).not().assertUndefined();
    });

    it('should read KDBX3.1 header from binary', 0, () => {
      header = new KdbxHeader(KdbxVersion.V3_1);
      const data = createTestHeaderData(KdbxVersion.V3_1);
      const offset = header.readFromBinary(data);

      expect(offset).assertLarger(0);
      expect(header.cipherId).assertDeepEquals(new Uint8Array(Array(16).fill(0x01)));
      expect(header.compressionFlags).assertEqual(CompressionFlags.GZIP);
      expect(header.masterSeed).assertDeepEquals(new Uint8Array(Array(32).fill(0x02)));
      expect(header.encryptionIV).assertDeepEquals(new Uint8Array(Array(16).fill(0x03)));
      expect(header.transformSeed).assertDeepEquals(new Uint8Array(Array(32).fill(0x04)));
      expect(header.transformRounds).assertEqual(100000);
      expect(header.protectedStreamKey).assertDeepEquals(new Uint8Array(Array(32).fill(0x05)));
      expect(header.streamStartBytes).assertDeepEquals(new Uint8Array(Array(32).fill(0x06)));
    });

    it('should write KDBX4 header to binary', 0, () => {
      // 设置测试数据
      header.cipherId = new Uint8Array(Array(16).fill(0x01));
      header.compressionFlags = CompressionFlags.GZIP;
      header.masterSeed = new Uint8Array(Array(32).fill(0x02));
      header.encryptionIV = new Uint8Array(Array(16).fill(0x03));
      header.innerRandomStreamId = InnerRandomStreamID.CHACHA20;

      const binary = header.writeToBinary();
      expect(binary).not().assertUndefined();
      expect(binary.length).assertLarger(0);

      // 读取写入的数据并验证
      const newHeader = new KdbxHeader(KdbxVersion.V4);
      newHeader.readFromBinary(binary);

      // 比较关键字段而不是整个对象
      expect(newHeader.cipherId).assertDeepEquals(new Uint8Array(Array(16).fill(0x01)));
      expect(newHeader.compressionFlags).assertEqual(CompressionFlags.GZIP);
      expect(newHeader.masterSeed).assertDeepEquals(new Uint8Array(Array(32).fill(0x02)));
      expect(newHeader.encryptionIV).assertDeepEquals(new Uint8Array(Array(16).fill(0x03)));
      expect(newHeader.innerRandomStreamId).assertEqual(InnerRandomStreamID.CHACHA20);
    });

    it('should write KDBX3.1 header to binary', 0, () => {
      header = new KdbxHeader(KdbxVersion.V3_1);

      // 设置测试数据
      header.cipherId = new Uint8Array(Array(16).fill(0x01));
      header.compressionFlags = CompressionFlags.GZIP;
      header.masterSeed = new Uint8Array(Array(32).fill(0x02));
      header.encryptionIV = new Uint8Array(Array(16).fill(0x03));
      header.transformSeed = new Uint8Array(Array(32).fill(0x04));
      header.transformRounds = 100000;
      header.protectedStreamKey = new Uint8Array(Array(32).fill(0x05));
      header.streamStartBytes = new Uint8Array(Array(32).fill(0x06));
      header.innerRandomStreamId = InnerRandomStreamID.SALSA20;

      const binary = header.writeToBinary();
      expect(binary).not().assertUndefined();
      expect(binary.length).assertLarger(0);

      // 读取写入的数据并验证
      const newHeader = new KdbxHeader(KdbxVersion.V3_1);
      newHeader.readFromBinary(binary);

      expect(newHeader.cipherId).assertDeepEquals(header.cipherId);
      expect(newHeader.compressionFlags).assertEqual(header.compressionFlags);
      expect(newHeader.masterSeed).assertDeepEquals(header.masterSeed);
      expect(newHeader.encryptionIV).assertDeepEquals(header.encryptionIV);
      expect(newHeader.transformSeed).assertDeepEquals(header.transformSeed);
      expect(newHeader.transformRounds).assertEqual(header.transformRounds);
      expect(newHeader.protectedStreamKey).assertDeepEquals(header.protectedStreamKey);
      expect(newHeader.streamStartBytes).assertDeepEquals(header.streamStartBytes);
      expect(newHeader.innerRandomStreamId).assertEqual(header.innerRandomStreamId);
    });

    it('should handle custom data', 0, () => {
      // 设置自定义数据
      header.publicCustomData = new Map<string, Object>([
        ['TestKey1', 'TestValue1'],
        ['TestKey2', 42],
        ['TestKey3', new Uint8Array([1, 2, 3])]
      ]);

      const binary = header.writeToBinary();
      expect(binary).not().assertUndefined();

      // 读取写入的数据并验证
      const newHeader = new KdbxHeader(KdbxVersion.V4);
      newHeader.readFromBinary(binary);

      expect(newHeader.publicCustomData).not().assertUndefined();
      expect(newHeader.publicCustomData?.get('TestKey1')).assertEqual('TestValue1');
      expect(newHeader.publicCustomData?.get('TestKey2')).assertEqual(42);
      expect(newHeader.publicCustomData?.get('TestKey3')).assertEqual(new Uint8Array([1, 2, 3]));
    });

    it('should handle error conditions gracefully', 0, () => {
      // 测试无效的二进制数据
      const invalidData = new Uint8Array([0xFF, 0xFF, 0xFF]);
      expect(() => header.readFromBinary(invalidData)).assertThrowError('Invalid header');

      // 测试缺少必需字段
      // header.masterSeed = null;
      // expect(() => header.writeToBinary()).assertThrowError('Invalid header');

      // 测试无效的字段ID
      const dataWithInvalidField = new Uint8Array([0xFF, 0x00, 0x00]);
      expect(() => header.readFromBinary(dataWithInvalidField)).assertThrowError('Invalid header');
    });

    it('should handle large custom data', 0, () => {
      // 创建大量自定义数据
      const customData = new Map<string, Object>();
      for (let i = 0; i < 1000; i++) {
        customData.set(`Key${i}`, `Value${i}`);
      }
      header.publicCustomData = customData;

      const binary = header.writeToBinary();
      expect(binary).not().assertUndefined();
      expect(binary.length).assertLarger(10000);

      // 读取写入的数据并验证
      const newHeader = new KdbxHeader(KdbxVersion.V4);
      newHeader.readFromBinary(binary);

      expect(newHeader.publicCustomData).not().assertUndefined();
      expect(newHeader.publicCustomData?.size).assertEqual(customData.size);
      for (let i = 0; i < 1000; i++) {
        expect(newHeader.publicCustomData?.get(`Key${i}`)).assertEqual(`Value${i}`);
      }
    });

    it('should maintain data integrity through binary conversion', 0, () => {
      // 设置所有可能的字段
      header.cipherId = KdbxUtils.generateRandom(new Uint8Array(16));
      header.compressionFlags = CompressionFlags.GZIP;
      header.masterSeed = KdbxUtils.generateRandom(new Uint8Array(32));
      header.encryptionIV = KdbxUtils.generateRandom(new Uint8Array(16));
      header.innerRandomStreamId = InnerRandomStreamID.CHACHA20;
      header.kdfParameters = {
        uuid: KdbxUtils.generateRandom(new Uint8Array(16)),
        iterations: 100000,
        salt: KdbxUtils.generateRandom(new Uint8Array(32))
      };
      header.publicCustomData = new Map<string, Object>([
        ['test', 'value'],
        ['binary', KdbxUtils.generateRandom(new Uint8Array(10))]
      ]);

      // 写入二进制
      const binary = header.writeToBinary();

      // 读取并验证所有字段
      const newHeader = new KdbxHeader(KdbxVersion.V4);
      newHeader.readFromBinary(binary);

      expect(newHeader.cipherId).assertDeepEquals(header.cipherId);
      expect(newHeader.compressionFlags).assertEqual(header.compressionFlags);
      expect(newHeader.masterSeed).assertDeepEquals(header.masterSeed);
      expect(newHeader.encryptionIV).assertDeepEquals(header.encryptionIV);
      expect(newHeader.innerRandomStreamId).assertEqual(header.innerRandomStreamId);
      expect(newHeader.kdfParameters).assertEqual(header.kdfParameters);
      expect(newHeader.publicCustomData).assertEqual(header.publicCustomData);
    });

    // 新增的边界条件测试
    it('should handle invalid version numbers', 0, () => {
      // 测试无效的版本号
      expect(() => new KdbxHeader(0)).assertThrowError('Invalid version');
      expect(() => new KdbxHeader(999)).assertThrowError('Invalid version');
    });

    it('should handle empty or null fields', 0, () => {
      // 测试空字段
      header.cipherId = new Uint8Array(0);
      expect(() => header.writeToBinary()).assertThrowError('Cannot write header: Missing required fields');

      // 测试null字段
      header.masterSeed = new Uint8Array(0);
      expect(() => header.writeToBinary()).assertThrowError('Cannot write header: Missing required fields');
    });

    it('should handle minimum and maximum values', 0, () => {
      // 测试最小值
      header = new KdbxHeader(KdbxVersion.V3_1);
      header.transformRounds = 1;
      const minBinary = header.writeToBinary();
      const minHeader = new KdbxHeader(KdbxVersion.V3_1);
      minHeader.readFromBinary(minBinary);
      expect(minHeader.transformRounds).assertEqual(1);

      // 测试最大值
      header.transformRounds = Number.MAX_SAFE_INTEGER;
      const maxBinary = header.writeToBinary();
      const maxHeader = new KdbxHeader(KdbxVersion.V3_1);
      maxHeader.readFromBinary(maxBinary);
      expect(maxHeader.transformRounds).assertEqual(Number.MAX_SAFE_INTEGER);
    });

    // 新增的特殊情况测试
    it('should handle incomplete header data', 0, () => {
      const incompleteData = createIncompleteHeaderData();
      expect(() => header.readFromBinary(incompleteData)).assertThrowError('Missing required fields');
    });

    it('should handle corrupted header data', 0, () => {
      const corruptedData = createCorruptedHeaderData();
      expect(() => header.readFromBinary(corruptedData)).assertThrowError('Data length mismatch');
    });

    it('should handle field length mismatches', 0, () => {
      // 创建字段长度与实际数据不匹配的测试数据
      const data = new Uint8Array([
        HeaderFieldID.CIPHER_ID,
        32, 0, // 声明32字节长度
        ...Array(16).fill(0x01) // 实际只有16字节
      ]);
      expect(() => header.readFromBinary(data)).assertThrowError('Data length mismatch');
    });
  });
}
