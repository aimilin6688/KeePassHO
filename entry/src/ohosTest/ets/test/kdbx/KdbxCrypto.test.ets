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
import { KdbxCrypto } from '../../../../main/ets/kdbx/KdbxCrypto';
import util from '@ohos.util';
import { KdbxUtils } from '../../../../main/ets/kdbx/utils/KdbxUtils';
import { KdfParameters } from '../../../../main/ets/kdbx/models/KdbxTypes';

export default function KdbxCryptoUnitTest() {
  describe('KdbxCrypto', () => {
    // 测试数据
    const testPassword = 'testPassword123';
    const testKeyFile = new Uint8Array([1, 2, 3, 4, 5]); // 示例密钥文件数据
    const testMasterSeed = KdbxUtils.generateRandom(new Uint8Array(32)); // 随机主种子

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

    it('should compute master key with password only',0, async () => {
      const kdfParameters: KdfParameters = {};
      kdfParameters.rounds = 10000;
      kdfParameters.salt=KdbxUtils.generateRandom(new Uint8Array(32));

      const masterKey = await KdbxCrypto.computeMasterKey(testPassword, null, testMasterSeed, kdfParameters);
      expect(masterKey).assertInstanceOf('Uint8Array');
      expect(masterKey.length).assertEqual(32); // SHA-256输出长度
    });

    it('should compute master key with password and key file',0, async () => {
      const kdfParameters: KdfParameters = {};
      kdfParameters.rounds = 10000;
      kdfParameters.salt=KdbxUtils.generateRandom(new Uint8Array(32));

      const masterKey = await KdbxCrypto.computeMasterKey(testPassword, testKeyFile, testMasterSeed, kdfParameters);
      expect(masterKey).assertInstanceOf('Uint8Array');
      expect(masterKey.length).assertEqual(32);

      // 验证使用相同参数生成相同的密钥
      const masterKey2 = await KdbxCrypto.computeMasterKey(testPassword, testKeyFile, testMasterSeed, kdfParameters);
      expect(masterKey).assertEqual(masterKey2);
    });

    it('should perform AES-256-CBC encryption and decryption',0, async () => {
      const key = KdbxUtils.generateRandom(new Uint8Array(32));
      const iv = KdbxUtils.generateRandom(new Uint8Array(16));
      const data = new util.TextEncoder().encode('Hello, World!');

      // 加密
      const encrypted = await KdbxCrypto.aes256CbcEncrypt(data, key, iv);
      expect(encrypted).not().assertUndefined();
      expect(encrypted.length).assertLarger(0);

      // 解密
      const decrypted = await KdbxCrypto.aes256CbcDecrypt(encrypted, key, iv);
      expect(decrypted).not().assertUndefined();
      expect(new util.TextDecoder().decode(decrypted)).assertEqual('Hello, World!');
    });

    it('should calculate HMAC-SHA-256',0, async () => {
      const key = KdbxUtils.generateRandom(new Uint8Array(32));
      const data = new util.TextEncoder().encode('Test Data');

      const hmac = await KdbxCrypto.hmacSha256(data, key);
      expect(hmac).assertInstanceOf('Uint8Array');
      expect(hmac.length).assertEqual(32);

      // 验证相同输入产生相同输出
      const hmac2 = await KdbxCrypto.hmacSha256(data, key);
      expect(hmac).assertEqual(hmac2);
    });

    it('should perform PBKDF2 key derivation',0, async () => {
      const password = new util.TextEncoder().encode('test');
      const salt = KdbxUtils.generateRandom(new Uint8Array(16));
      const iterations = 1000;
      const keyLength = 32;

      const derivedKey = await KdbxCrypto.pbkdf2(password, salt, iterations, keyLength);
      expect(derivedKey).assertInstanceOf('Uint8Array');
      expect(derivedKey.length).assertEqual(keyLength);

      // 验证相同参数产生相同密钥
      const derivedKey2 = await KdbxCrypto.pbkdf2(password, salt, iterations, keyLength);
      expect(derivedKey).assertEqual(derivedKey2);
    });



    it('should handle large data',0, async () => {
      // 创建1MB的测试数据
      const largeData = KdbxUtils.generateRandom(new Uint8Array(1024 * 1024));
      const key = KdbxUtils.generateRandom(new Uint8Array(32));
      const iv = KdbxUtils.generateRandom(new Uint8Array(16));

      // 测试大数据的AES加密解密
      const encrypted = await KdbxCrypto.aes256CbcEncrypt(largeData, key, iv);
      expect(encrypted).not().assertUndefined();

      const decrypted = await KdbxCrypto.aes256CbcDecrypt(encrypted, key, iv);
      expect(decrypted).assertEqual(largeData);

      // 测试大数据的HMAC计算
      const hmac = await KdbxCrypto.hmacSha256(largeData, key);
      expect(hmac).not().assertUndefined();
      expect(hmac.length).assertEqual(32);
    });
  });
}

