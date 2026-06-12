import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Client, S3ClientOptionsImpl } from '../../../../../main/ets/storage/s3/S3Client';
import { MultipartUploadInit } from '../../../../../main/ets/storage/s3/S3Types';
import { S3TestConfig } from './S3TestConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'S3ClientMultipartTest';

export default function s3ClientMultipartTest() {
  describe('S3Client Multipart Upload', () => {
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
        expect(result.data).assertNotNull();
        expect(result.data?.uploadId).assertNotEmpty();
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
        throw error;
      }
    });

    /**
     * 测试 createMultipartUpload 返回的 uploadId 格式
     */
    it('should_return_valid_uploadId_format', 0, async () => {
      try {
        const result = await client.createMultipartUpload(testBucket, testKey);

        expect(result.success).assertTrue();
        expect(result.data?.uploadId).assertNotNull();

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
        throw error;
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
        throw error;
      }
    });

    /**
     * 测试 createMultipartUpload 响应头
     */
    it('should_return_response_headers', 0, async () => {
      try {
        const result = await client.createMultipartUpload(testBucket, testKey);

        expect(result.success).assertTrue();
        expect(result.headers).assertNotNull();

        // 检查关键响应头
        const headers = result.headers;
        if (headers) {
          hilog.info(DOMAIN, TAG, 'Response headers: %{public}s', JSON.stringify(headers));

          // 检查是否有 content-type 头
          const contentType = headers['content-type'] || headers['Content-Type'];
          expect(contentType).assertNotNull();
        }

        // 清理
        if (result.data?.uploadId) {
          await client.abortMultipartUpload(testBucket, testKey, result.data.uploadId);
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Test error: %{public}s', err.message);
        throw error;
      }
    });
  });
}
