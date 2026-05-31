import { describe, expect, it } from '@ohos/hypium';
import { PCloudStorageConfig, PCloudPageConfig } from '../../../../../main/ets/storage/pcloud/PCloudConfig';
import { StorageType } from '../../../../../main/ets/storage/StorageType';

export default function PCloudConfigTest() {
  describe('PCloudConfigTest', () => {

    /**
     * 测试 PCloudStorageConfig 创建
     */
    describe('Creation', () => {
      it('should create config with default values', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        expect(config).not().assertUndefined();
        expect(config.expireAt).assertEqual(0);
        expect(config.timeout).assertEqual(30000);
      });

      it('should set and get timeout', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        config.timeout = 60000;
        expect(config.timeout).assertEqual(60000);
      });

      it('should set and get expireAt', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        const future: number = Date.now() + 3600000;
        config.expireAt = future;
        expect(config.expireAt).assertEqual(future);
      });
    });

    /**
     * 测试 accessToken 加密/解密
     */
    describe('AccessToken', () => {
      it('should encrypt and decrypt access token', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        const original: string = 'test-access-token-12345';
        config.accessToken = original;
        const retrieved: string = config.accessToken;
        expect(retrieved).assertEqual(original);
      });

      it('should return empty string for default token', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        expect(config.accessToken).assertEqual('');
      });
    });

    /**
     * 测试 isTokenExpired
     */
    describe('TokenExpiration', () => {
      it('should not be expired when expireAt is 0', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        expect(config.isTokenExpired()).assertFalse();
      });

      it('should be expired when expireAt is in the past', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        config.expireAt = Date.now() - 1000; // 1秒前已过期
        expect(config.isTokenExpired()).assertTrue();
      });

      it('should not be expired when expireAt is in the future', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        config.expireAt = Date.now() + 3600000; // 1小时后
        expect(config.isTokenExpired()).assertFalse();
      });

      it('should be expired exactly at expireAt boundary', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        const now: number = Date.now();
        config.expireAt = now;
        // expireAt == now is considered expired (>= check)
        expect(config.isTokenExpired()).assertTrue();
      });
    });

    /**
     * 测试 touchActive
     */
    describe('TouchActive', () => {
      it('should update lastActiveAt after touchActive', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        const before: number = config.lastActiveAt;
        // 等待短暂时间确保时间戳变化
        const start: number = Date.now();
        // touchActive 使用 Date.now()
        config.touchActive();
        const after: number = config.lastActiveAt;
        expect(after).assertLargerOrEqual(before);
      });

      it('should set and get lastActiveAt', 0, () => {
        const config: PCloudStorageConfig = new PCloudStorageConfig();
        const testTime: number = 1234567890;
        config.lastActiveAt = testTime;
        expect(config.lastActiveAt).assertEqual(testTime);
      });
    });

    /**
     * 测试 PCloudPageConfig 常量
     */
    describe('PageConfig', () => {
      it('should have correct title', 0, () => {
        expect(PCloudPageConfig.title).assertEqual('pCloud');
      });

      it('should have correct pageUrl', 0, () => {
        expect(PCloudPageConfig.pageUrl).assertEqual('storage/pcloud/PCloudPage');
      });

      it('should have correct storageType', 0, () => {
        expect(PCloudPageConfig.storageType).assertEqual(StorageType.PCLOUD);
      });

      it('should have icon resource', 0, () => {
        expect(PCloudPageConfig.icon).not().assertUndefined();
      });

      it('should have selectDesc resource', 0, () => {
        expect(PCloudPageConfig.selectDesc).not().assertUndefined();
      });

      it('should have saveDesc resource', 0, () => {
        expect(PCloudPageConfig.saveDesc).not().assertUndefined();
      });
    });
  });
}
