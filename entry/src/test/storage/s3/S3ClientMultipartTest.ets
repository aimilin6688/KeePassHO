import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { S3Client, S3ClientOptionsImpl } from '../../../../main/ets/storage/s3/S3Client';
import { UploadedPart } from '../../../../main/ets/storage/s3/S3Types';

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
  });
}
