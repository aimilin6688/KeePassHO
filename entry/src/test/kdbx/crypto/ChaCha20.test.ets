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
import { util, buffer } from '@kit.ArkTS';

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

describe('ChaCha20', () => {
  // Test vectors from RFC 8439 Section 2.4.2
  const TEST_KEY = hexToBytes('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
  const TEST_NONCE = hexToBytes('000000000000004a00000000');
  const TEST_COUNTER = 1;
  const TEST_PLAINTEXT: Uint8Array =
    new util.TextEncoder().encodeInto('Ladies and Gentlemen of the class of \'99: If I could offer you only one tip for the future, sunscreen would be it.');
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

  it('should initialize with key and nonce', () => {
    expect(() => {
      chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    }).not().assertThrowError("ChaCha20 key must be 32 bytes");
  });

  it('should throw error for invalid key length', () => {
    const invalidKey = new Uint8Array(31); // Wrong length
    expect(() => {
      chaCha20 = new ChaCha20(invalidKey, TEST_NONCE, TEST_COUNTER);
    }).assertThrowError("ChaCha20 key must be 32 bytes");
  });

  it('should throw error for invalid nonce length', () => {
    const invalidNonce = new Uint8Array(11); // Wrong length
    expect(() => {
      chaCha20 = new ChaCha20(TEST_KEY, invalidNonce, TEST_COUNTER);
    }).assertThrowError("ChaCha20 nonce must be 12 bytes");
  });

  it('should encrypt data correctly', () => {
    chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const ciphertext = chaCha20.process(TEST_PLAINTEXT);
    expect(bytesToHex(ciphertext)).assertEqual(bytesToHex(EXPECTED_CIPHERTEXT));
  });

  it('should decrypt data correctly', () => {
    chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const decrypted = chaCha20.process(EXPECTED_CIPHERTEXT);
    expect(new util.TextDecoder().decode(decrypted)).assertEqual(new util.TextDecoder().decode(TEST_PLAINTEXT));
  });

  it('should produce different output with different counter', () => {
    chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const ciphertext1 = chaCha20.process(TEST_PLAINTEXT);

    chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER + 1);
    const ciphertext2 = chaCha20.process(TEST_PLAINTEXT);

    expect(bytesToHex(ciphertext1)).not().assertEqual(bytesToHex(ciphertext2));
  });

  it('should produce different output with different nonce', () => {
    chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const ciphertext1 = chaCha20.process(TEST_PLAINTEXT);

    const differentNonce = new Uint8Array(TEST_NONCE);
    differentNonce[0] = 1;
    chaCha20 = new ChaCha20(TEST_KEY, differentNonce, TEST_COUNTER);
    const ciphertext2 = chaCha20.process(TEST_PLAINTEXT);

    expect(bytesToHex(ciphertext1)).not().assertEqual(bytesToHex(ciphertext2));
  });

  it('should handle empty input', () => {
    chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    const emptyInput = new Uint8Array(0);
    expect(() => {
      const output = chaCha20.process(emptyInput);
    }).not().assertThrowError('should handle empty input')
  });

  it('should throw error if output buffer is too small', () => {
    chaCha20 = new ChaCha20(TEST_KEY, TEST_NONCE, TEST_COUNTER);
    expect(() => {
      chaCha20.process(TEST_PLAINTEXT);
    }).assertThrowError('output buffer is too small')
  });
});
