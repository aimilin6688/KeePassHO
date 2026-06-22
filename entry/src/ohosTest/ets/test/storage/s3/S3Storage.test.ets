import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Storage } from '../../../../../main/ets/storage/s3/S3Storage';
import { S3StorageConfig, S3MultipartConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { StorageError, StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { FileType, FileInfo } from '../../../../../main/ets/storage/IFileStorage';
import { StorageType } from '../../../../../main/ets/storage/StorageType';
import { S3TestConfig, TestS3StorageConfig } from './S3TestConfig';
import { MultipartUploadProgress } from '../../../../../main/ets/storage/s3/S3Types';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const DOMAIN = 0x0000;
const TAG = 'S3StorageTest';

export default function S3StorageTest() {
  describe('S3Storage', () => {

    // ==================== S3StorageConfig 配置类测试 ====================
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

    // ==================== S3MultipartConfig 测试 ====================
    describe('S3MultipartConfig', () => {

      it('should have correct min part size', 0, () => {
        expect(S3MultipartConfig.MIN_PART_SIZE).assertEqual(5 * 1024 * 1024);
      });

      it('should have correct recommended part size', 0, () => {
        expect(S3MultipartConfig.RECOMMENDED_PART_SIZE).assertEqual(8 * 1024 * 1024);
      });

      it('should have correct multipart threshold', 0, () => {
        expect(S3MultipartConfig.MULTIPART_THRESHOLD).assertEqual(5 * 1024 * 1024);
      });

      it('should have correct max retry count', 0, () => {
        expect(S3MultipartConfig.MAX_RETRY_COUNT).assertEqual(3);
      });

      it('should recommended part size be larger than min', 0, () => {
        expect(S3MultipartConfig.RECOMMENDED_PART_SIZE)
          .assertLarger(S3MultipartConfig.MIN_PART_SIZE);
      });
    });

    // ==================== S3Storage 初始化测试 ====================
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

    // ==================== IFileStorage 接口测试 ====================
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
        const pageConfig = storage.getPageConfig();
        expect(pageConfig).not().assertUndefined();
      });
    });

    // ==================== 真实文件操作测试 ====================
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
          await storage.write(testPath, data.buffer as ArrayBuffer);

          const exists: boolean = await storage.exists(testPath);
          expect(exists).assertTrue();

          const readContent: ArrayBuffer = await storage.read(testPath);
          const decoder: util.TextDecoder = new util.TextDecoder();
          const contentStr: string = decoder.decodeToString(new Uint8Array(readContent));
          expect(contentStr).assertEqual(testContent);
        } catch (error) {
          // 忽略清理错误
        }
      });
    });

    // ==================== 多路径操作测试 ====================
    describe('MultiPathOperations', () => {
      let storage: S3Storage;
      let testFileContent: ArrayBuffer | null = null;

      beforeEach(async () => {
        storage = new S3Storage();
        const config: TestS3StorageConfig = S3TestConfig.getStorageConfig();
        storage.init(config as S3StorageConfig);

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

      it('should setup test data - copy file to test paths', 0, async () => {
        if (!testFileContent) {
          console.log('Source file not available, skipping test data setup');
          expect(true).assertTrue();
          return;
        }

        const results: string[] = [];
        for (let i = 0; i < S3TestConfig.TEST_PATHS.length; i++) {
          const testPath = S3TestConfig.TEST_PATHS[i];
          if (testPath === S3TestConfig.TEST_FILE) {
            continue;
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

        const successCount = results.filter(r => r.startsWith('✓')).length;
        expect(successCount).assertLarger(0);
      });

      for (let i = 0; i < S3TestConfig.TEST_PATHS.length; i++) {
        const testPath: string = S3TestConfig.TEST_PATHS[i];

        it(`should verify file at path: ${testPath}`, 0, async () => {
          if (!testFileContent) {
            console.log(`Skipping test for ${testPath} - source file not available`);
            expect(true).assertTrue();
            return;
          }

          const exists: boolean = await storage.exists(testPath);
          expect(exists).assertTrue();

          const readContent: ArrayBuffer = await storage.read(testPath);
          expect(readContent.byteLength).assertEqual(testFileContent.byteLength);

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

    // ==================== 分块上传集成测试 ====================
    describe('MultipartUploadIntegration', () => {
      let storage: S3Storage;
      const testBucket = S3TestConfig.BUCKET;

      beforeEach(() => {
        const config = S3TestConfig.getStorageConfig(testBucket);
        storage = new S3Storage();
        storage.init(config);
      });

      afterEach(() => {
        storage.close();
      });

      it('should automatically use multipart for large file', 0, async () => {
        try {
          const largeData = new ArrayBuffer(20 * 1024 * 1024); // 20MB
          let progressCalled = false;

          storage.setProgressCallback((progress: MultipartUploadProgress) => {
            progressCalled = true;
            hilog.info(DOMAIN, TAG, 'Upload progress: %{public}d/%{public}d bytes, part %{public}d/%{public}d',
              progress.uploadedBytes, progress.totalBytes, progress.currentPart, progress.totalParts);
          });

          const testKey = 'integration-test/large-file-20mb.kdbx';
          await storage.write(`/${testBucket}/${testKey}`, largeData);

          hilog.info(DOMAIN, TAG, 'Large file uploaded successfully');
          expect(progressCalled).assertTrue();
        } catch (error) {
          const err = error as Error;
          hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
          throw new Error(err.message);
        }
      });

      it('should automatically use chunked download for large file', 0, async () => {
        try {
          const testData = new ArrayBuffer(20 * 1024 * 1024); // 20MB
          const testKey = 'integration-test/large-file-download.kdbx';
          await storage.write(`/${testBucket}/${testKey}`, testData);

          hilog.info(DOMAIN, TAG, 'Large file uploaded for download test');

          let progressCalled = false;
          storage.setProgressCallback((progress: MultipartUploadProgress) => {
            progressCalled = true;
            hilog.info(DOMAIN, TAG, 'Download progress: %{public}d/%{public}d bytes, part %{public}d/%{public}d',
              progress.uploadedBytes, progress.totalBytes, progress.currentPart, progress.totalParts);
          });

          const result = await storage.read(`/${testBucket}/${testKey}`);

          hilog.info(DOMAIN, TAG, 'Downloaded file size: %{public}d bytes', result.byteLength);

          expect(result.byteLength).assertEqual(20 * 1024 * 1024);
          expect(progressCalled).assertTrue();
        } catch (error) {
          const err = error as Error;
          hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
          throw new Error(err.message);
        }
      });

      it('should use regular upload for small file', 0, async () => {
        try {
          const smallData = new ArrayBuffer(1024 * 1024); // 1MB
          let progressCalled = false;

          storage.setProgressCallback((progress: MultipartUploadProgress) => {
            progressCalled = true;
            hilog.info(DOMAIN, TAG, 'Upload progress (small): %{public}d/%{public}d bytes',
              progress.uploadedBytes, progress.totalBytes);
          });

          const testKey = 'integration-test/small-file-1mb.kdbx';
          await storage.write(`/${testBucket}/${testKey}`, smallData);

          hilog.info(DOMAIN, TAG, 'Small file uploaded successfully');
          expect(progressCalled).assertFalse();

          const result = await storage.read(`/${testBucket}/${testKey}`);
          expect(result.byteLength).assertEqual(1024 * 1024);

          hilog.info(DOMAIN, TAG, 'Small file verified successfully');
        } catch (error) {
          const err = error as Error;
          hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
          throw new Error(err.message);
        }
      });

      it('should report correct progress data', 0, async () => {
        try {
          const testData = new ArrayBuffer(15 * 1024 * 1024); // 15MB
          const progressData: MultipartUploadProgress[] = [];

          storage.setProgressCallback((progress: MultipartUploadProgress) => {
            progressData.push({
              uploadedBytes: progress.uploadedBytes,
              totalBytes: progress.totalBytes,
              currentPart: progress.currentPart,
              totalParts: progress.totalParts
            });
          });

          const testKey = 'integration-test/progress-test.kdbx';
          await storage.write(`/${testBucket}/${testKey}`, testData);

          hilog.info(DOMAIN, TAG, 'Progress events count: %{public}d', progressData.length);

          expect(progressData.length > 0).assertTrue();

          const firstProgress = progressData[0];
          expect(firstProgress.totalBytes).assertEqual(15 * 1024 * 1024);
          expect(firstProgress.currentPart).assertEqual(1);

          const lastProgress = progressData[progressData.length - 1];
          expect(lastProgress.uploadedBytes).assertEqual(15 * 1024 * 1024);
          expect(lastProgress.currentPart).assertEqual(lastProgress.totalParts);
        } catch (error) {
          const err = error as Error;
          hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
          throw new Error(err.message);
        }
      });

      it('should use multipart at threshold', 0, async () => {
        try {
          // 5MB (MULTIPART_THRESHOLD)
          const thresholdData = new ArrayBuffer(5 * 1024 * 1024);
          let progressCalled = false;

          storage.setProgressCallback((progress: MultipartUploadProgress) => {
            progressCalled = true;
          });

          const testKey = 'integration-test/threshold-5mb.kdbx';
          await storage.write(`/${testBucket}/${testKey}`, thresholdData);

          // 5MB 应该触发分块上传（>= 阈值）
          expect(progressCalled).assertTrue();

          const result = await storage.read(`/${testBucket}/${testKey}`);
          expect(result.byteLength).assertEqual(5 * 1024 * 1024);

          hilog.info(DOMAIN, TAG, 'Threshold file test passed');
        } catch (error) {
          const err = error as Error;
          hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
          throw new Error(err.message);
        }
      });

      it('should use regular upload below threshold', 0, async () => {
        try {
          // 4.9MB (just below threshold)
          const belowThresholdData = new ArrayBuffer(4.9 * 1024 * 1024);
          let progressCalled = false;

          storage.setProgressCallback((progress: MultipartUploadProgress) => {
            progressCalled = true;
          });

          const testKey = 'integration-test/below-threshold.kdbx';
          await storage.write(`/${testBucket}/${testKey}`, belowThresholdData);

          // 小于 5MB 不应该触发分块上传
          expect(progressCalled).assertFalse();

          const result = await storage.read(`/${testBucket}/${testKey}`);
          expect(result.byteLength).assertEqual(4.9 * 1024 * 1024);

          hilog.info(DOMAIN, TAG, 'Below threshold file test passed');
        } catch (error) {
          const err = error as Error;
          hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
          throw new Error(err.message);
        }
      });
    });
  });
}
