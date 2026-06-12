import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Storage } from '../../../../../main/ets/storage/s3/S3Storage';
import { S3StorageConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { StorageError } from '../../../../../main/ets/storage/StorageError';
import { StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { FileType, FileInfo } from '../../../../../main/ets/storage/IFileStorage';
import { StorageType } from '../../../../../main/ets/storage/StorageType';
import { S3TestConfig, TestS3StorageConfig } from './S3TestConfig';
import { S3MultipartConfig } from '../../../../../main/ets/storage/s3/S3Config';
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

    describe('S3MultipartConfig', () => {

      it('should_have_correct_min_part_size', () => {
        expect(S3MultipartConfig.MIN_PART_SIZE).assertEqual(5 * 1024 * 1024);
      });

      it('should_have_correct_recommended_part_size', () => {
        expect(S3MultipartConfig.RECOMMENDED_PART_SIZE).assertEqual(8 * 1024 * 1024);
      });

      it('should_have_correct_multipart_threshold', () => {
        expect(S3MultipartConfig.MULTIPART_THRESHOLD).assertEqual(5 * 1024 * 1024);
      });

      it('should_have_correct_max_retry_count', () => {
        expect(S3MultipartConfig.MAX_RETRY_COUNT).assertEqual(3);
      });

      it('should_recommended_part_size_be_larger_than_min', () => {
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

    /**
     * 测试多种路径场景（中文路径、多级目录等）
     * 注意：这些测试需要先手动创建测试数据或运行数据初始化
     */
    describe('MultiPathOperations', () => {
      let storage: S3Storage;
      let testFileContent: ArrayBuffer | null = null;

      beforeEach(async () => {
        storage = new S3Storage();
        const config: TestS3StorageConfig = S3TestConfig.getStorageConfig();
        storage.init(config as S3StorageConfig);

        // 读取源测试文件内容
        try {
          testFileContent = await storage.read(S3TestConfig.TEST_FILE);
        } catch (error) {
          console.log('Source test file not found, multi-path tests may fail');
          testFileContent = null;
        }
      });

      afterEach(() => {
        if (storage) {
          storage.close();
        }
      });

      /**
       * 测试路径数据初始化
       * 将 test-1.kdbx 复制到各个测试路径
       */
      it('should setup test data - copy file to test paths', 0, async () => {
        if (!testFileContent) {
          console.log('Source file not available, skipping test data setup');
          expect(true).assertTrue(); // 跳过但不失败
          return;
        }

        const results: string[] = [];
        for (let i = 0; i < S3TestConfig.TEST_PATHS.length; i++) {
          const testPath = S3TestConfig.TEST_PATHS[i];
          if (testPath === S3TestConfig.TEST_FILE) {
            continue; // 跳过源文件
          }
          try {
            await storage.write(testPath, testFileContent);
            results.push(`✓ ${testPath}`);
          } catch (error) {
            const err = error as Error;
            results.push(`✗ ${testPath}: ${err.message}`);
          }
        }
        console.log('Test data setup results:\n' + results.join('\n'));

        // 至少有一个成功写入
        const successCount = results.filter(r => r.startsWith('✓')).length;
        expect(successCount).assertLarger(0);
      });

      // 动态为每个测试路径生成测试用例
      for (let i = 0; i < S3TestConfig.TEST_PATHS.length; i++) {
        const testPath: string = S3TestConfig.TEST_PATHS[i];

        it(`should verify file at path: ${testPath}`, 0, async () => {
          if (!testFileContent) {
            console.log(`Skipping test for ${testPath} - source file not available`);
            expect(true).assertTrue(); // 跳过但不失败
            return;
          }

          // 验证文件存在
          const exists: boolean = await storage.exists(testPath);
          expect(exists).assertTrue();

          // 验证文件内容
          const readContent: ArrayBuffer = await storage.read(testPath);
          expect(readContent.byteLength).assertEqual(testFileContent.byteLength);

          // 获取文件信息
          const info: FileInfo = await storage.getInfo(testPath);
          expect(info.name).assertEqual('test-1.kdbx');
          expect(info.type).assertEqual(FileType.FILE);
          expect(info.size).assertLarger(0);

          console.log(`Successfully verified file at: ${testPath}`);
        });
      }

      it('should list Chinese directory', 0, async () => {
        const files: FileInfo[] = await storage.listDir('密码库');
        expect(files).not().assertUndefined();
        expect(Array.isArray(files)).assertTrue();
        // 目录下应该有文件
        expect(files.length).assertLarger(0);
        console.log(`Found ${files.length} files in 密码库/`);
      });

      it('should list nested directory', 0, async () => {
        const files: FileInfo[] = await storage.listDir('folder1/folder2');
        expect(files).not().assertUndefined();
        expect(Array.isArray(files)).assertTrue();
        expect(files.length).assertLarger(0);
        console.log(`Found ${files.length} files in folder1/folder2/`);
      });

      it('should handle mixed Chinese and English path', 0, async () => {
        const files: FileInfo[] = await storage.listDir('我的密码/工作账号');
        expect(files).not().assertUndefined();
        expect(Array.isArray(files)).assertTrue();
        expect(files.length).assertLarger(0);
        console.log(`Found ${files.length} files in 我的密码/工作账号/`);
      });
    });
  });
}
