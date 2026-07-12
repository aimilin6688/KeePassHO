import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Storage } from '../../../../../main/ets/storage/s3/S3Storage';
import { TestS3StorageConfig } from './S3TestConfig';
import { S3TestConfig } from './S3TestConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MultipartUploadProgress } from '../../../../../main/ets/storage/s3/S3Types';

const DOMAIN = 0x0000;
const TAG = 'S3StorageIntegrationTest';

export default function S3StorageIntegrationTest() {
  describe('S3Storage Integration', () => {
    let storage: S3Storage;
    const testPath = '/test-bucket/test-database.kdbx';
    const testBucket = S3TestConfig.BUCKET;

    beforeEach(() => {
      const config = S3TestConfig.getStorageConfig(testBucket);
      storage = new S3Storage();
      storage.init(config);
    });

    afterEach(() => {
      storage.close();
    });

    /**
     * 测试 write() 自动选择分块上传
     */
    it('should_automatically_use_multipart_for_large_file', 0, async () => {
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

        // 验证进度回调被调用（大文件应该触发分块上传）
        expect(progressCalled).assertTrue();

        // 清理：删除测试文件
        // 注意：S3Storage 当前没有 delete 方法，这里省略清理步骤
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试 read() 自动选择分块下载
     */
    it('should_automatically_use_chunked_download_for_large_file', 0, async () => {
      try {
        // 先上传大文件
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

    /**
     * 测试小文件使用普通上传
     */
    it('should_use_regular_upload_for_small_file', 0, async () => {
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

        // 小文件不应该触发分块上传，因此进度回调不会被调用
        // 注意：putObject 方法不会调用进度回调
        expect(progressCalled).assertFalse();

        // 验证文件可以正常读取
        const result = await storage.read(`/${testBucket}/${testKey}`);
        expect(result.byteLength).assertEqual(1024 * 1024);

        hilog.info(DOMAIN, TAG, 'Small file verified successfully');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试进度回调数据正确性
     */
    it('should_report_correct_progress_data', 0, async () => {
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

        // 验证进度事件数量
        expect(progressData.length > 0).assertTrue();

        // 验证第一个进度事件
        const firstProgress = progressData[0];
        expect(firstProgress.totalBytes).assertEqual(15 * 1024 * 1024);
        expect(firstProgress.currentPart).assertEqual(1);

        // 验证最后一个进度事件
        const lastProgress = progressData[progressData.length - 1];
        expect(lastProgress.uploadedBytes).assertEqual(15 * 1024 * 1024);
        expect(lastProgress.currentPart).assertEqual(lastProgress.totalParts);
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试边界情况：刚好 5MB 的文件
     */
    it('should_use_multipart_at_threshold', 0, async () => {
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

        // 验证文件大小
        const result = await storage.read(`/${testBucket}/${testKey}`);
        expect(result.byteLength).assertEqual(5 * 1024 * 1024);

        hilog.info(DOMAIN, TAG, 'Threshold file test passed');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试边界情况：小于 5MB 的文件
     */
    it('should_use_regular_upload_below_threshold', 0, async () => {
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

        // 验证文件大小
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
}
