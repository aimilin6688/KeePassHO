import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { HuaweiDriveStorage } from '../../../../../main/ets/storage/huawei/HuaweiDriveStorage';
import { HuaweiDriveStorageConfig } from '../../../../../main/ets/storage/huawei/HuaweiDriveConfig';
import { StorageError } from '../../../../../main/ets/storage/StorageError';
import { StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { FileType, FileInfo } from '../../../../../main/ets/storage/IFileStorage';
import { StorageType } from '../../../../../main/ets/storage/StorageType';
import { HuaweiDriveTestConfig, TestHuaweiDriveStorageConfig, TestConfigOptions } from './HuaweiDriveTestConfig';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDriveStorageTest';

export default function HuaweiDriveStorageTest() {
  describe('HuaweiDriveStorageTest', () => {

    /**
     * 测试 HuaweiDriveStorageConfig 配置类
     * 注意：由于 Sm4Utils 需要设备环境，测试中使用 TestHuaweiDriveStorageConfig
     */
    describe('HuaweiDriveStorageConfig', () => {
      it('should create config object with required fields', 0, () => {
        const config: TestHuaweiDriveStorageConfig = HuaweiDriveTestConfig.getStorageConfig();

        expect(config.accessToken).assertEqual(HuaweiDriveTestConfig.ACCESS_TOKEN);
        expect(config.refreshToken).assertEqual(HuaweiDriveTestConfig.REFRESH_TOKEN);
        expect(config.scope).assertEqual(HuaweiDriveTestConfig.SCOPE_FULL);
      });

      it('should check token expiration correctly', 0, () => {
        // 未过期的配置
        const validConfig = new TestHuaweiDriveStorageConfig(
          'token',
          'refresh',
          Date.now() + 3600000 // 1小时后过期
        );
        expect(validConfig.isTokenExpired()).assertFalse();

        // 已过期的配置
        const expiredConfig = new TestHuaweiDriveStorageConfig(
          'token',
          'refresh',
          Date.now() - 1000 // 已过期
        );
        expect(expiredConfig.isTokenExpired()).assertTrue();
      });

      it('should create config with custom scope', 0, () => {
        const options = new TestConfigOptions();
        options.scope = HuaweiDriveTestConfig.SCOPE_APP_FILE;
        const config = new TestHuaweiDriveStorageConfig(
          'token',
          'refresh',
          Date.now() + 3600000,
          options
        );

        expect(config.scope).assertEqual(HuaweiDriveTestConfig.SCOPE_APP_FILE);
      });

    });

    /**
     * 测试 HuaweiDriveScope 枚举
     */
    describe('HuaweiDriveScopeTest', () => {

      it('should have correct full access scope', 0, () => {
        expect(HuaweiDriveTestConfig.SCOPE_FULL).assertEqual('https://www.huawei.com/auth/drive');
      });

      it('should have correct app file scope', 0, () => {
        expect(HuaweiDriveTestConfig.SCOPE_APP_FILE).assertEqual('https://www.huawei.com/auth/drive.file');
      });

    });

    /**
     * 测试 HuaweiDriveStorage 初始化
     */
    describe('HuaweiDriveStorageInitialization', () => {
      let storage: HuaweiDriveStorage | undefined;

      afterEach(() => {
        if (storage) {
          storage = undefined;
        }
      });

      it('should throw error when not initialized', 0, async () => {
        storage = new HuaweiDriveStorage();

        try {
          await storage.read('test-file-id');
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          const storageError: StorageError = error as StorageError;
          expect(storageError.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
        }
      });

      it('should initialize with TestHuaweiDriveStorageConfig', 0, () => {
        storage = new HuaweiDriveStorage();
        const config: TestHuaweiDriveStorageConfig = HuaweiDriveTestConfig.getStorageConfig();

        storage.init(config as HuaweiDriveStorageConfig);

        const pageConfig = storage.getPageConfig();
        expect(pageConfig).not().assertUndefined();
        expect(pageConfig.storageType).assertEqual(StorageType.HUAWEI_DRIVE);
      });

      it('should parse config from TestHuaweiDriveStorageConfig', 0, () => {
        storage = new HuaweiDriveStorage();
        const config: TestHuaweiDriveStorageConfig = HuaweiDriveTestConfig.getStorageConfig();

        storage.init(config as HuaweiDriveStorageConfig);

        const pageConfig = storage.getPageConfig();
        expect(pageConfig).not().assertUndefined();
      });
    });

    /**
     * 测试 IFileStorage 接口实现
     */
    describe('IFileStorageInterface', () => {
      let storage: HuaweiDriveStorage | undefined;

      beforeEach(() => {
        storage = new HuaweiDriveStorage();
        const config: TestHuaweiDriveStorageConfig = HuaweiDriveTestConfig.getStorageConfig();
        storage.init(config as HuaweiDriveStorageConfig);
      });

      afterEach(() => {
        storage = undefined;
      });

      it('should implement getPageConfig', 0, () => {
        if (!storage) {
          expect(false).assertTrue();
          return;
        }
        const pageConfig = storage.getPageConfig();

        expect(pageConfig).not().assertUndefined();
        expect(pageConfig.icon).not().assertUndefined();
        expect(pageConfig.title).not().assertUndefined();
        expect(pageConfig.pageUrl).assertEqual('storage/huawei/HuaweiDrivePage');
      });

      it('should implement init', 0, () => {
        // 使用已有的 storage 实例，避免创建新的 session
        if (!storage) {
          expect(false).assertTrue();
          return;
        }
        const pageConfig = storage.getPageConfig();
        expect(pageConfig).not().assertUndefined();
      });

      it('should return correct storage type', 0, () => {
        if (!storage) {
          expect(false).assertTrue();
          return;
        }
        const pageConfig = storage.getPageConfig();
        expect(pageConfig.storageType).assertEqual(StorageType.HUAWEI_DRIVE);
      });
    });

    /**
     * 测试配置管理
     */
    describe('ConfigManagement', () => {
      let storage: HuaweiDriveStorage | undefined;

      beforeEach(() => {
        storage = new HuaweiDriveStorage();
      });

      afterEach(() => {
        storage = undefined;
      });

      it('should update config correctly', 0, () => {
        if (!storage) {
          expect(false).assertTrue();
          return;
        }
        const config1: TestHuaweiDriveStorageConfig = HuaweiDriveTestConfig.getStorageConfig();
        storage.init(config1 as HuaweiDriveStorageConfig);

        const options = new TestConfigOptions();
        options.scope = HuaweiDriveTestConfig.SCOPE_APP_FILE;
        const newConfig = new TestHuaweiDriveStorageConfig(
          'new_token',
          'new_refresh',
          Date.now() + 7200000,
          options
        );

        storage.updateConfig(newConfig as HuaweiDriveStorageConfig);

        const currentConfig = storage.getConfig();
        expect(currentConfig).not().assertUndefined();
        expect(currentConfig?.getAccessTokenText()).assertEqual('new_token');
      });

      it('should get current config', 0, () => {
        if (!storage) {
          expect(false).assertTrue();
          return;
        }
        const config: TestHuaweiDriveStorageConfig = HuaweiDriveTestConfig.getStorageConfig();
        storage.init(config as HuaweiDriveStorageConfig);

        const currentConfig = storage.getConfig();
        expect(currentConfig).not().assertUndefined();
      });
    });
  });
}
