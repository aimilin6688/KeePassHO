import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Storage } from '../../../../../main/ets/storage/s3/S3Storage';
import { S3Client } from '../../../../../main/ets/storage/s3/S3Client';
import { S3StorageConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { StorageError } from '../../../../../main/ets/storage/StorageError';
import { StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { FileType, FileInfo } from '../../../../../main/ets/storage/IFileStorage';
import { StorageType } from '../../../../../main/ets/storage/StorageType';
import { S3TestConfig, TestS3StorageConfig } from './S3TestConfig';
import { S3MultipartConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { TestFixtures } from '../TestFixtures';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'S3StorageTest';

export default function S3StorageTest() {
  describe('S3StorageTest', () => {

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

    describe('S3MultipartConfigTest', () => {

      it('should_have_correct_min_part_size', 0, () => {
        expect(S3MultipartConfig.MIN_PART_SIZE).assertEqual(5 * 1024 * 1024);
      });

      it('should_have_correct_recommended_part_size', 0, () => {
        expect(S3MultipartConfig.RECOMMENDED_PART_SIZE).assertEqual(8 * 1024 * 1024);
      });

      it('should_have_correct_multipart_threshold', 0, () => {
        expect(S3MultipartConfig.MULTIPART_THRESHOLD).assertEqual(5 * 1024 * 1024);
      });

      it('should_have_correct_max_retry_count', 0, () => {
        expect(S3MultipartConfig.MAX_RETRY_COUNT).assertEqual(3);
      });

      it('should_recommended_part_size_be_larger_than_min', 0, () => {
        expect(S3MultipartConfig.RECOMMENDED_PART_SIZE)
          .assertLarger(S3MultipartConfig.MIN_PART_SIZE);
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
     * 测试真实的文件操作（自建 SeaweedFS，真实 KDBX 数据，无 mock）
     */
    describe('RealFileOperations', () => {
      let storage: S3Storage;
      let fixture: ArrayBuffer;

      beforeAll(async () => {
        // 上传 rawfile 中的真实 KDBX 数据库文件到测试桶
        fixture = await TestFixtures.loadUnitTestKdbx();
        const setupClient = new S3Client(S3TestConfig.getClientOptions());
        try {
          const putResult = await setupClient.putObject(S3TestConfig.BUCKET, S3TestConfig.TEST_FILE, fixture);
          if (!putResult.success) {
            throw new Error(`upload test fixture failed: statusCode=${putResult.statusCode}, message=${putResult.message}`);
          }
          hilog.info(DOMAIN, TAG, 'RealFileOperations setup done, fixture size=%{public}d', fixture.byteLength);
        } finally {
          setupClient.close();
        }
      });

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

      it('should return true for uploaded test file', 0, async () => {
        const exists: boolean = await storage.exists(S3TestConfig.TEST_FILE);
        expect(exists).assertTrue();
      });

      it('should return false for non-existent file', 0, async () => {
        const exists: boolean = await storage.exists('non-existent-file-12345.kdbx');
        expect(exists).assertFalse();
      });

      it('should read existing file with real kdbx content', 0, async () => {
        const content: ArrayBuffer = await storage.read(S3TestConfig.TEST_FILE);
        expect(content).not().assertUndefined();
        // 内容必须与上传的真实 KDBX 夹具一致
        expect(content.byteLength).assertEqual(fixture.byteLength);
        expect(TestFixtures.assertKdbxMagic(content)).assertTrue();
      });

      it('should get file info with exact fixture size', 0, async () => {
        const info: FileInfo = await storage.getInfo(S3TestConfig.TEST_FILE);
        expect(info).not().assertUndefined();
        expect(info.name).assertEqual(S3TestConfig.TEST_FILE);
        expect(info.type).assertEqual(FileType.FILE);
        expect(info.size).assertEqual(fixture.byteLength);
      });

      it('should list directory contents', 0, async () => {
        const files: FileInfo[] = await storage.listDir(S3TestConfig.BUCKET);
        expect(files).not().assertUndefined();
        expect(Array.isArray(files)).assertTrue();
        // 测试桶中至少存在夹具文件
        expect(files.length).assertLarger(0);
      });

      it('should write and read back real kdbx file', 0, async () => {
        const testPath: string = 'test-write-' + Date.now() + '.kdbx';

        // 写入真实 KDBX 内容
        await storage.write(testPath, fixture);

        // 验证文件存在
        const exists: boolean = await storage.exists(testPath);
        expect(exists).assertTrue();

        // 读取并验证内容完全一致
        const readContent: ArrayBuffer = await storage.read(testPath);
        expect(readContent.byteLength).assertEqual(fixture.byteLength);
        expect(TestFixtures.assertKdbxMagic(readContent)).assertTrue();
      });
    });

    /**
     * 测试多种路径场景（中文路径、多级目录等）
     * setup 用例先把真实 KDBX 夹具复制到各测试路径，后续用例逐一验证
     */
    describe('MultiPathOperations', () => {
      let storage: S3Storage;
      let testFileContent: ArrayBuffer;

      beforeAll(async () => {
        testFileContent = await TestFixtures.loadUnitTestKdbx();
      });

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

      /**
       * 测试路径数据初始化
       * 将真实 KDBX 夹具复制到各个测试路径（必须全部成功）
       */
      it('should setup test data - copy real kdbx to all test paths', 0, async () => {
        let successCount: number = 0;
        for (let i = 0; i < S3TestConfig.TEST_PATHS.length; i++) {
          const testPath = S3TestConfig.TEST_PATHS[i];
          if (testPath === S3TestConfig.TEST_FILE) {
            continue; // 跳过源文件路径
          }
          await storage.write(testPath, testFileContent);
          successCount++;
        }
        // 除源路径外全部写入成功
        expect(successCount).assertEqual(S3TestConfig.TEST_PATHS.length - 1);
      });

      // 动态为每个测试路径生成测试用例
      for (let i = 0; i < S3TestConfig.TEST_PATHS.length; i++) {
        const testPath: string = S3TestConfig.TEST_PATHS[i];

        it(`should verify file at path: ${testPath}`, 0, async () => {
          // 验证文件存在
          const exists: boolean = await storage.exists(testPath);
          expect(exists).assertTrue();

          // 验证文件内容与夹具一致
          const readContent: ArrayBuffer = await storage.read(testPath);
          expect(readContent.byteLength).assertEqual(testFileContent.byteLength);
          expect(TestFixtures.assertKdbxMagic(readContent)).assertTrue();

          // 获取文件信息
          const info: FileInfo = await storage.getInfo(testPath);
          expect(info.name).assertEqual('test-1.kdbx');
          expect(info.type).assertEqual(FileType.FILE);
          expect(info.size).assertEqual(testFileContent.byteLength);
        });
      }

      it('should list Chinese directory', 0, async () => {
        const files: FileInfo[] = await storage.listDir('密码库');
        expect(files).not().assertUndefined();
        expect(Array.isArray(files)).assertTrue();
        // 目录下应该有夹具文件
        expect(files.length).assertLarger(0);
        hilog.info(DOMAIN, TAG, 'Found %{public}d files in 密码库/', files.length);
      });

      it('should list nested directory', 0, async () => {
        const files: FileInfo[] = await storage.listDir('folder1/folder2');
        expect(files).not().assertUndefined();
        expect(Array.isArray(files)).assertTrue();
        expect(files.length).assertLarger(0);
        hilog.info(DOMAIN, TAG, 'Found %{public}d files in folder1/folder2/', files.length);
      });

      it('should handle mixed Chinese and English path', 0, async () => {
        const files: FileInfo[] = await storage.listDir('我的密码/工作账号');
        expect(files).not().assertUndefined();
        expect(Array.isArray(files)).assertTrue();
        expect(files.length).assertLarger(0);
        hilog.info(DOMAIN, TAG, 'Found %{public}d files in 我的密码/工作账号/', files.length);
      });
    });
  });
}
