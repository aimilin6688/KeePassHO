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
import { KdbxError, KdbxErrorCode } from '../../../main/ets/kdbx/KdbxError';

describe('KdbxError', () => {
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

  it('should create error with default values', () => {
    const error = new KdbxError();

    expect(error).toBeInstanceOf(Error);
    expect(error).toBeInstanceOf(KdbxError);
    expect(error.name).toBe('KdbxError');
    expect(error.code).toBe(KdbxErrorCode.UNKNOWN);
    expect(error.message).toBe('未知错误');
    expect(error.originalError).toBeUndefined();
    expect(error.details).toBeUndefined();
  });

  it('should create error with custom message', () => {
    const message = '自定义错误消息';
    const error = new KdbxError(KdbxErrorCode.INVALID_ARGUMENT, message);

    expect(error.code).toBe(KdbxErrorCode.INVALID_ARGUMENT);
    expect(error.message).toBe(message);
  });

  it('should create error with original error', () => {
    const originalError = new Error('原始错误');
    const error = new KdbxError(
      KdbxErrorCode.OPERATION_FAILED,
      '操作失败',
      originalError
    );

    expect(error.code).toBe(KdbxErrorCode.OPERATION_FAILED);
    expect(error.originalError).toBe(originalError);
  });

  it('should create error with details', () => {
    const details = { field: 'password', value: '****' };
    const error = new KdbxError(
      KdbxErrorCode.INVALID_CREDENTIALS,
      '无效的凭证',
      undefined,
      details
    );

    expect(error.code).toBe(KdbxErrorCode.INVALID_CREDENTIALS);
    expect(error.details).toEqual(details);
  });

  it('should get default message for each error code', () => {
    // 测试所有错误代码的默认消息
    Object.values(KdbxErrorCode).forEach(code => {
      const error = new KdbxError(code);
      expect(error.message).toBeDefined();
      expect(error.message.length).toBeGreaterThan(0);
    });
  });

  it('should get suggestion for specific error codes', () => {
    const testCases = [
      {
        code: KdbxErrorCode.FILE_NOT_FOUND,
        expectedSuggestion: '请检查文件路径是否正确，文件是否存在。'
      },
      {
        code: KdbxErrorCode.FILE_ACCESS_DENIED,
        expectedSuggestion: '请检查文件权限，确保应用有足够的访问权限。'
      },
      {
        code: KdbxErrorCode.INVALID_CREDENTIALS,
        expectedSuggestion: '请检查密码或密钥文件是否正确。'
      },
      {
        code: KdbxErrorCode.INVALID_KEYFILE,
        expectedSuggestion: '请确保使用有效的密钥文件格式（XML、二进制或十六进制）。'
      },
      {
        code: KdbxErrorCode.DATABASE_CORRUPTED,
        expectedSuggestion: '数据库文件可能已损坏，请尝试使用备份文件恢复。'
      },
      {
        code: KdbxErrorCode.OUT_OF_MEMORY,
        expectedSuggestion: '请关闭其他应用释放内存，或增加设备内存。'
      },
      {
        code: KdbxErrorCode.NETWORK_ERROR,
        expectedSuggestion: '请检查网络连接是否正常。'
      },
      {
        code: KdbxErrorCode.TIMEOUT,
        expectedSuggestion: '请检查网络连接，或稍后重试。'
      }
    ];

    testCases.forEach(({ code, expectedSuggestion }) => {
      const error = new KdbxError(code);
      expect(error.getSuggestion()).toBe(expectedSuggestion);
    });
  });

  it('should get full message with all information', () => {
    const originalError = new Error('原始错误');
    const details = { field: 'password' };
    const error = new KdbxError(
      KdbxErrorCode.INVALID_CREDENTIALS,
      '密码错误',
      originalError,
      details
    );

    const fullMessage = error.getFullMessage();

    expect(fullMessage).toContain('密码错误');
    expect(fullMessage).toContain('错误代码: INVALID_CREDENTIALS');
    expect(fullMessage).toContain('详细信息: {"field":"password"}');
    expect(fullMessage).toContain('原始错误: 原始错误');
    expect(fullMessage).toContain('处理建议: ');
  });

  it('should create error using static create method', () => {
    const error = KdbxError.create(
      KdbxErrorCode.ENCRYPTION_FAILED,
      '加密失败',
      new Error('加密错误'),
      { algorithm: 'AES' }
    );

    expect(error).toBeInstanceOf(KdbxError);
    expect(error.code).toBe(KdbxErrorCode.ENCRYPTION_FAILED);
    expect(error.message).toBe('加密失败');
    expect(error.originalError).toBeDefined();
    expect(error.details).toBeDefined();
  });

  it('should wrap existing error', () => {
    const originalError = new Error('网络连接失败');
    const wrappedError = KdbxError.wrap(
      originalError,
      KdbxErrorCode.NETWORK_ERROR,
      '同步失败',
      { url: 'https://example.com' }
    );

    expect(wrappedError).toBeInstanceOf(KdbxError);
    expect(wrappedError.code).toBe(KdbxErrorCode.NETWORK_ERROR);
    expect(wrappedError.message).toBe('同步失败');
    expect(wrappedError.originalError).toBe(originalError);
    expect(wrappedError.details).toBeDefined();
  });

  it('should wrap error with default values', () => {
    const originalError = new Error('测试错误');
    const wrappedError = KdbxError.wrap(originalError);

    expect(wrappedError).toBeInstanceOf(KdbxError);
    expect(wrappedError.code).toBe(KdbxErrorCode.UNKNOWN);
    expect(wrappedError.message).toBe('测试错误');
    expect(wrappedError.originalError).toBe(originalError);
  });

  it('should handle error inheritance correctly', () => {
    const error = new KdbxError(KdbxErrorCode.INVALID_ARGUMENT);

    // 验证错误继承链
    expect(error instanceof Error).toBe(true);
    expect(error instanceof KdbxError).toBe(true);
    expect(Object.getPrototypeOf(error)).toBe(KdbxError.prototype);
    expect(Object.getPrototypeOf(Object.getPrototypeOf(error))).toBe(Error.prototype);
  });

  it('should handle stack trace', () => {
    const error = new KdbxError(KdbxErrorCode.INVALID_ARGUMENT);

    expect(error.stack).toBeDefined();
    expect(error.stack.includes('KdbxError')).toBe(true);
  });

  it('should handle error code validation', () => {
    // 验证所有错误代码都是有效的字符串
    Object.values(KdbxErrorCode).forEach(code => {
      expect(typeof code).toBe('string');
      expect(code.length).toBeGreaterThan(0);
    });
  });

  it('should handle error code uniqueness', () => {
    // 验证错误代码的唯一性
    const codes = Object.values(KdbxErrorCode);
    const uniqueCodes = new Set(codes);
    expect(uniqueCodes.size).toBe(codes.length);
  });

  it('should handle error grouping', () => {
    // 验证错误分组
    const fileErrors = [
      KdbxErrorCode.FILE_NOT_FOUND,
      KdbxErrorCode.FILE_ACCESS_DENIED,
      KdbxErrorCode.FILE_CORRUPTED,
      KdbxErrorCode.INVALID_FILE_FORMAT,
      KdbxErrorCode.UNSUPPORTED_VERSION,
      KdbxErrorCode.FILE_LOCKED
    ];

    const encryptionErrors = [
      KdbxErrorCode.ENCRYPTION_FAILED,
      KdbxErrorCode.DECRYPTION_FAILED,
      KdbxErrorCode.INVALID_KEY,
      KdbxErrorCode.INVALID_CREDENTIALS,
      KdbxErrorCode.KEY_DERIVATION_FAILED,
      KdbxErrorCode.INVALID_KEYFILE
    ];

    const databaseErrors = [
      KdbxErrorCode.DATABASE_CORRUPTED,
      KdbxErrorCode.INVALID_DATABASE_STRUCTURE,
      KdbxErrorCode.DATABASE_NOT_LOADED,
      KdbxErrorCode.ENTRY_NOT_FOUND,
      KdbxErrorCode.GROUP_NOT_FOUND,
      KdbxErrorCode.DUPLICATE_UUID,
      KdbxErrorCode.INVALID_FIELD
    ];

    // 验证每个分组中的错误代码都存在且有效
    [...fileErrors, ...encryptionErrors, ...databaseErrors].forEach(code => {
      const error = new KdbxError(code);
      expect(error.message).toBeDefined();
      expect(error.getSuggestion()).toBeDefined();
    });
  });
});
