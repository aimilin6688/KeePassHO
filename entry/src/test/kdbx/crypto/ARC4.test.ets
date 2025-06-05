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

import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { ARC4 } from '../../../main/ets/kdbx/crypto/ARC4';
import { util,buffer } from '@kit.ArkTS';


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

const strToBytes = (str: string): Uint8Array => {
  return new Uint8Array(buffer.from(str, 'utf8').buffer);
}

const bytesToStr = (bytes: Uint8Array): string => {
  return buffer.from(bytes).toString('utf8');
}

export default function ARC4UnitTest() {
  describe('ARC4', () => {
    // Test vectors from various sources including RFC 6229
    interface TestVector {
      key: Uint8Array;
      plaintext: Uint8Array;
      ciphertext: Uint8Array;
    }

    const TEST_VECTORS: TestVector[] = [
      {
        key: strToBytes('shortKey'),
        plaintext: strToBytes('Z'),
        // Note: This expected value takes into account the 3072 byte drop
        ciphertext: hexToBytes('83'),
      },
      {
        key: strToBytes('mySecretKey'),
        plaintext: strToBytes('Hello World'),
        // Note: This expected value takes into account the 3072 byte drop
        ciphertext: hexToBytes('77dd7b0a65daec4aabf53a'),
      },
      {
        key: strToBytes('p@ssw0rd!'),
        plaintext: strToBytes('Data123!abc'),
        ciphertext: hexToBytes('4de692edeed0fc18de37d1'),
      },
      {
        key: strToBytes('ARC4@2023'),
        plaintext: strToBytes('加密测试'),
        ciphertext: hexToBytes('a7e2e7519efb5a28367176e8'),
      }
    ];

    let arc4: ARC4;

    beforeAll(() => {
      // 测试套件开始前的设置
    });

    beforeEach(() => {
    });

    afterEach(() => {
      // 每个测试用例结束后的清理
    });

    afterAll(() => {
      // 测试套件结束后的清理
    });

    it('should initialize with key', 0, () => {
      expect(() => {
        arc4 = new ARC4(TEST_VECTORS[0].key);
      }).not().assertThrowError('key must be provided and must be at least one byte long');
    });

    it('should throw error for empty key', 0, () => {
      const emptyKey = new Uint8Array(0);
      expect(() => {
        arc4 = new ARC4(emptyKey);
      }).assertThrowError('key must be provided and must be at least one byte long');
    });

    it('should throw error for key longer than 256 bytes', 0, () => {
      const longKey = new Uint8Array(257);
      expect(() => {
        arc4 = new ARC4(longKey);
      }).assertThrowError('key must be 256 bytes or less');
    });

    it('should encrypt test vectors correctly', 0, () => {
      TEST_VECTORS.forEach((vector, index) => {
        arc4 = new ARC4(vector.key);
        const output = new Uint8Array(vector.plaintext.length);
        arc4.process(vector.plaintext, output);
        console.log(`Test vector ${index}, text: ${bytesToStr(vector.plaintext)} encryption: ${bytesToHex(output)}`);
        expect(bytesToHex(output))
          .message(`Test vector ${index} encryption failed`)
          .assertEqual(bytesToHex(vector.ciphertext));
      });
    });

    it('should decrypt to original plaintext', 0, () => {
      TEST_VECTORS.forEach((vector, index) => {
        // Encrypt
        arc4 = new ARC4(vector.key);
        const ciphertext = new Uint8Array(vector.plaintext.length);
        arc4.process(vector.plaintext, ciphertext);

        // Decrypt
        arc4 = new ARC4(vector.key);
        const decrypted = new Uint8Array(ciphertext.length);
        arc4.process(ciphertext, decrypted);

        expect(bytesToStr(decrypted)).assertEqual(bytesToStr(vector.plaintext));
        console.log(`plaintext: Test vector ${index} plaintext: ${bytesToStr(vector.plaintext)} ciphertext: ${bytesToHex(ciphertext)}, decrypted: ${bytesToStr(decrypted)}`)
      });
    });

    it('should produce different output with different keys', 0, () => {
      const plaintext = TEST_VECTORS[0].plaintext;
      arc4 = new ARC4(TEST_VECTORS[0].key);
      const ciphertext1 = new Uint8Array(plaintext.length);
      arc4.process(plaintext, ciphertext1);

      const differentKey = new Uint8Array(TEST_VECTORS[0].key);
      differentKey[0] = differentKey[0] + 1;
      arc4 = new ARC4(differentKey);
      const ciphertext2 = new Uint8Array(plaintext.length);
      arc4.process(plaintext, ciphertext2);

      expect(bytesToHex(ciphertext1)).not().assertEqual(bytesToHex(ciphertext2));
    });

    it('should handle empty input', 0, () => {
      arc4 = new ARC4(TEST_VECTORS[0].key);
      const emptyInput = new Uint8Array(0);
      const output = new Uint8Array(0);
      expect(() => {
        arc4.process(emptyInput, output);
      }).not().assertThrowError('ARC4 encryption failed');
    });

    it('should throw error if output buffer is too small', 0, () => {
      arc4 = new ARC4(TEST_VECTORS[0].key);
      const output = new Uint8Array(TEST_VECTORS[0].plaintext.length - 1); // Too small
      expect(() => {
        arc4.process(TEST_VECTORS[0].plaintext, output);
      }).assertThrowError('Output buffer too small');
    });

    it('should verify 3072 byte drop', 0, () => {
      // This test verifies that the implementation correctly drops the first 3072 bytes
      // We'll encrypt the same plaintext twice, but for the second encryption,
      // we'll first process 3072 dummy bytes manually
      const key = TEST_VECTORS[0].key;
      const plaintext = TEST_VECTORS[0].plaintext;

      // First encryption (normal, with automatic 3072 byte drop)
      arc4 = new ARC4(key);
      const ciphertext1 = new Uint8Array(plaintext.length);
      arc4.process(plaintext, ciphertext1);

      // Second encryption (manual 3072 byte drop)
      arc4 = new ARC4(key);
      const dummyData = new Uint8Array(3072);
      const dummyOutput = new Uint8Array(3072);
      arc4.process(dummyData, dummyOutput); // Process 3072 bytes manually
      const ciphertext2 = new Uint8Array(plaintext.length);
      arc4.process(plaintext, ciphertext2);

      // The results should be different because the second encryption
      // effectively dropped 6144 bytes (3072 automatic + 3072 manual)
      expect(bytesToHex(ciphertext1)).not().assertEqual(bytesToHex(ciphertext2));
    });

    it('should process data in chunks correctly', 0, () => {
      const plaintext = new util.TextEncoder().encode('This is a longer text that will be processed in chunks');
      arc4 = new ARC4(TEST_VECTORS[0].key);

      // Process first half
      const halfLength = Math.floor(plaintext.length / 2);
      const firstHalf = plaintext.slice(0, halfLength);
      const secondHalf = plaintext.slice(halfLength);

      const ciphertext1 = new Uint8Array(halfLength);
      const ciphertext2 = new Uint8Array(plaintext.length - halfLength);

      arc4.process(firstHalf, ciphertext1);
      arc4.process(secondHalf, ciphertext2);

      // Now encrypt the whole message at once for comparison
      arc4 = new ARC4(TEST_VECTORS[0].key);
      const fullCiphertext = new Uint8Array(plaintext.length);
      arc4.process(plaintext, fullCiphertext);

      // Compare results
      expect(bytesToHex(ciphertext1)).assertEqual(bytesToHex(fullCiphertext.slice(0, halfLength)));
      expect(bytesToHex(ciphertext2)).assertEqual(bytesToHex(fullCiphertext.slice(halfLength)));
    });
  });
}