import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Client, S3ClientOptionsImpl } from '../../../../../main/ets/storage/s3/S3Client';
import { MultipartUploadInit, UploadedPart, MultipartUploadProgress } from '../../../../../main/ets/storage/s3/S3Types';
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
}
