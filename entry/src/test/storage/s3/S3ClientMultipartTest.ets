import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { S3Client, S3ClientOptionsImpl } from '../../../../main/ets/storage/s3/S3Client';
import { UploadedPart, MultipartUploadProgress } from '../../../../main/ets/storage/s3/S3Types';

export default function s3MultipartTest() {
  describe('S3MultipartTest', () => {
    let client: S3Client;
    const testBucket = 'test-bucket';
    const testKey = 'test-object.dat';

    beforeAll(() => {
      // 使用模拟 S3 服务器配置
      const options = new S3ClientOptionsImpl(
        'http://localhost:9000',  // MinIO 测试服务器
        'test-access-key',
        'test-secret-key',
        'us-east-1',
        true,  // path-style
        30000
      );
      client = new S3Client(options);
    });

    afterAll(() => {
      client.close();
    });

    /**
     * 测试 completeMultipartUpload 成功场景
     */
    it('should_complete_multipart_upload_successfully', async () => {
      const initResult = await client.createMultipartUpload(testBucket, testKey);
      const uploadId = initResult.data!.uploadId;

      // 上传两个 parts
      const partData1 = new ArrayBuffer(8 * 1024 * 1024);
      const partData2 = new ArrayBuffer(4 * 1024 * 1024);

      const part1 = await client.uploadPart(testBucket, testKey, uploadId, 1, partData1);
      const part2 = await client.uploadPart(testBucket, testKey, uploadId, 2, partData2);

      // 完成上传
      const parts: UploadedPart[] = [part1.data!, part2.data!];
      const result = await client.completeMultipartUpload(
        testBucket,
        testKey,
        uploadId,
        parts
      );

      expect(result.success).assertTrue();
      expect(result.statusCode).assertEqual(200);
    });

    /**
     * 测试 completeMultipartUpload 按顺序排序 Parts
     */
    it('should_sort_parts_by_part_number', async () => {
      const initResult = await client.createMultipartUpload(testBucket, testKey);
      const uploadId = initResult.data!.uploadId;

      // 上传三个 parts，但顺序不同
      const partData1 = new ArrayBuffer(5 * 1024 * 1024);
      const partData2 = new ArrayBuffer(5 * 1024 * 1024);
      const partData3 = new ArrayBuffer(5 * 1024 * 1024);

      const part1 = await client.uploadPart(testBucket, testKey, uploadId, 1, partData1);
      const part2 = await client.uploadPart(testBucket, testKey, uploadId, 2, partData2);
      const part3 = await client.uploadPart(testBucket, testKey, uploadId, 3, partData3);

      // 故意乱序传递 parts
      const parts: UploadedPart[] = [part3.data!, part1.data!, part2.data!];
      const result = await client.completeMultipartUpload(
        testBucket,
        testKey,
        uploadId,
        parts
      );

      expect(result.success).assertTrue();
    });

    /**
     * 测试 abortMultipartUpload 成功场景
     */
    it('should_abort_multipart_upload_successfully', async () => {
      const initResult = await client.createMultipartUpload(testBucket, testKey);
      const uploadId = initResult.data!.uploadId;

      // 上传一个 part
      const partData = new ArrayBuffer(8 * 1024 * 1024);
      await client.uploadPart(testBucket, testKey, uploadId, 1, partData);

      // 取消上传
      const result = await client.abortMultipartUpload(testBucket, testKey, uploadId);

      expect(result.success).assertTrue();
    });

    /**
     * 测试 putObjectSmart 小文件（< 5MB）
     */
    it('should_use_simple_upload_for_small_file', async () => {
      const smallData = new ArrayBuffer(3 * 1024 * 1024); // 3MB
      let progressCalled = false;

      const result = await client.putObjectSmart(
        testBucket,
        testKey + '-small',
        smallData,
        (progress) => {
          progressCalled = true;
        }
      );

      expect(result.success).assertTrue();
      // 小文件不会触发进度回调
      expect(progressCalled).assertFalse();
    });

    /**
     * 测试 putObjectSmart 大文件（>= 5MB）
     */
    it('should_use_multipart_upload_for_large_file', async () => {
      const largeData = new ArrayBuffer(20 * 1024 * 1024); // 20MB
      const progressEvents: MultipartUploadProgress[] = [];

      const result = await client.putObjectSmart(
        testBucket,
        testKey + '-large',
        largeData,
        (progress) => {
          progressEvents.push(progress);
        }
      );

      expect(result.success).assertTrue();
      expect(progressEvents.length > 0).assertTrue();
      expect(progressEvents[progressEvents.length - 1].uploadedBytes).assertEqual(20 * 1024 * 1024);
    });

    /**
     * 测试 putObjectSmart 自定义阈值
     */
    it('should_use_custom_threshold', async () => {
      const data = new ArrayBuffer(6 * 1024 * 1024); // 6MB
      let progressCalled = false;

      // 使用 10MB 阈值，6MB 应该使用简单上传
      const result = await client.putObjectSmart(
        testBucket,
        testKey + '-custom',
        data,
        (progress) => {
          progressCalled = true;
        },
        10 * 1024 * 1024 // 10MB 阈值
      );

      expect(result.success).assertTrue();
      expect(progressCalled).assertFalse();
    });
  });
}
