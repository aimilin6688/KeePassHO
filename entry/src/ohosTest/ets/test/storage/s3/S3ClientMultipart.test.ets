import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Client, S3ClientOptionsImpl } from '../../../../../main/ets/storage/s3/S3Client';
import { MultipartUploadInit, UploadedPart, MultipartUploadProgress, UploadTask, UploadWorkerResult } from '../../../../../main/ets/storage/s3/S3Types';
import { S3MultipartConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { S3UploadQueue } from '../../../../../main/ets/storage/s3/S3UploadQueue';
import { S3TestConfig } from './S3TestConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'S3ClientMultipartTest';

export default function S3ClientMultipartTest() {
  describe('S3Client_Multipart_Upload', () => {
    let client: S3Client;
    const testBucket = S3TestConfig.BUCKET;
    const testKey = 'multipart-test/test-file.kdbx';

    beforeEach(() => {
      const options = S3TestConfig.getClientOptions();
      client = new S3Client(options);
    });

    afterEach(() => {
      if (client) {
        client.close();
      }
    });

    /**
     * 测试 createMultipartUpload 成功场景
     */
    it('should_create_multipart_upload_successfully', 0, async () => {
      try {
        const result = await client.createMultipartUpload(testBucket, testKey);

        hilog.info(DOMAIN, TAG, 'createMultipartUpload result: success=%{public}s, statusCode=%{public}d',
          String(result.success), result.statusCode);

        expect(result.success).assertTrue();
        expect(result.statusCode).assertEqual(200);
        expect(result.data !== null).assertTrue();
        expect(result.data?.uploadId?.length ?? 0).assertLarger(0);
        expect(result.data?.bucket).assertEqual(testBucket);
        expect(result.data?.key).assertEqual(testKey);

        hilog.info(DOMAIN, TAG, 'Created multipart upload with uploadId: %{public}s', result.data?.uploadId ?? '');

        // 清理：取消 multipart upload
        if (result.data?.uploadId) {
          const abortResult = await client.abortMultipartUpload(testBucket, testKey, result.data.uploadId);
          hilog.info(DOMAIN, TAG, 'Aborted multipart upload: %{public}s', String(abortResult.success));
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试 createMultipartUpload 返回的 uploadId 格式
     */
    it('should_return_valid_uploadId_format', 0, async () => {
      try {
        const result = await client.createMultipartUpload(testBucket, testKey);

        expect(result.success).assertTrue();
        expect(result.data !== null).assertTrue();

        // uploadId 应该是一个非空字符串
        const uploadId = result.data?.uploadId ?? '';
        expect(uploadId.length > 0).assertTrue();

        hilog.info(DOMAIN, TAG, 'UploadId length: %{public}d', uploadId.length);

        // 清理
        if (result.data?.uploadId) {
          await client.abortMultipartUpload(testBucket, testKey, result.data.uploadId);
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试 createMultipartUpload 对不同 key 的支持
     */
    it('should_support_various_key_patterns', 0, async () => {
      const testKeys = [
        'simple-test.kdbx',
        'folder/nested/test.kdbx',
        '中文测试/密码库.kdbx'
      ];

      try {
        for (const key of testKeys) {
          const result = await client.createMultipartUpload(testBucket, key);

          expect(result.success).assertTrue();
          expect(result.data?.key).assertEqual(key);

          hilog.info(DOMAIN, TAG, 'Created multipart upload for key: %{public}s', key);

          // 清理
          if (result.data?.uploadId) {
            await client.abortMultipartUpload(testBucket, key, result.data.uploadId);
          }
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试 createMultipartUpload 响应头
     */
    it('should_return_response_headers', 0, async () => {
      try {
        const result = await client.createMultipartUpload(testBucket, testKey);

        expect(result.success).assertTrue();
        expect(result.headers !== null).assertTrue();

        // 检查关键响应头
        const headers = result.headers;
        if (headers) {
          hilog.info(DOMAIN, TAG, 'Response headers: %{public}s', JSON.stringify(headers));

          // 检查是否有 content-type 头
          const contentType = headers['content-type'] || headers['Content-Type'];
          expect(contentType !== undefined).assertTrue();
        }

        // 清理
        if (result.data?.uploadId) {
          await client.abortMultipartUpload(testBucket, testKey, result.data.uploadId);
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试 uploadPart 成功场景
     */
    it('should_upload_part_successfully', 0, async () => {
      try {
        // 先创建 multipart upload
        const initResult = await client.createMultipartUpload(testBucket, testKey);
        const uploadId = initResult.data!.uploadId;

        hilog.info(DOMAIN, TAG, 'Created multipart upload with uploadId: %{public}s', uploadId);

        // 准备测试数据（1MB - 减小数据量以加快测试）
        const partData = new ArrayBuffer(1 * 1024 * 1024);

        // 上传第一个 part
        const result = await client.uploadPart(
          testBucket,
          testKey,
          uploadId,
          1,
          partData
        );

        hilog.info(DOMAIN, TAG, 'uploadPart result: success=%{public}s, statusCode=%{public}d',
          String(result.success), result.statusCode);

        expect(result.success).assertTrue();
        expect(result.statusCode).assertEqual(200);
        expect(result.data !== null).assertTrue();
        expect(result.data?.partNumber).assertEqual(1);
        expect(result.data?.etag?.length ?? 0).assertLarger(0);
        expect(result.data?.size).assertEqual(1 * 1024 * 1024);

        hilog.info(DOMAIN, TAG, 'Uploaded part: partNumber=%{public}d, etag=%{public}s, size=%{public}d',
          result.data?.partNumber ?? 0, result.data?.etag ?? '', result.data?.size ?? 0);

        // 清理：取消 multipart upload
        await client.abortMultipartUpload(testBucket, testKey, uploadId);
        hilog.info(DOMAIN, TAG, 'Aborted multipart upload');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试 abortMultipartUpload 成功场景
     */
    it('should_abort_multipart_upload_successfully', 0, async () => {
      try {
        // 先创建 multipart upload
        const initResult = await client.createMultipartUpload(testBucket, testKey);
        const uploadId = initResult.data!.uploadId;

        hilog.info(DOMAIN, TAG, 'Created multipart upload with uploadId: %{public}s', uploadId);

        // 上传一个 part（1MB - 减小数据量以加快测试）
        const partData = new ArrayBuffer(1 * 1024 * 1024);
        await client.uploadPart(testBucket, testKey, uploadId, 1, partData);

        hilog.info(DOMAIN, TAG, 'Uploaded part 1');

        // 取消上传
        const result = await client.abortMultipartUpload(testBucket, testKey, uploadId);

        hilog.info(DOMAIN, TAG, 'abortMultipartUpload result: success=%{public}s, statusCode=%{public}d',
          String(result.success), result.statusCode);

        expect(result.success).assertTrue();
        expect(result.statusCode).assertEqual(204);

        hilog.info(DOMAIN, TAG, 'Successfully aborted multipart upload');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试 getObjectChunked 分块下载
     */
    it('should_download_file_in_chunks', 0, async () => {
      try {
        // 先上传一个 3MB 文件（减小数据量以加快测试）
        const testData = new ArrayBuffer(3 * 1024 * 1024);
        const uploadResult = await client.putObject(testBucket, testKey + '-chunked', testData);

        hilog.info(DOMAIN, TAG, 'putObject result: success=%{public}s', String(uploadResult.success));
        expect(uploadResult.success).assertTrue();

        // 分块下载（1MB chunks）
        const progressEvents: MultipartUploadProgress[] = [];
        const result = await client.getObjectChunked(
          testBucket,
          testKey + '-chunked',
          1 * 1024 * 1024, // 1MB chunks
          (progress) => {
            progressEvents.push(progress);
            hilog.info(DOMAIN, TAG, 'Download progress: %{public}d/%{public}d bytes, part %{public}d/%{public}d',
              progress.uploadedBytes, progress.totalBytes, progress.currentPart, progress.totalParts);
          }
        );

        hilog.info(DOMAIN, TAG, 'getObjectChunked result: success=%{public}s, statusCode=%{public}d',
          String(result.success), result.statusCode);

        expect(result.success).assertTrue();
        expect(result.data !== null).assertTrue();
        expect(result.data?.byteLength).assertEqual(3 * 1024 * 1024);
        expect(progressEvents.length > 0).assertTrue();

        hilog.info(DOMAIN, TAG, 'Successfully downloaded file in chunks, size=%{public}d, progressEvents=%{public}d',
          result.data?.byteLength ?? 0, progressEvents.length);
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });
  });

  /**
   * 分块大小计算和并发上传逻辑测试
   * 这些测试验证核心算法的正确性，不需要真实的 S3 服务
   */
  describe('S3Client_Multipart_Logic', () => {
    /**
     * 测试 MultipartUploadQueue 基本功能
     */
    it('should_manage_upload_queue_correctly', 0, () => {
      const totalBytes = 10 * 1024 * 1024; // 10MB
      const totalParts = 2;
      const queue = new S3UploadQueue(totalBytes, totalParts);

      // 添加任务
      const task1: UploadTask = { partNumber: 1, start: 0, end: 5 * 1024 * 1024, retryCount: 0 };
      const task2: UploadTask = { partNumber: 2, start: 5 * 1024 * 1024, end: 10 * 1024 * 1024, retryCount: 0 };

      queue.addTask(task1);
      queue.addTask(task2);

      // 获取任务
      const nextTask = queue.getNextTask();
      expect(nextTask !== null).assertTrue();
      expect(nextTask?.partNumber).assertEqual(1);

      // 标记完成
      queue.markCompleted(5 * 1024 * 1024);

      // 检查进度
      const progress = queue.getProgress();
      expect(progress.uploadedBytes).assertEqual(5 * 1024 * 1024);
      expect(progress.currentPart).assertEqual(1);
      expect(progress.totalParts).assertEqual(2);

      hilog.info(DOMAIN, TAG, 'Queue test passed: progress=%{public}d/%{public}d',
        progress.currentPart, progress.totalParts);
    });

    /**
     * 测试 MultipartUploadQueue 重试逻辑
     */
    it('should_handle_retry_logic_correctly', 0, () => {
      const queue = new S3UploadQueue(10 * 1024 * 1024, 2);

      const task: UploadTask = { partNumber: 1, start: 0, end: 5 * 1024 * 1024, retryCount: 0 };
      queue.addTask(task);

      const retrievedTask = queue.getNextTask();
      expect(retrievedTask !== null).assertTrue();

      // 模拟重试
      const canRetry1 = queue.retryTask(retrievedTask!);
      expect(canRetry1).assertTrue(); // 第一次重试应该成功
      expect(retrievedTask!.retryCount).assertEqual(1);

      // 继续重试直到超过最大次数
      const task2 = queue.getNextTask();
      const canRetry2 = queue.retryTask(task2!);
      expect(canRetry2).assertTrue(); // 第二次重试
      expect(task2!.retryCount).assertEqual(2);

      const task3 = queue.getNextTask();
      const canRetry3 = queue.retryTask(task3!);
      expect(canRetry3).assertTrue(); // 第三次重试
      expect(task3!.retryCount).assertEqual(3);

      const task4 = queue.getNextTask();
      const canRetry4 = queue.retryTask(task4!);
      expect(canRetry4).assertFalse(); // 超过最大重试次数

      // 检查失败计数
      expect(queue.hasFailedTasks()).assertTrue();
      expect(queue.getFailedCount()).assertEqual(1);

      hilog.info(DOMAIN, TAG, 'Retry logic test passed: failedCount=%{public}d', queue.getFailedCount());
    });

    /**
     * 测试分块大小配置常量
     */
    it('should_have_correct_config_constants', 0, () => {
      // 验证最小分块大小为 5MB
      expect(S3MultipartConfig.MIN_PART_SIZE).assertEqual(5 * 1024 * 1024);

      // 验证最大分块大小为 32MB
      expect(S3MultipartConfig.MAX_PART_SIZE).assertEqual(32 * 1024 * 1024);

      // 验证分块阈值为 5MB
      expect(S3MultipartConfig.MULTIPART_THRESHOLD).assertEqual(5 * 1024 * 1024);

      // 验证目标分块数量为 500
      expect(S3MultipartConfig.TARGET_PART_COUNT).assertEqual(500);

      // 验证并发上传数量为 3
      expect(S3MultipartConfig.CONCURRENT_UPLOADS).assertEqual(3);

      // 验证最大重试次数为 3
      expect(S3MultipartConfig.MAX_RETRY_COUNT).assertEqual(3);

      hilog.info(DOMAIN, TAG, 'Config constants test passed');
    });

    /**
     * 测试 UploadTask 类型定义
     */
    it('should_create_upload_task_correctly', 0, () => {
      const task: UploadTask = {
        partNumber: 1,
        start: 0,
        end: 5 * 1024 * 1024,
        retryCount: 0
      };

      expect(task.partNumber).assertEqual(1);
      expect(task.start).assertEqual(0);
      expect(task.end).assertEqual(5 * 1024 * 1024);
      expect(task.retryCount).assertEqual(0);

      hilog.info(DOMAIN, TAG, 'UploadTask test passed: partNumber=%{public}d', task.partNumber);
    });

    /**
     * 测试进度计算逻辑
     */
    it('should_calculate_progress_correctly', 0, () => {
      const totalBytes = 100 * 1024 * 1024; // 100MB
      const totalParts = 20;
      const queue = new S3UploadQueue(totalBytes, totalParts);

      // 模拟上传 10 个分块
      const partSize = 5 * 1024 * 1024; // 5MB
      for (let i = 1; i <= 10; i++) {
        queue.markCompleted(partSize);
      }

      const progress = queue.getProgress();

      // 验证进度计算
      expect(progress.uploadedBytes).assertEqual(10 * partSize);
      expect(progress.totalBytes).assertEqual(totalBytes);
      expect(progress.currentPart).assertEqual(10);
      expect(progress.totalParts).assertEqual(totalParts);

      // 验证上传百分比（应该是 50%）
      const percentage = (progress.uploadedBytes / progress.totalBytes) * 100;
      expect(percentage).assertEqual(50);

      hilog.info(DOMAIN, TAG, 'Progress calculation test passed: %{public}d%%', percentage);
    });

    /**
     * 测试分块大小算法边界条件
     * 模拟 calculatePartSize 的逻辑
     */
    it('should_calculate_part_size_for_various_file_sizes', 0, () => {
      const calculatePartSize = (fileSize: number): number => {
        const idealSize = Math.max(
          fileSize / S3MultipartConfig.TARGET_PART_COUNT,
          S3MultipartConfig.MIN_PART_SIZE
        );

        const fiveMB = 5 * 1024 * 1024;
        const eightMB = 8 * 1024 * 1024;
        const sixteenMB = 16 * 1024 * 1024;
        const thirtyTwoMB = 32 * 1024 * 1024;

        if (idealSize <= eightMB) {
          return fiveMB;
        } else if (idealSize <= sixteenMB) {
          return eightMB;
        } else if (idealSize <= thirtyTwoMB) {
          return sixteenMB;
        } else {
          return thirtyTwoMB;
        }
      };

      // 10MB 文件 → 5MB 分块
      expect(calculatePartSize(10 * 1024 * 1024)).assertEqual(5 * 1024 * 1024);

      // 100MB 文件 → 5MB 分块
      expect(calculatePartSize(100 * 1024 * 1024)).assertEqual(5 * 1024 * 1024);

      // 1GB 文件 → 5MB 分块（理想大小约 2.1MB，提升到 5MB）
      expect(calculatePartSize(1 * 1024 * 1024 * 1024)).assertEqual(5 * 1024 * 1024);

      // 4GB 文件 → 8MB 分块（理想大小约 8.4MB）
      expect(calculatePartSize(4 * 1024 * 1024 * 1024)).assertEqual(8 * 1024 * 1024);

      // 10GB 文件 → 16MB 分块（理想大小约 21MB）
      expect(calculatePartSize(10 * 1024 * 1024 * 1024)).assertEqual(16 * 1024 * 1024);

      // 100GB 文件 → 32MB 分块（理想大小约 210MB，超过 32MB 上限）
      expect(calculatePartSize(100 * 1024 * 1024 * 1024)).assertEqual(32 * 1024 * 1024);

      hilog.info(DOMAIN, TAG, 'Part size calculation test passed');
    });

    /**
     * 测试并发上传器结果合并逻辑
     */
    it('should_merge_worker_results_correctly', 0, () => {
      // 模拟 3 个上传器的结果
      const part1: UploadedPart = { partNumber: 1, etag: 'etag1', size: 5 * 1024 * 1024 };
      const part4: UploadedPart = { partNumber: 4, etag: 'etag4', size: 5 * 1024 * 1024 };
      const part2: UploadedPart = { partNumber: 2, etag: 'etag2', size: 5 * 1024 * 1024 };
      const part5: UploadedPart = { partNumber: 5, etag: 'etag5', size: 5 * 1024 * 1024 };
      const part3: UploadedPart = { partNumber: 3, etag: 'etag3', size: 5 * 1024 * 1024 };

      const result1: UploadWorkerResult = {
        success: true,
        parts: [part1, part4]
      };
      const result2: UploadWorkerResult = {
        success: true,
        parts: [part2, part5]
      };
      const result3: UploadWorkerResult = {
        success: true,
        parts: [part3]
      };

      const results: UploadWorkerResult[] = [result1, result2, result3];

      // 合并并排序
      const allParts: UploadedPart[] = [];
      for (const result of results) {
        allParts.push(...result.parts);
      }
      allParts.sort((a, b) => a.partNumber - b.partNumber);

      // 验证结果
      expect(allParts.length).assertEqual(5);
      expect(allParts[0].partNumber).assertEqual(1);
      expect(allParts[1].partNumber).assertEqual(2);
      expect(allParts[2].partNumber).assertEqual(3);
      expect(allParts[3].partNumber).assertEqual(4);
      expect(allParts[4].partNumber).assertEqual(5);

      hilog.info(DOMAIN, TAG, 'Worker result merge test passed: totalParts=%{public}d', allParts.length);
    });

    /**
     * 测试队列任务顺序
     */
    it('should_process_tasks_in_fifo_order', 0, () => {
      const queue = new S3UploadQueue(15 * 1024 * 1024, 3);

      // 按顺序添加任务
      for (let i = 1; i <= 3; i++) {
        const task: UploadTask = {
          partNumber: i,
          start: (i - 1) * 5 * 1024 * 1024,
          end: i * 5 * 1024 * 1024,
          retryCount: 0
        };
        queue.addTask(task);
      }

      // 验证按 FIFO 顺序获取
      for (let i = 1; i <= 3; i++) {
        const task = queue.getNextTask();
        expect(task?.partNumber).assertEqual(i);
        queue.markCompleted(5 * 1024 * 1024);
      }

      // 队列应该为空
      const emptyTask = queue.getNextTask();
      expect(emptyTask).assertNull();

      hilog.info(DOMAIN, TAG, 'FIFO order test passed');
    });

    /**
     * 测试重试任务添加到队列末尾
     */
    it('should_add_retry_task_to_end_of_queue', 0, () => {
      const queue = new S3UploadQueue(15 * 1024 * 1024, 3);

      // 添加 3 个任务
      for (let i = 1; i <= 3; i++) {
        queue.addTask({ partNumber: i, start: 0, end: 0, retryCount: 0 });
      }

      // 获取第一个任务并重试
      const task1 = queue.getNextTask();
      expect(task1?.partNumber).assertEqual(1);

      queue.retryTask(task1!);

      // 重试任务应该添加到队列末尾
      // 接下来应该是 2, 3, 1（重试的）
      const task2 = queue.getNextTask();
      expect(task2?.partNumber).assertEqual(2);

      const task3 = queue.getNextTask();
      expect(task3?.partNumber).assertEqual(3);

      const retryTask = queue.getNextTask();
      expect(retryTask?.partNumber).assertEqual(1);
      expect(retryTask?.retryCount).assertEqual(1);

      hilog.info(DOMAIN, TAG, 'Retry task order test passed');
    });
  });
}

