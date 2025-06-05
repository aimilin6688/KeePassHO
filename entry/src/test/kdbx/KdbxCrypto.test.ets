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
import { KdbxCrypto, ProtectedStreamEncryptor } from '../../../main/ets/kdbx/KdbxCrypto';
import { InnerRandomStreamID } from '../../../main/ets/kdbx/KdbxFormat';
import util from '@ohos.util';
import { KdbxUtils } from '../../main/ets/kdbx/utils/KdbxUtils';

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

  it('should compute master key with password only', async () => {
    const kdfParameters = new Map<string, any>();
    kdfParameters.set('rounds', 10000);
    kdfParameters.set('salt', KdbxUtils.generateRandom(new Uint8Array(32)));

    const masterKey = await KdbxCrypto.computeMasterKey(testPassword, null, testMasterSeed, kdfParameters);
    expect(masterKey).toBeInstanceOf(Uint8Array);
    expect(masterKey.length).assertEqual(32); // SHA-256输出长度
  });

  it('should compute master key with password and key file', async () => {
    const kdfParameters = new Map<string, any>();
    kdfParameters.set('rounds', 10000);
    kdfParameters.set('salt', KdbxUtils.generateRandom(new Uint8Array(32)));

    const masterKey = await KdbxCrypto.computeMasterKey(testPassword, testKeyFile, testMasterSeed, kdfParameters);
    expect(masterKey).toBeInstanceOf(Uint8Array);
    expect(masterKey.length).assertEqual(32);

    // 验证使用相同参数生成相同的密钥
    const masterKey2 = await KdbxCrypto.computeMasterKey(testPassword, testKeyFile, testMasterSeed, kdfParameters);
    expect(masterKey).toEqual(masterKey2);
  });

  it('should perform AES-256-CBC encryption and decryption', async () => {
    const key = KdbxUtils.generateRandom(new Uint8Array(32));
    const iv = KdbxUtils.generateRandom(new Uint8Array(16));
    const data = new util.TextEncoder().encode('Hello, World!');

    // 加密
    const encrypted = await KdbxCrypto.aes256CbcEncrypt(data, key, iv);
    expect(encrypted).toBeDefined();
    expect(encrypted.length).toBeGreaterThan(0);

    // 解密
    const decrypted = await KdbxCrypto.aes256CbcDecrypt(encrypted, key, iv);
    expect(decrypted).toBeDefined();
    expect(new util.TextDecoder().decode(decrypted)).assertEqual('Hello, World!');
  });

  it('should calculate HMAC-SHA-256', async () => {
    const key = KdbxUtils.generateRandom(new Uint8Array(32));
    const data = new util.TextEncoder().encode('Test Data');

    const hmac = await KdbxCrypto.hmacSha256(data, key);
    expect(hmac).toBeInstanceOf(Uint8Array);
    expect(hmac.length).assertEqual(32);

    // 验证相同输入产生相同输出
    const hmac2 = await KdbxCrypto.hmacSha256(data, key);
    expect(hmac).toEqual(hmac2);
  });

  it('should perform PBKDF2 key derivation', async () => {
    const password = new util.TextEncoder().encode('test');
    const salt = KdbxUtils.generateRandom(new Uint8Array(16));
    const iterations = 1000;
    const keyLength = 32;

    const derivedKey = await KdbxCrypto.pbkdf2(password, salt, iterations, keyLength);
    expect(derivedKey).toBeInstanceOf(Uint8Array);
    expect(derivedKey.length).assertEqual(keyLength);

    // 验证相同参数产生相同密钥
    const derivedKey2 = await KdbxCrypto.pbkdf2(password, salt, iterations, keyLength);
    expect(derivedKey).toEqual(derivedKey2);
  });

  it('should handle different KDF types', async () => {
    const key = KdbxUtils.generateRandom(new Uint8Array(32));

    // 测试AES-KDF
    const aesKdfParams = new Map<string, any>();
    aesKdfParams.set('$UUID', '7c02bb82-79a7-4ac0-927d-114a00648238');
    aesKdfParams.set('rounds', 10000);
    aesKdfParams.set('seed', KdbxUtils.generateRandom(new Uint8Array(32)));

    const aesResult = await KdbxCrypto.computeMasterKey(testPassword, null, testMasterSeed, aesKdfParams);
    expect(aesResult).toBeDefined();
    expect(aesResult.length).assertEqual(32);

    // 测试Argon2id（会回退到PBKDF2）
    const argon2Params = new Map<string, any>();
    argon2Params.set('$UUID', '9e298b19-56db-4773-b23d-fc3ec6f0a1e6');
    argon2Params.set('salt', KdbxUtils.generateRandom(new Uint8Array(32)));
    argon2Params.set('iterations', 2);
    argon2Params.set('memory', 1024 * 1024);

    const argon2Result = await KdbxCrypto.computeMasterKey(testPassword, null, testMasterSeed, argon2Params);
    expect(argon2Result).toBeDefined();
    expect(argon2Result.length).assertEqual(32);
  });

  it('should create and use protected stream encryptor', () => {
    const key = KdbxUtils.generateRandom(new Uint8Array(32));
    const data = new util.TextEncoder().encode('Protected Data');

    // 测试ChaCha20
    const chacha20Encryptor = KdbxCrypto.createProtectedStreamEncryptor(key, InnerRandomStreamID.CHACHA20);
    expect(chacha20Encryptor).toBeDefined();

    const encrypted = chacha20Encryptor.encrypt(data);
    expect(encrypted).toBeDefined();
    expect(encrypted).not.toEqual(data);

    const decrypted = chacha20Encryptor.decrypt(encrypted);
    expect(decrypted).toEqual(data);

    // 测试Salsa20
    const salsa20Encryptor = KdbxCrypto.createProtectedStreamEncryptor(key, InnerRandomStreamID.SALSA20);
    expect(salsa20Encryptor).toBeDefined();

    const encrypted2 = salsa20Encryptor.encrypt(data);
    expect(encrypted2).toBeDefined();
    expect(encrypted2).not.toEqual(data);

    const decrypted2 = salsa20Encryptor.decrypt(encrypted2);
    expect(decrypted2).toEqual(data);
  });

  it('should handle invalid inputs gracefully', async () => {
    // 测试空密码
    await expect(KdbxCrypto.computeMasterKey('', null, testMasterSeed, new Map())).rejects.toThrow();

    // 测试无效的KDF参数
    const invalidKdfParams = new Map<string, any>();
    invalidKdfParams.set('$UUID', 'invalid-uuid');
    await expect(KdbxCrypto.computeMasterKey(testPassword, null, testMasterSeed, invalidKdfParams)).rejects.toThrow();

    // 测试无效的AES密钥长度
    const invalidKey = new Uint8Array(16); // AES-256需要32字节密钥
    const iv = KdbxUtils.generateRandom(new Uint8Array(16));
    const data = new Uint8Array(16);
    await expect(KdbxCrypto.aes256CbcEncrypt(data, invalidKey, iv)).rejects.toThrow();

    // 测试无效的流加密类型
    expect(() => {
      KdbxCrypto.createProtectedStreamEncryptor(new Uint8Array(32), InnerRandomStreamID.NONE);
    }).toThrow();
  });

  it('should handle large data', async () => {
    // 创建1MB的测试数据
    const largeData = KdbxUtils.generateRandom(new Uint8Array(1024 * 1024));
    const key = KdbxUtils.generateRandom(new Uint8Array(32));
    const iv = KdbxUtils.generateRandom(new Uint8Array(16));

    // 测试大数据的AES加密解密
    const encrypted = await KdbxCrypto.aes256CbcEncrypt(largeData, key, iv);
    expect(encrypted).toBeDefined();

    const decrypted = await KdbxCrypto.aes256CbcDecrypt(encrypted, key, iv);
    expect(decrypted).toEqual(largeData);

    // 测试大数据的HMAC计算
    const hmac = await KdbxCrypto.hmacSha256(largeData, key);
    expect(hmac).toBeDefined();
    expect(hmac.length).assertEqual(32);
  });

  it('should maintain constant time operations', async () => {
    const password1 = 'password1';
    const password2 = 'password2';
    const kdfParams = new Map<string, any>();
    kdfParams.set('rounds', 1000);
    kdfParams.set('salt', KdbxUtils.generateRandom(new Uint8Array(32)));

    // 记录两次操作的时间
    const start1 = Date.now();
    await KdbxCrypto.computeMasterKey(password1, null, testMasterSeed, kdfParams);
    const time1 = Date.now() - start1;

    const start2 = Date.now();
    await KdbxCrypto.computeMasterKey(password2, null, testMasterSeed, kdfParams);
    const time2 = Date.now() - start2;

    // 验证时间差异不大（允许10%的误差）
    const timeDiff = Math.abs(time1 - time2);
    expect(timeDiff / Math.max(time1, time2)).toBeLessThan(0.1);
  });

  it('should handle concurrent operations', async () => {
    const password = 'test';
    const kdfParams = new Map<string, any>();
    kdfParams.set('rounds', 1000);
    kdfParams.set('salt', KdbxUtils.generateRandom(new Uint8Array(32)));

    // 并发执行多个加密操作
    const operations = [];
    for (let i = 0; i < 5; i++) {
      operations.push(KdbxCrypto.computeMasterKey(password, null, testMasterSeed, kdfParams));
    }

    const results = await Promise.all(operations);

    // 验证所有结果都相同
    for (let i = 1; i < results.length; i++) {
      expect(results[i]).toEqual(results[0]);
    }
  });
});
