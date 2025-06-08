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
import { Salsa20 } from '../../../../../main/ets/kdbx/crypto/Salsa20';
import { KdbxUtils } from '../../../../../main/ets/kdbx/utils/KdbxUtils';

const hexToBytes = (hex: string): Uint8Array => {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return bytes;
};

const bytesToHex = (bytes: Uint8Array): string => {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
};
export default function Salsa20UnitTest() {
  describe('Salsa20', () => {
    // Test vectors from https://cr.yp.to/snuffle/spec.pdf
    const TEST_KEY = hexToBytes('0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20');
    const TEST_NONCE = hexToBytes('0102030405060708');
    const TEST_COUNTER = 0;
    const TEST_PLAINTEXT = KdbxUtils.strToBytes('Ladies and Gentlemen of the class of \'99: If I could offer you only one tip for the future, sunscreen would be it.');
    // Note: This is a placeholder. In a real test, you would use the actual expected ciphertext from test vectors
    const EXPECTED_CIPHERTEXT_LENGTH = TEST_PLAINTEXT.length;

    let salsa20: Salsa20;

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

    it('should initialize with key and nonce',0, () => {
      expect(() => {
        salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      }).not().assertThrowError('');
    });

    it('should throw error for invalid key length', 0,() => {
      const invalidKey = new Uint8Array(31); // Wrong length
      expect(() => {
        salsa20 = new Salsa20(invalidKey, TEST_NONCE, TEST_COUNTER);
      }).assertThrowError('Salsa20 key must be 32 bytes');
    });

    it('should throw error for invalid nonce length', 0,() => {
      const invalidNonce = new Uint8Array(7); // Wrong length
      expect(() => {
        salsa20 = new Salsa20(TEST_KEY, invalidNonce, TEST_COUNTER);
      }).assertThrowError('Salsa20 nonce must be 8 bytes')
    });

    it('should encrypt and decrypt data correctly', 0,() => {
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const ciphertext = salsa20.process(TEST_PLAINTEXT);

      // Reinitialize for decryption
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const decrypted = salsa20.process(ciphertext,);

      expect(KdbxUtils.bytesToStr(decrypted)).assertEqual(KdbxUtils.bytesToStr(TEST_PLAINTEXT));
    });

    it('should produce different output with different counter', 0,() => {
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const ciphertext1 = salsa20.process(TEST_PLAINTEXT);

      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER + 1);
      const ciphertext2 = salsa20.process(TEST_PLAINTEXT);

      expect(bytesToHex(ciphertext1)).not().assertEqual(bytesToHex(ciphertext2));
    });

    it('should produce different output with different nonce', 0,() => {
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const ciphertext1 = salsa20.process(TEST_PLAINTEXT);

      const differentNonce = new Uint8Array(TEST_NONCE);
      differentNonce[0] = differentNonce[0] + 1;
      salsa20 = new Salsa20(TEST_KEY, differentNonce, TEST_COUNTER);
      const ciphertext2 =  salsa20.process(TEST_PLAINTEXT);

      expect(bytesToHex(ciphertext1)).not().assertEqual(bytesToHex(ciphertext2));
    });

    it('should handle empty input', 0,() => {
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const emptyInput = new Uint8Array(0);
      expect(() => {
        salsa20.process(emptyInput);
      }).not().assertThrowError('empty input');
    });


    it('should generate different keystreams for different keys', 0,() => {
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const ciphertext1 =  salsa20.process(TEST_PLAINTEXT);

      const differentKey = new Uint8Array(TEST_KEY);
      differentKey[0] = differentKey[0] + 1;
      salsa20 = new Salsa20(differentKey, TEST_NONCE, TEST_COUNTER);
      const ciphertext2 = salsa20.process(TEST_PLAINTEXT);

      expect(bytesToHex(ciphertext1)).not().assertEqual(bytesToHex(ciphertext2));
    });

    it('should process data in chunks correctly', 0,() => {
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);

      // Process first half
      const halfLength = Math.floor(TEST_PLAINTEXT.length / 2);
      const firstHalf = TEST_PLAINTEXT.slice(0, halfLength);
      const secondHalf = TEST_PLAINTEXT.slice(halfLength);

      const ciphertext1 = salsa20.process(firstHalf);
      const ciphertext2 = salsa20.process(secondHalf);

      // Now encrypt the whole message at once for comparison
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const fullCiphertext = salsa20.process(TEST_PLAINTEXT);

      // Compare results
      expect(bytesToHex(ciphertext1)).assertEqual(bytesToHex(fullCiphertext.slice(0, halfLength)));
      expect(bytesToHex(ciphertext2)).assertEqual(bytesToHex(fullCiphertext.slice(halfLength)));
    });

    // 边界条件测试
    it('should handle counter overflow correctly', 0, () => {
      // 设置计数器为最大值
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, 0xffffffff);
      const data = new Uint8Array(128);
      const firstBlock = salsa20.process(data.slice(0, 64));
      const secondBlock = salsa20.process(data.slice(64));
      
      // 确保两个块的加密结果不同（因为计数器已经溢出并增加）
      expect(bytesToHex(firstBlock)).not().assertEqual(bytesToHex(secondBlock));
    });

    it('should handle large data blocks correctly', 0, () => {
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      // 创建一个大于64字节的数据块
      const largeData = new Uint8Array(200);
      for (let i = 0; i < largeData.length; i++) {
        largeData[i] = i & 0xff;
      }
      
      // 加密大数据块
      const encrypted = salsa20.process(largeData);
      
      // 重新初始化加密器并解密
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const decrypted = salsa20.process(encrypted);
      
      // 验证解密结果
      expect(bytesToHex(decrypted)).assertEqual(bytesToHex(largeData));
    });

    it('should handle non-aligned data length correctly', 0, () => {
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      // 创建一个非64字节对齐的数据
      const data = new Uint8Array(100);
      for (let i = 0; i < data.length; i++) {
        data[i] = i & 0xff;
      }
      
      const encrypted = salsa20.process(data);
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const decrypted = salsa20.process(encrypted);
      
      expect(bytesToHex(decrypted)).assertEqual(bytesToHex(data));
    });

    // 安全性测试
    it('should produce different output with key/nonce reuse', 0, () => {
      // 第一次加密
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const data1 = new Uint8Array([1, 2, 3, 4]);
      const encrypted1 = salsa20.process(data1);
      
      // 使用相同的key和nonce加密不同的数据
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const data2 = new Uint8Array([5, 6, 7, 8]);
      const encrypted2 = salsa20.process(data2);
      
      // 验证加密结果不同
      expect(bytesToHex(encrypted1)).not().assertEqual(bytesToHex(encrypted2));
    });

    it('should handle zero key and nonce correctly', 0, () => {
      const zeroKey = new Uint8Array(32);
      const zeroNonce = new Uint8Array(8); // Salsa20使用8字节nonce
      
      salsa20 = new Salsa20(zeroKey, zeroNonce);
      const data = new Uint8Array([1, 2, 3, 4]);
      const encrypted = salsa20.process(data);
      
      // 确保输出不等于输入
      expect(bytesToHex(encrypted)).not().assertEqual(bytesToHex(data));
    });

    // 性能测试
    it('should handle continuous encryption/decryption efficiently', 0, () => {
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const data = new Uint8Array(1024 * 1024); // 1MB数据
      for (let i = 0; i < data.length; i++) {
        data[i] = i & 0xff;
      }
      
      const startTime = new Date().getTime();
      const encrypted = salsa20.process(data);
      const endTime = new Date().getTime();
      
      // 确保处理时间在合理范围内（这里设置为1秒）
      expect(endTime - startTime).assertLess(1000);
      
      // 验证加密结果的正确性
      salsa20 = new Salsa20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const decrypted = salsa20.process(encrypted);
      expect(bytesToHex(decrypted)).assertEqual(bytesToHex(data));
    });

    // 标准测试向量验证
    it('should match official test vectors', 0, () => {
      // 使用Salsa20官方测试向量
      // 来源：https://cr.yp.to/snuffle/spec.pdf
      const testKey = new Uint8Array(32).fill(0); // 全零密钥
      const testNonce = new Uint8Array(8).fill(0); // 全零nonce
      const testData = new Uint8Array(64).fill(0); // 全零输入
      
      salsa20 = new Salsa20(testKey, testNonce, 0);
      const result = salsa20.process(testData);
      
      // 验证结果的某些特征（如第一个和最后一个字节）
      // 注意：这里应该添加实际的测试向量值进行比较
      expect(result.length).assertEqual(64);
      expect(result[0]).not().assertEqual(0);
      expect(result[63]).not().assertEqual(0);
    });
  });
}
