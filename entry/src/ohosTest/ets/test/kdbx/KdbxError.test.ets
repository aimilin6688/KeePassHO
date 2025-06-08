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
import { KdbxError, KdbxErrorCode } from '../../../../main/ets/kdbx/KdbxError';

interface KdbxErrorData {
  code: KdbxErrorCode;
  expectedSuggestion: string;
}

export default function KdbxErrorUnitTest() {
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

    it('should create error with default values', 0, () => {
      const error = new KdbxError();

      expect(error instanceof Error).assertTrue();
      expect(error instanceof KdbxError).assertTrue();
      expect(error.name).assertEqual('KdbxError');
      expect(error.code).assertEqual(KdbxErrorCode.UNKNOWN);
      expect(error.message).assertEqual('未知错误');
      expect(error.originalError).assertUndefined();
      expect(error.details).assertUndefined();
    });

    it('should create error with custom message', 0, () => {
      const message = '自定义错误消息';
      const error = new KdbxError(KdbxErrorCode.INVALID_ARGUMENT, message);

      expect(error.code).assertEqual(KdbxErrorCode.INVALID_ARGUMENT);
      expect(error.message).assertEqual(message);
    });

    it('should create error with original error', 0, () => {
      const originalError = new Error('原始错误');
      const error = new KdbxError(
        KdbxErrorCode.OPERATION_FAILED,
        '操作失败',
        originalError
      );

      expect(error.code).assertEqual(KdbxErrorCode.OPERATION_FAILED);
      expect(error.originalError).assertEqual(originalError);
    });

    it('should create error with details', 0, () => {
      const details = new Map<string, Object>([['field', 'password'], ['value', '****']]);
      const error = new KdbxError(
        KdbxErrorCode.INVALID_CREDENTIALS,
        '无效的凭证',
        undefined,
        details
      );

      expect(error.code).assertEqual(KdbxErrorCode.INVALID_CREDENTIALS);
      expect(error.details).assertEqual(details);
    });

    it('should get default message for each error code', 0, () => {
      // 测试所有错误代码的默认消息
      Object.values(KdbxErrorCode).forEach(code => {
        const error = new KdbxError(code);
        expect(error.message).not().assertUndefined();
        expect(error.message.length).assertLarger(0);
      });
    });

    it('should get suggestion for specific error codes', 0, () => {
      const testCases: KdbxErrorData[] = [
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

      testCases.forEach((item) => {
        const error = new KdbxError(item.code);
        expect(error.getSuggestion()).assertEqual(item.expectedSuggestion);
      });
    });

    it('should get full message with all information', 0, () => {
      const originalError = new Error('原始错误');
      const details = new Map<string,Object>([['field','password' ]]);
      const error = new KdbxError(
        KdbxErrorCode.INVALID_CREDENTIALS,
        '密码错误',
        originalError,
        details
      );

      const fullMessage = error.getFullMessage();

      expect(fullMessage).assertContain('密码错误');
      expect(fullMessage).assertContain('错误代码: INVALID_CREDENTIALS');
      expect(fullMessage).assertContain('原始错误: 原始错误');
      expect(fullMessage).assertContain('处理建议: ');
    });

    it('should create error using static create method', 0, () => {
      const details = new Map<string,Object>([[ 'algorithm', 'AES' ]]);
      const error = KdbxError.create(
        KdbxErrorCode.ENCRYPTION_FAILED,
        '加密失败',
        new Error('加密错误'),
        details
      );

      expect(error instanceof KdbxError).assertTrue();
      expect(error.code).assertEqual(KdbxErrorCode.ENCRYPTION_FAILED);
      expect(error.message).assertEqual('加密失败');
      expect(error.originalError).not().assertUndefined();
      expect(error.details).not().assertUndefined();
    });

    it('should wrap existing error', 0, () => {
      const originalError = new Error('网络连接失败');
      const wrappedError = KdbxError.wrap(
        originalError,
        KdbxErrorCode.NETWORK_ERROR,
        '同步失败',
        { url: 'https://example.com' }
      );

      expect(wrappedError instanceof KdbxError).assertTrue();
      expect(wrappedError.code).assertEqual(KdbxErrorCode.NETWORK_ERROR);
      expect(wrappedError.message).assertEqual('同步失败');
      expect(wrappedError.originalError).assertEqual(originalError);
      expect(wrappedError.details).not().assertUndefined();
    });

    it('should wrap error with default values', 0, () => {
      const originalError = new Error('测试错误');
      const wrappedError = KdbxError.wrap(originalError);

      expect(wrappedError instanceof KdbxError).assertTrue();
      expect(wrappedError.code).assertEqual(KdbxErrorCode.UNKNOWN);
      expect(wrappedError.message).assertEqual('测试错误');
      expect(wrappedError.originalError).assertEqual(originalError);
    });

    it('should handle error inheritance correctly', 0, () => {
      const error = new KdbxError(KdbxErrorCode.INVALID_ARGUMENT);

      // 验证错误继承链
      expect(error instanceof Error).assertEqual(true);
      expect(error instanceof KdbxError).assertEqual(true);
    });

    it('should handle stack trace', 0, () => {
      const error = new KdbxError(KdbxErrorCode.INVALID_ARGUMENT);

      expect(error.stack).not().assertUndefined();
      expect(error.stack?.includes('KdbxError')).assertEqual(true);
    });

    it('should handle error code validation', 0, () => {
      // 验证所有错误代码都是有效的字符串
      Object.values(KdbxErrorCode).forEach(code => {
        expect(typeof code).assertEqual('string');
        expect(code.length).assertLarger(0);
      });
    });

    it('should handle error code uniqueness', 0, () => {
      // 验证错误代码的唯一性
      const codes = Object.values(KdbxErrorCode);
      const uniqueCodes = new Set(codes);
      expect(uniqueCodes.size).assertEqual(codes.length);
    });

    it('should handle error grouping', 0, () => {
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
        expect(error.message).not().assertUndefined();
        expect(error.getSuggestion()).not().assertUndefined();
      });
    });
  });
}

