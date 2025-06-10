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
import { Argon2, Argon2Variant, Argon2Params } from '../../../../../main/ets/kdbx/crypto/Argon2';
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

export default function Argon2UnitTest() {
  describe('Argon2', () => {
    // 测试向量来自 Argon2 参考实现
    const TEST_PASSWORD = KdbxUtils.strToBytes('password');
    const TEST_SALT = KdbxUtils.strToBytes('somesalt');
    const TEST_SECRET = new Uint8Array(0);
    const TEST_AD = new Uint8Array(0);

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

    // 基本功能测试
    it('should derive key with default parameters', 0, async () => {
      const params: Argon2Params = {
        variant: Argon2Variant.Argon2d,  // 对应 type: 0
        iterations: 3,
        memory: 32,
        parallelism: 4,
        salt: TEST_SALT,
        outputLength: 32
      };
      
      const result = await new Argon2().deriveKey(params, TEST_PASSWORD);

      expect(result.length).assertEqual(32);
    });

    // 参数验证测试
    it('should throw error for invalid iterations', 0, async () => {
      try {
        const params: Argon2Params = {
          variant: Argon2Variant.Argon2d,
          iterations: 0,  // 无效的迭代次数
          memory: 32,
          parallelism: 4,
          salt: TEST_SALT,
          outputLength: 32
        };
        
        await new Argon2().deriveKey(params, TEST_PASSWORD);
        expect(false).assertTrue();  // 如果没有抛出错误，测试应该失败
      } catch (error) {
        expect(error.message).assertContain('Invalid iterations');
      }
    });

    it('should throw error for invalid memory', 0, async () => {
      try {
        const params: Argon2Params = {
          variant: Argon2Variant.Argon2d,
          iterations: 3,
          memory: 7,  // 无效的内存参数（小于8）
          parallelism: 4,
          salt: TEST_SALT,
          outputLength: 32
        };
        
        await new Argon2().deriveKey(params, TEST_PASSWORD);
        expect(false).assertTrue();  // 如果没有抛出错误，测试应该失败
      } catch (error) {
        expect(error.message).assertContain('Invalid memory');
      }
    });

    it('should throw error for invalid parallelism', 0, async () => {
      try {
        const params: Argon2Params = {
          variant: Argon2Variant.Argon2d,
          iterations: 3,
          memory: 32,
          parallelism: 0,  // 无效的并行度
          salt: TEST_SALT,
          outputLength: 32
        };
        
        await new Argon2().deriveKey(params, TEST_PASSWORD);
        expect(false).assertTrue();  // 如果没有抛出错误，测试应该失败
      } catch (error) {
        expect(error.message).assertContain('Invalid parallelism');
      }
    });

    // 测试不同的输出长度
    it('should handle different output lengths', 0, async () => {
      const lengths = [16, 32, 64];
      for (const length of lengths) {
        const params: Argon2Params = {
          variant: Argon2Variant.Argon2d,
          iterations: 3,
          memory: 32,
          parallelism: 4,
          salt: TEST_SALT,
          outputLength: length
        };
        
        const result = await new Argon2().deriveKey(params, TEST_PASSWORD);
        expect(result.length).assertEqual(length);
      }
    });

    // 测试不同的Argon2变体
    it('should support different Argon2 variants', 0, async () => {
      const variants:Argon2Variant[] = [Argon2Variant.Argon2d,  Argon2Variant.Argon2id];
      for (const variant of variants) {
        const params: Argon2Params = {
          variant: variant,
          iterations: 3,
          memory: 32,
          parallelism: 4,
          salt: TEST_SALT,
          outputLength: 32
        };
        
        const result = await new Argon2().deriveKey(params, TEST_PASSWORD);
        expect(result.length).assertEqual(32);
      }
    });

    // 测试空密码和最小盐值
    it('should handle empty password and minimum salt', 0, async () => {
      const emptyPassword = new Uint8Array(0);
      const minSalt = new Uint8Array(8); // 最小8字节的盐值

      const params: Argon2Params = {
        variant: Argon2Variant.Argon2d,
        iterations: 3,
        memory: 32,
        parallelism: 4,
        salt: minSalt,
        outputLength: 32
      };

      const result = await new Argon2().deriveKey(params, emptyPassword);
      expect(result.length).assertEqual(32);
    });

    // 性能测试
    it('should complete within reasonable time', 0, async () => {
      const startTime = new Date().getTime();

      const params: Argon2Params = {
        variant: Argon2Variant.Argon2d,
        iterations: 3,
        memory: 32,
        parallelism: 4,
        salt: TEST_SALT,
        outputLength: 32
      };

      await new Argon2().deriveKey(params, TEST_PASSWORD);

      const endTime = new Date().getTime();
      const duration = endTime - startTime;

      // 确保执行时间在合理范围内（这里设置为5秒）
      expect(duration).assertLess(5000);
    });

    // 测试结果一致性
    it('should produce consistent results', 0, async () => {
      const params: Argon2Params = {
        variant: Argon2Variant.Argon2d,
        iterations: 3,
        memory: 32,
        parallelism: 4,
        salt: TEST_SALT,
        outputLength: 32
      };

      const argon2 = new Argon2();
      const result1 = await argon2.deriveKey(params, TEST_PASSWORD);
      const result2 = await argon2.deriveKey(params, TEST_PASSWORD);

      expect(bytesToHex(result1)).assertEqual(bytesToHex(result2));
    });

    // 测试参数边界
    it('should handle minimum valid parameters', 0, async () => {
      const params: Argon2Params = {
        variant: Argon2Variant.Argon2d,
        iterations: 1,  // 最小迭代次数
        memory: 8,     // 最小内存
        parallelism: 1, // 最小并行度
        salt: TEST_SALT,
        outputLength: 32
      };

      const result = await new Argon2().deriveKey(params, TEST_PASSWORD);
      expect(result.length).assertEqual(32);
    });

    // 测试大内存参数
    it('should handle larger memory parameters', 0, async () => {
      const params: Argon2Params = {
        variant: Argon2Variant.Argon2d,
        iterations: 1,
        memory: 1024,  // 1GB内存
        parallelism: 4,
        salt: TEST_SALT,
        outputLength: 32
      };

      const result = await new Argon2().deriveKey(params, TEST_PASSWORD);
      expect(result.length).assertEqual(32);
    });

    // 测试高并行度
    it('should handle high parallelism', 0, async () => {
      const params: Argon2Params = {
        variant: Argon2Variant.Argon2d,
        iterations: 1,
        memory: 32,
        parallelism: 8,  // 高并行度
        salt: TEST_SALT,
        outputLength: 32
      };

      const result = await new Argon2().deriveKey(params, TEST_PASSWORD);
      expect(result.length).assertEqual(32);
    });

    // 测试额外数据参数
    it('should handle additional data', 0, async () => {
      const key = new Uint8Array([1, 2, 3, 4]);
      const associatedData = new Uint8Array([5, 6, 7, 8]);

      const params: Argon2Params = {
        variant: Argon2Variant.Argon2d,
        iterations: 3,
        memory: 32,
        parallelism: 4,
        salt: TEST_SALT,
        key: key,
        associatedData: associatedData,
        outputLength: 32
      };

      const result = await new Argon2().deriveKey(params, TEST_PASSWORD);
      expect(result.length).assertEqual(32);
    });
  });
}
