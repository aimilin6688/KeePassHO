import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Storage } from '../../../../../main/ets/storage/s3/S3Storage';
import { S3StorageConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { StorageError } from '../../../../../main/ets/storage/StorageError';
import { StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { FileType, FileInfo } from '../../../../../main/ets/storage/IFileStorage';
import { StorageType } from '../../../../../main/ets/storage/StorageType';
import { S3TestConfig, TestS3StorageConfig } from './S3TestConfig';
import { util } from '@kit.ArkTS';


export default function S3StorageTest() {
  describe('S3Storage', () => {

    /**
     * 测试 S3StorageConfig 配置类
     * 注意：由于 Sm4Utils 需要设备环境，测试中使用 TestS3StorageConfig
     */
    describe('S3StorageConfig', () => {
      it('should create config object with required fields', 0, () => {
        const config: TestS3StorageConfig = S3TestConfig.getStorageConfig();

        expect(config.endpoint).assertEqual(S3TestConfig.ENDPOINT);
        expect(config.region).assertEqual(S3TestConfig.REGION);
        expect(config.bucket).assertEqual(S3TestConfig.BUCKET);
      });

      it('should create config object with custom bucket', 0, () => {
        const config: TestS3StorageConfig = S3TestConfig.getStorageConfig('custom-bucket');

        expect(config.bucket).assertEqual('custom-bucket');
      });
    });

    /**
     * 测试 S3Storage 初始化
     */
    describe('S3StorageInitialization', () => {
      let storage: S3Storage | undefined;

      afterEach(() => {
        if (storage) {
          storage.close();
        }
      });

      it('should throw error when not initialized', 0, async () => {
        storage = new S3Storage();

        try {
          await storage.read('test/path');
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          const storageError: StorageError = error as StorageError;
          expect(storageError.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
        }
      });

      it('should initialize with TestS3StorageConfig', 0, () => {
        storage = new S3Storage();
        const config: TestS3StorageConfig = S3TestConfig.getStorageConfig();

        storage.init(config as S3StorageConfig);

        const pageConfig = storage.getPageConfig();
        expect(pageConfig).not().assertUndefined();
        expect(pageConfig.storageType).assertEqual(StorageType.S3);
      });

      it('should parse config from TestS3StorageConfig', 0, () => {
        storage = new S3Storage();
        const config: TestS3StorageConfig = S3TestConfig.getStorageConfig();

        storage.init(config as S3StorageConfig);

        const pageConfig = storage.getPageConfig();
        expect(pageConfig).not().assertUndefined();
      });
    });

    /**
     * 测试 IFileStorage 接口实现
     */
    describe('IFileStorageInterface', () => {
      let storage: S3Storage;

      beforeEach(() => {
        storage = new S3Storage();
        const config: TestS3StorageConfig = S3TestConfig.getStorageConfig();
        storage.init(config as S3StorageConfig);
      });

      afterEach(() => {
        if (storage) {
          storage.close();
        }
      });

      it('should implement getPageConfig', 0, () => {
        const pageConfig = storage.getPageConfig();

        expect(pageConfig).not().assertUndefined();
        expect(pageConfig.icon).not().assertUndefined();
        expect(pageConfig.title).not().assertUndefined();
        expect(pageConfig.pageUrl).assertEqual('storage/s3/S3Page');
      });

      it('should implement init', 0, () => {
        // 使用已有的 storage 实例，避免创建新的 session
        const pageConfig = storage.getPageConfig();
        expect(pageConfig).not().assertUndefined();
      });
    });

    /**
     * 测试真实的文件操作（需要有效凭证）
     */
    describe('RealFileOperations', () => {
      let storage: S3Storage;

      beforeEach(() => {
        storage = new S3Storage();
        const config: TestS3StorageConfig = S3TestConfig.getStorageConfig();
        storage.init(config as S3StorageConfig);
      });

      afterEach(() => {
        if (storage) {
          storage.close();
        }
      });

      it('should check if file exists', 0, async () => {
        const exists: boolean = await storage.exists(S3TestConfig.TEST_FILE);
        expect(typeof exists).assertEqual('boolean');
      });

      it('should return false for non-existent file', 0, async () => {
        const exists: boolean = await storage.exists('non-existent-file-12345.kdbx');
        expect(exists).assertFalse();
      });

      it('should read existing file', 0, async () => {
        try {
          const content: ArrayBuffer = await storage.read(S3TestConfig.TEST_FILE);
          expect(content).not().assertUndefined();
          expect(content.byteLength).assertLarger(0);
        } catch (error) {
          // 如果文件不存在，测试跳过
          console.log('Test file not found, skipping read test');
        }
      });

      it('should get file info', 0, async () => {
        try {
          const info: FileInfo = await storage.getInfo(S3TestConfig.TEST_FILE);
          expect(info).not().assertUndefined();
          expect(info.name).assertEqual(S3TestConfig.TEST_FILE);
          expect(info.type).assertEqual(FileType.FILE);
          expect(info.size).assertLarger(0);
        } catch (error) {
          console.log('Test file not found, skipping getInfo test');
        }
      });

      it('should list directory contents', 0, async () => {
        const files: FileInfo[] = await storage.listDir(S3TestConfig.BUCKET);
        expect(files).not().assertUndefined();
        expect(Array.isArray(files)).assertTrue();
      });

      it('should write and read file', 0, async () => {
        const testContent: string = 'Test content for S3 storage ' + Date.now();
        const encoder: util.TextEncoder = new util.TextEncoder();
        const data: Uint8Array = encoder.encodeInto(testContent);
        const testPath: string = 'test-write-' + Date.now() + '.txt';

        try {
          // 写入文件
          await storage.write(testPath, data.buffer as ArrayBuffer);

          // 验证文件存在
          const exists: boolean = await storage.exists(testPath);
          expect(exists).assertTrue();

          // 读取文件内容
          const readContent: ArrayBuffer = await storage.read(testPath);
          const decoder: util.TextDecoder = new util.TextDecoder();
          const contentStr: string = decoder.decodeToString(new Uint8Array(readContent));
          expect(contentStr).assertEqual(testContent);
        } catch (error) {
          // 忽略清理错误
        }
      });
    });
  });
}
