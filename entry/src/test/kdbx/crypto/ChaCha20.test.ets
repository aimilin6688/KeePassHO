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
import { ChaCha20 } from '../../../main/ets/kdbx/crypto/ChaCha20';
import { KdbxUtils } from '../../../main/ets/kdbx/utils/KdbxUtils';

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

export default function ChaCha20UnitTest() {
  describe('ChaCha20', () => {
    // Test vectors from RFC 8439 Section 2.4.2
    const TEST_KEY = hexToBytes('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
    const TEST_NONCE = hexToBytes('000000000000004a00000000');
    const TEST_COUNTER = 1;
    const TEST_PLAINTEXT: Uint8Array = KdbxUtils.strToBytes('Ladies and Gentlemen of the class of \'99: If I could offer you only one tip for the future, sunscreen would be it.');
    const EXPECTED_CIPHERTEXT =
      hexToBytes('6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d');

    let chaCha20: ChaCha20;

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

    it('should initialize with key and nonce', 0, () => {
      expect(() => {
        chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      }).not().assertThrowError("ChaCha20 key must be 32 bytes");
    });

    it('should throw error for invalid key length', 0, () => {
      const invalidKey = new Uint8Array(31); // Wrong length
      expect(() => {
        chaCha20 = new ChaCha20(invalidKey, TEST_NONCE, TEST_COUNTER);
      }).assertThrowError("ChaCha20 key must be 32 bytes");
    });

    it('should throw error for invalid nonce length', 0, () => {
      const invalidNonce = new Uint8Array(11); // Wrong length
      expect(() => {
        chaCha20 = new ChaCha20(TEST_KEY, invalidNonce, TEST_COUNTER);
      }).assertThrowError("ChaCha20 nonce must be 12 bytes");
    });

    it('should encrypt data correctly', 0, () => {
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const ciphertext = chaCha20.process(TEST_PLAINTEXT);
      expect(bytesToHex(ciphertext)).assertEqual(bytesToHex(EXPECTED_CIPHERTEXT));
    });

    it('should decrypt data correctly', 0, () => {
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const decrypted = chaCha20.process(EXPECTED_CIPHERTEXT);
      console.log(KdbxUtils.bytesToStr(decrypted));
      expect(KdbxUtils.bytesToStr(decrypted)).assertEqual(KdbxUtils.bytesToStr(TEST_PLAINTEXT));
    });

    it('should produce different output with different counter', 0, () => {
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const ciphertext1 = chaCha20.process(TEST_PLAINTEXT);

      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER + 1);
      const ciphertext2 = chaCha20.process(TEST_PLAINTEXT);

      expect(bytesToHex(ciphertext1)).not().assertEqual(bytesToHex(ciphertext2));
    });

    it('should produce different output with different nonce', 0, () => {
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const ciphertext1 = chaCha20.process(TEST_PLAINTEXT);

      const differentNonce = new Uint8Array(TEST_NONCE);
      differentNonce[0] = 1;
      chaCha20 = new ChaCha20(TEST_KEY, differentNonce, TEST_COUNTER);
      const ciphertext2 = chaCha20.process(TEST_PLAINTEXT);

      expect(bytesToHex(ciphertext1)).not().assertEqual(bytesToHex(ciphertext2));
    });

    it('should handle empty input', 0, () => {
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const emptyInput = new Uint8Array(0);
      expect(() => {
        const output = chaCha20.process(emptyInput);
      }).not().assertThrowError('should handle empty input')
    });

    // 边界条件测试
    it('should handle counter overflow correctly', 0, () => {
      // 设置计数器为最大值
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, 0xffffffff);
      const data = new Uint8Array(128);
      const firstBlock = chaCha20.process(data.slice(0, 64));
      const secondBlock = chaCha20.process(data.slice(64));
      
      // 确保两个块的加密结果不同（因为计数器已经溢出并增加）
      expect(bytesToHex(firstBlock)).not().assertEqual(bytesToHex(secondBlock));
    });

    it('should handle large data blocks correctly', 0, () => {
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      // 创建一个大于64字节的数据块
      const largeData = new Uint8Array(200);
      for (let i = 0; i < largeData.length; i++) {
        largeData[i] = i & 0xff;
      }
      
      // 加密大数据块
      const encrypted = chaCha20.process(largeData);
      
      // 重新初始化加密器并解密
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const decrypted = chaCha20.process(encrypted);
      
      // 验证解密结果
      expect(bytesToHex(decrypted)).assertEqual(bytesToHex(largeData));
    });

    it('should handle non-aligned data length correctly', 0, () => {
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      // 创建一个非64字节对齐的数据
      const data = new Uint8Array(100);
      for (let i = 0; i < data.length; i++) {
        data[i] = i & 0xff;
      }
      
      const encrypted = chaCha20.process(data);
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const decrypted = chaCha20.process(encrypted);
      
      expect(bytesToHex(decrypted)).assertEqual(bytesToHex(data));
    });

    // 安全性测试
    it('should produce different output with key/nonce reuse', 0, () => {
      // 第一次加密
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const data1 = new Uint8Array([1, 2, 3, 4]);
      const encrypted1 = chaCha20.process(data1);
      
      // 使用相同的key和nonce加密不同的数据
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const data2 = new Uint8Array([5, 6, 7, 8]);
      const encrypted2 = chaCha20.process(data2);
      
      // 验证加密结果不同
      expect(bytesToHex(encrypted1)).not().assertEqual(bytesToHex(encrypted2));
    });

    it('should handle zero key and nonce correctly', 0, () => {
      const zeroKey = new Uint8Array(32);
      const zeroNonce = new Uint8Array(12);
      
      chaCha20 = new ChaCha20(zeroKey, zeroNonce);
      const data = new Uint8Array([1, 2, 3, 4]);
      const encrypted = chaCha20.process(data);
      
      // 确保输出不等于输入
      expect(bytesToHex(encrypted)).not().assertEqual(bytesToHex(data));
    });

    // 性能测试
    it('should handle continuous encryption/decryption efficiently', 0, () => {
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const data = new Uint8Array(1024 * 1024); // 1MB数据
      for (let i = 0; i < data.length; i++) {
        data[i] = i & 0xff;
      }
      
      const startTime = new Date().getTime();
      const encrypted = chaCha20.process(data);
      const endTime = new Date().getTime();
      
      // 确保处理时间在合理范围内（这里设置为1秒）
      expect(endTime - startTime).assertLess(1000);
      
      // 验证加密结果的正确性
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
      const decrypted = chaCha20.process(encrypted);
      expect(bytesToHex(decrypted)).assertEqual(bytesToHex(data));
    });
  });
}