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
import { Salsa20 } from '../../../main/ets/kdbx/crypto/Salsa20';

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

describe('Salsa20', () => {
  // Test vectors from https://cr.yp.to/snuffle/spec.pdf
  const TEST_KEY = hexToBytes('0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20');
  const TEST_NONCE = hexToBytes('0102030405060708');
  const TEST_COUNTER = 0;
  const TEST_PLAINTEXT = new TextEncoder().encode('Ladies and Gentlemen of the class of \'99: If I could offer you only one tip for the future, sunscreen would be it.');
  // Note: This is a placeholder. In a real test, you would use the actual expected ciphertext from test vectors
  const EXPECTED_CIPHERTEXT_LENGTH = TEST_PLAINTEXT.length;

  let salsa20: Salsa20;

  beforeAll(() => {
    // 测试套件开始前的设置
  });

  beforeEach(() => {
    // 每个测试用例开始前的设置
    salsa20 = new Salsa20();
  });

  afterEach(() => {
    // 每个测试用例结束后的清理
  });

  afterAll(() => {
    // 测试套件结束后的清理
  });

  it('should initialize with key and nonce', () => {
    expect(() => {
      salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    }).not.toThrow();
  });

  it('should throw error for invalid key length', () => {
    const invalidKey = new Uint8Array(31); // Wrong length
    expect(() => {
      salsa20.init(invalidKey, TEST_NONCE, TEST_COUNTER);
    }).toThrow();
  });

  it('should throw error for invalid nonce length', () => {
    const invalidNonce = new Uint8Array(7); // Wrong length
    expect(() => {
      salsa20.init(TEST_KEY, invalidNonce, TEST_COUNTER);
    }).toThrow();
  });

  it('should encrypt and decrypt data correctly', () => {
    salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const ciphertext = new Uint8Array(TEST_PLAINTEXT.length);
    salsa20.process(TEST_PLAINTEXT, ciphertext);

    // Reinitialize for decryption
    salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const decrypted = new Uint8Array(ciphertext.length);
    salsa20.process(ciphertext, decrypted);

    expect(new TextDecoder().decode(decrypted)).toBe(new TextDecoder().decode(TEST_PLAINTEXT));
  });

  it('should produce different output with different counter', () => {
    salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const ciphertext1 = new Uint8Array(TEST_PLAINTEXT.length);
    salsa20.process(TEST_PLAINTEXT, ciphertext1);

    salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER + 1);
    const ciphertext2 = new Uint8Array(TEST_PLAINTEXT.length);
    salsa20.process(TEST_PLAINTEXT, ciphertext2);

    expect(bytesToHex(ciphertext1)).not.toBe(bytesToHex(ciphertext2));
  });

  it('should produce different output with different nonce', () => {
    salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const ciphertext1 = new Uint8Array(TEST_PLAINTEXT.length);
    salsa20.process(TEST_PLAINTEXT, ciphertext1);

    const differentNonce = new Uint8Array(TEST_NONCE);
    differentNonce[0] = differentNonce[0] + 1;
    salsa20.init(TEST_KEY, differentNonce, TEST_COUNTER);
    const ciphertext2 = new Uint8Array(TEST_PLAINTEXT.length);
    salsa20.process(TEST_PLAINTEXT, ciphertext2);

    expect(bytesToHex(ciphertext1)).not.toBe(bytesToHex(ciphertext2));
  });

  it('should handle empty input', () => {
    salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const emptyInput = new Uint8Array(0);
    const output = new Uint8Array(0);
    expect(() => {
      salsa20.process(emptyInput, output);
    }).not.toThrow();
  });

  it('should throw error if output buffer is too small', () => {
    salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const output = new Uint8Array(TEST_PLAINTEXT.length - 1); // Too small
    expect(() => {
      salsa20.process(TEST_PLAINTEXT, output);
    }).toThrow();
  });

  it('should generate different keystreams for different keys', () => {
    salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const ciphertext1 = new Uint8Array(TEST_PLAINTEXT.length);
    salsa20.process(TEST_PLAINTEXT, ciphertext1);

    const differentKey = new Uint8Array(TEST_KEY);
    differentKey[0] = differentKey[0] + 1;
    salsa20.init(differentKey, TEST_NONCE, TEST_COUNTER);
    const ciphertext2 = new Uint8Array(TEST_PLAINTEXT.length);
    salsa20.process(TEST_PLAINTEXT, ciphertext2);

    expect(bytesToHex(ciphertext1)).not.toBe(bytesToHex(ciphertext2));
  });

  it('should process data in chunks correctly', () => {
    salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER);

    // Process first half
    const halfLength = Math.floor(TEST_PLAINTEXT.length / 2);
    const firstHalf = TEST_PLAINTEXT.slice(0, halfLength);
    const secondHalf = TEST_PLAINTEXT.slice(halfLength);

    const ciphertext1 = new Uint8Array(halfLength);
    const ciphertext2 = new Uint8Array(TEST_PLAINTEXT.length - halfLength);

    salsa20.process(firstHalf, ciphertext1);
    salsa20.process(secondHalf, ciphertext2);

    // Now encrypt the whole message at once for comparison
    salsa20.init(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const fullCiphertext = new Uint8Array(TEST_PLAINTEXT.length);
    salsa20.process(TEST_PLAINTEXT, fullCiphertext);

    // Compare results
    expect(bytesToHex(ciphertext1)).toBe(bytesToHex(fullCiphertext.slice(0, halfLength)));
    expect(bytesToHex(ciphertext2)).toBe(bytesToHex(fullCiphertext.slice(halfLength)));
  });
});
