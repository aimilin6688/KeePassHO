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
import { KdbxCredentials, KeyFileFormat } from '../../../main/ets/kdbx/KdbxCredentials';
import util from '@ohos.util';
import { KdbxUtils } from '../../main/ets/kdbx/utils/KdbxUtils';

describe('KdbxCredentials', () => {
  let credentials: KdbxCredentials;

  beforeAll(() => {
    // 测试套件开始前的设置
  });

  beforeEach(() => {
    // 每个测试用例开始前的设置
    credentials = new KdbxCredentials();
  });

  afterEach(() => {
    // 每个测试用例结束后的清理
    credentials.clear();
  });

  afterAll(() => {
    // 测试套件结束后的清理
  });

  it('should handle password credentials', async () => {
    const password = 'testPassword123';
    credentials.setPassword(password);

    expect(credentials.isValid()).assertEqual(true);

    const compositeKey = await credentials.getCompositeKey();
    expect(compositeKey).toBeDefined();
    expect(compositeKey.length).assertEqual(32); // SHA-256输出长度

    // 验证相同密码生成相同的密钥
    const credentials2 = new KdbxCredentials();
    credentials2.setPassword(password);
    const compositeKey2 = await credentials2.getCompositeKey();
    expect(compositeKey).toEqual(compositeKey2);
  });

  it('should handle key file in XML format', async () => {
    // 生成XML格式的密钥文件
    const keyFileData = await KdbxCredentials.generateKeyFile(KeyFileFormat.XML);
    expect(keyFileData).toBeDefined();

    // 验证生成的XML格式
    const xmlString = new util.TextDecoder().decode(keyFileData);
    expect(xmlString).toContain('<?xml version="1.0" encoding="utf-8"?>');
    expect(xmlString).toContain('<KeyFile>');
    expect(xmlString).toContain('<Version>2.0</Version>');
    expect(xmlString).toContain('<Data>');

    // 使用生成的密钥文件
    credentials.setKeyFileData(keyFileData);
    expect(credentials.isValid()).assertEqual(true);

    const compositeKey = await credentials.getCompositeKey();
    expect(compositeKey).toBeDefined();
    expect(compositeKey.length).assertEqual(32);
  });

  it('should handle key file in binary format', async () => {
    // 生成二进制格式的密钥文件
    const keyFileData = await KdbxCredentials.generateKeyFile(KeyFileFormat.BINARY);
    expect(keyFileData).toBeDefined();
    expect(keyFileData.length).assertEqual(32);

    // 使用生成的密钥文件
    credentials.setKeyFileData(keyFileData);
    expect(credentials.isValid()).assertEqual(true);

    const compositeKey = await credentials.getCompositeKey();
    expect(compositeKey).toBeDefined();
    expect(compositeKey.length).assertEqual(32);
  });

  it('should handle key file in hex format', async () => {
    // 生成十六进制格式的密钥文件
    const keyFileData = await KdbxCredentials.generateKeyFile(KeyFileFormat.HEX);
    expect(keyFileData).toBeDefined();

    // 验证生成的十六进制格式
    const hexString = new util.TextDecoder().decode(keyFileData);
    expect(hexString.length).assertEqual(64);
    expect(/^[0-9A-Fa-f]{64}$/.test(hexString)).assertEqual(true);

    // 使用生成的密钥文件
    credentials.setKeyFileData(keyFileData);
    expect(credentials.isValid()).assertEqual(true);

    const compositeKey = await credentials.getCompositeKey();
    expect(compositeKey).toBeDefined();
    expect(compositeKey.length).assertEqual(32);
  });

  it('should handle Windows user account data', async () => {
    // 模拟Windows用户账户数据
    const userData =KdbxUtils.generateRandom(new Uint8Array(32));
    credentials.setWindowsUserData(userData);

    expect(credentials.isValid()).assertEqual(true);

    const compositeKey = await credentials.getCompositeKey();
    expect(compositeKey).toBeDefined();
    expect(compositeKey.length).assertEqual(32);

    // 验证相同用户数据生成相同的密钥
    const credentials2 = new KdbxCredentials();
    credentials2.setWindowsUserData(userData);
    const compositeKey2 = await credentials2.getCompositeKey();
    expect(compositeKey).toEqual(compositeKey2);
  });

  it('should combine multiple credentials', async () => {
    const password = 'testPassword123';
    const keyFileData = await KdbxCredentials.generateKeyFile(KeyFileFormat.BINARY);
    const userData = KdbxUtils.generateRandom(new Uint8Array(32));

    // 设置所有凭证
    credentials.setPassword(password);
    credentials.setKeyFileData(keyFileData);
    credentials.setWindowsUserData(userData);

    expect(credentials.isValid()).assertEqual(true);

    const compositeKey = await credentials.getCompositeKey();
    expect(compositeKey).toBeDefined();
    expect(compositeKey.length).assertEqual(32);

    // 验证相同凭证组合生成相同的密钥
    const credentials2 = new KdbxCredentials();
    credentials2.setPassword(password);
    credentials2.setKeyFileData(keyFileData);
    credentials2.setWindowsUserData(userData);
    const compositeKey2 = await credentials2.getCompositeKey();
    expect(compositeKey).toEqual(compositeKey2);
  });

  it('should clear credentials', () => {
    credentials.setPassword('testPassword');
    credentials.setKeyFileData(new Uint8Array(32));
    credentials.setWindowsUserData(new Uint8Array(32));

    expect(credentials.isValid()).assertEqual(true);

    credentials.clear();
    expect(credentials.isValid()).assertEqual(false);
  });

  it('should validate credentials', () => {
    expect(credentials.isValid()).assertEqual(false);

    credentials.setPassword('testPassword');
    expect(credentials.isValid()).assertEqual(true);

    credentials.clear();
    expect(credentials.isValid()).assertEqual(false);

    credentials.setKeyFileData(new Uint8Array(32));
    expect(credentials.isValid()).assertEqual(true);

    credentials.clear();
    expect(credentials.isValid()).assertEqual(false);

    credentials.setWindowsUserData(new Uint8Array(32));
    expect(credentials.isValid()).assertEqual(true);
  });

  it('should handle empty credentials', async () => {
    const compositeKey = await credentials.getCompositeKey();
    expect(compositeKey).toBeDefined();
    expect(compositeKey.length).assertEqual(32);
    expect(new Set(compositeKey).size).assertEqual(1); // 应该全是0
  });

  it('should handle invalid key file formats', async () => {
    // 测试无效的XML
    const invalidXml = new util.TextEncoder().encode('<invalid>XML</data>');
    credentials.setKeyFileData(invalidXml);
    const compositeKey1 = await credentials.getCompositeKey();
    expect(compositeKey1.length).assertEqual(32);

    // 测试无效的十六进制字符串
    const invalidHex = new util.TextEncoder().encode('NotHexString');
    credentials.setKeyFileData(invalidHex);
    const compositeKey2 = await credentials.getCompositeKey();
    expect(compositeKey2.length).assertEqual(32);

    // 测试无效长度的二进制数据
    const invalidBinary = new Uint8Array(16); // 不是32字节
    credentials.setKeyFileData(invalidBinary);
    const compositeKey3 = await credentials.getCompositeKey();
    expect(compositeKey3.length).assertEqual(32);
  });

  it('should handle special characters in password', async () => {
    const specialPassword = '!@#$%^&*()_+{}|:"<>?~`-=[]\\;\',./';
    credentials.setPassword(specialPassword);

    const compositeKey = await credentials.getCompositeKey();
    expect(compositeKey).toBeDefined();
    expect(compositeKey.length).assertEqual(32);

    // 验证相同密码生成相同的密钥
    const credentials2 = new KdbxCredentials();
    credentials2.setPassword(specialPassword);
    const compositeKey2 = await credentials2.getCompositeKey();
    expect(compositeKey).toEqual(compositeKey2);
  });

  it('should handle Unicode passwords', async () => {
    const unicodePassword = '密码测试🔑';
    credentials.setPassword(unicodePassword);

    const compositeKey = await credentials.getCompositeKey();
    expect(compositeKey).toBeDefined();
    expect(compositeKey.length).assertEqual(32);

    // 验证相同密码生成相同的密钥
    const credentials2 = new KdbxCredentials();
    credentials2.setPassword(unicodePassword);
    const compositeKey2 = await credentials2.getCompositeKey();
    expect(compositeKey).toEqual(compositeKey2);
  });

  it('should handle large key files', async () => {
    // 创建1MB的随机数据
    const largeKeyFile = KdbxUtils.generateRandom(new Uint8Array(1024 * 1024));
    credentials.setKeyFileData(largeKeyFile);

    const compositeKey = await credentials.getCompositeKey();
    expect(compositeKey).toBeDefined();
    expect(compositeKey.length).assertEqual(32);

    // 验证相同数据生成相同的密钥
    const credentials2 = new KdbxCredentials();
    credentials2.setKeyFileData(largeKeyFile);
    const compositeKey2 = await credentials2.getCompositeKey();
    expect(compositeKey).toEqual(compositeKey2);
  });

  it('should maintain constant time operations', async () => {
    const password1 = 'password1';
    const password2 = 'password2';

    // 记录两次操作的时间
    const start1 = Date.now();
    credentials.setPassword(password1);
    await credentials.getCompositeKey();
    const time1 = Date.now() - start1;

    const start2 = Date.now();
    credentials.setPassword(password2);
    await credentials.getCompositeKey();
    const time2 = Date.now() - start2;

    // 验证时间差异不大（允许10%的误差）
    const timeDiff = Math.abs(time1 - time2);
    expect(timeDiff / Math.max(time1, time2)).toBeLessThan(0.1);
  });
});
