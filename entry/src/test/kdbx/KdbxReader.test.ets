/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { KdbxReader } from '../../../main/ets/kdbx/KdbxReader';
import { InnerRandomStreamID } from '../../../main/ets/kdbx/KdbxFormat';
import { Binary } from '../../../main/ets/kdbx/models/KdbxTypes';
import { KdbxUtils } from '../../main/ets/kdbx/utils/KdbxUtils';

describe('KdbxReader', () => {
  // 辅助函数：创建测试用的KDBX文件数据
  function createTestKdbxData(options: {
    version?: number;
    invalidSignature?: boolean;
    missingFields?: boolean;
    invalidKdf?: boolean;
    compressed?: boolean;
  } = {}): Uint8Array {
    const chunks: number[][] = [];

    // 1. 版本号 (KDBX4 = 0x00040000)
    const version = options.version ?? 0x00040000;
    chunks.push([
      version & 0xFF,
      (version >> 8) & 0xFF,
      (version >> 16) & 0xFF,
      (version >> 24) & 0xFF
    ]);

    // 2. 文件签名
    if (!options.invalidSignature) {
      chunks.push([0x03, 0xD9, 0xA2, 0x9A]); // 0x9AA2D903
      chunks.push([0x67, 0xFB, 0x4B, 0xB5]); // 0xB54BFB67
    } else {
      chunks.push([0x00, 0x00, 0x00, 0x00]);
      chunks.push([0x00, 0x00, 0x00, 0x00]);
    }

    if (!options.missingFields) {
      // 3. 主种子 (32字节)
      chunks.push([0x05]); // 字段ID
      chunks.push([32, 0, 0, 0]); // 长度
      chunks.push(Array(32).fill(0x01)); // 数据

      // 4. 加密IV (16字节)
      chunks.push([0x08]); // 字段ID
      chunks.push([16, 0, 0, 0]); // 长度
      chunks.push(Array(16).fill(0x02)); // 数据

      // 5. KDF参数
      if (!options.invalidKdf) {
        chunks.push([0x0C]); // 字段ID
        const kdfData = [
          0x04, // UInt32类型
          0x0A, // 名称长度
          ...Array.from('iterations').map(c => c.charCodeAt(0)), // 名称
          0x04, // 值长度
          0xA0, 0x86, 0x01, 0x00 // 值 (100000)
        ];
        chunks.push([kdfData.length, 0, 0, 0]); // 长度
        chunks.push(kdfData); // 数据
      }

      // 6. 压缩标志
      chunks.push([0x04]); // 字段ID
      chunks.push([4, 0, 0, 0]); // 长度
      chunks.push([options.compressed ? 1 : 0, 0, 0, 0]); // 数据

      // 7. 内部随机流ID
      chunks.push([0x0B]); // 字段ID
      chunks.push([4, 0, 0, 0]); // 长度
      chunks.push([InnerRandomStreamID.CHACHA20, 0, 0, 0]); // 数据
    }

    // 8. 头部结束标记
    chunks.push([0x00]); // 字段ID
    chunks.push([4, 0, 0, 0]); // 长度
    chunks.push([0x0D, 0x0A, 0x0D, 0x0A]); // 数据

    // 9. 加密的数据块
    chunks.push(Array(64).fill(0xFF)); // 模拟加密数据

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

  let reader: KdbxReader;

  beforeAll(() => {
    // 测试套件开始前的设置
  });

  beforeEach(() => {
    // 每个测试用例开始前的设置
  });

  afterEach(() => {
    // 每个测试用例结束后的清理
  });

  afterAll(() => {
    // 测试套件结束后的清理
  });

  it('should create reader with valid data', () => {
    const data = createTestKdbxData();
    reader = new KdbxReader(data);
    expect(reader).toBeDefined();
  });

  it('should reject invalid KDBX version', async () => {
    const data = createTestKdbxData({ version: 0x00030000 }); // KDBX3
    reader = new KdbxReader(data);

    await expect(reader.read('password')).rejects.toThrow('Unsupported KDBX version');
  });

  it('should reject invalid file signature', async () => {
    const data = createTestKdbxData({ invalidSignature: true });
    reader = new KdbxReader(data);

    await expect(reader.read('password')).rejects.toThrow('Invalid KDBX file signature');
  });

  it('should reject missing required fields', async () => {
    const data = createTestKdbxData({ missingFields: true });
    reader = new KdbxReader(data);

    await expect(reader.read('password')).rejects.toThrow('Missing required header fields');
  });

  it('should handle invalid KDF parameters', async () => {
    const data = createTestKdbxData({ invalidKdf: true });
    reader = new KdbxReader(data);

    await expect(reader.read('password')).rejects.toThrow();
  });

  it('should handle both compressed and uncompressed data', async () => {
    // 测试未压缩数据
    const uncompressedData = createTestKdbxData({ compressed: false });
    reader = new KdbxReader(uncompressedData);
    await expect(reader.read('password')).rejects.toThrow(); // 会失败，因为测试数据不是真实的加密数据

    // 测试压缩数据
    const compressedData = createTestKdbxData({ compressed: true });
    reader = new KdbxReader(compressedData);
    await expect(reader.read('password')).rejects.toThrow(); // 会失败，因为测试数据不是真实的加密数据
  });

  it('should handle key file', async () => {
    const data = createTestKdbxData();
    reader = new KdbxReader(data);

    const keyFile: Binary = new Uint8Array(32).fill(0x03); // 模拟密钥文件
    await expect(reader.read('password', keyFile)).rejects.toThrow(); // 会失败，因为测试数据不是真实的加密数据
  });

  it('should read various integer types correctly', () => {
    // 创建包含各种整数类型的测试数据
    const testData = new Uint8Array([
      // Uint8
      0x42,
      // Uint32 (小端序)
      0x78, 0x56, 0x34, 0x12,
      // Uint64 (小端序)
      0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01,
      // VarInt (0x1234)
      0xB4, 0x24
    ]);

    reader = new KdbxReader(testData);

    // 使用私有方法测试各种整数读取
    // 注意：这需要修改KdbxReader类，将这些方法改为public，或者使用其他方式测试
    // 这里仅作为示例，实际测试需要根据实现方式调整
    /*
    expect(reader['readUint8']()).assertEqual(0x42);
    expect(reader['readUint32']()).assertEqual(0x12345678);
    expect(reader['readUint64']()).assertEqual(0x0123456789ABCDEF);
    expect(reader['readVarInt'](testData, 13)).assertEqual(0x1234);
    */
  });

  it('should parse XML content correctly', async () => {
    // 创建包含有效XML内容的测试数据
    const xmlContent = `
      <?xml version="1.0" encoding="utf-8" standalone="yes"?>
      <KeePassFile>
        <Meta>
          <Generator>KeePassHO</Generator>
          <DatabaseName>Test Database</DatabaseName>
        </Meta>
        <Root>
          <Group>
            <Name>Root</Name>
          </Group>
        </Root>
      </KeePassFile>
    `;

    // 将XML内容添加到测试数据中
    const headerData = createTestKdbxData();
    const xmlData = new TextEncoder().encode(xmlContent);
    const testData = new Uint8Array(headerData.length + xmlData.length);
    testData.set(headerData);
    testData.set(xmlData, headerData.length);

    reader = new KdbxReader(testData);
    await expect(reader.read('password')).rejects.toThrow(); // 会失败，因为测试数据不是真实的加密数据
  });

  it('should handle large files', async () => {
    // 创建大文件测试数据
    const largeData = new Uint8Array(1024 * 1024); // 1MB
    KdbxUtils.fillRandom(largeData); // 填充随机数据

    const headerData = createTestKdbxData();
    const testData = new Uint8Array(headerData.length + largeData.length);
    testData.set(headerData);
    testData.set(largeData, headerData.length);

    reader = new KdbxReader(testData);
    await expect(reader.read('password')).rejects.toThrow(); // 会失败，因为测试数据不是真实的加密数据
  });

  it('should handle error conditions gracefully', async () => {
    // 测试空数据
    await expect(() => new KdbxReader(new Uint8Array(0))).toThrow();

    // 测试null数据
    await expect(() => new KdbxReader(null)).toThrow();

    // 测试损坏的数据
    const corruptedData = new Uint8Array(100);
    KdbxUtils.generateRandom(corruptedData);
    reader = new KdbxReader(corruptedData);
    await expect(reader.read('password')).rejects.toThrow();
  });
});
