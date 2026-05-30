import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Client } from '../../../../../main/ets/storage/s3/S3Client';
import { S3Object, S3Result, S3Bucket } from '../../../../../main/ets/storage/s3/S3Types';
import { S3TestConfig, S3ClientOptionsImpl } from './S3TestConfig';
import { util } from '@kit.ArkTS';


export default function S3ClientTest() {
  describe('S3Client', () => {

    let client: S3Client;

    afterEach(() => {
      if (client) {
        client.close();
      }
    });

    /**
     * 测试客户端初始化
     */
    describe('Initialization', () => {
      it('should create client with valid options', 0, () => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          S3TestConfig.ENDPOINT,
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION,
          false,
          S3TestConfig.TIMEOUT
        );
        client = new S3Client(options);

        expect(client).not().assertUndefined();
      });

      it('should accept custom timeout', 0, () => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          S3TestConfig.ENDPOINT,
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION,
          false,
          60000
        );
        client = new S3Client(options);

        expect(client).not().assertUndefined();
      });

      it('should accept pathStyle option', 0, () => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          S3TestConfig.ENDPOINT,
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION,
          true,
          S3TestConfig.TIMEOUT
        );
        client = new S3Client(options);

        expect(client).not().assertUndefined();
      });
    });

    /**
     * 测试 close 方法
     */
    describe('close', () => {
      it('should close client without error', 0, () => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          S3TestConfig.ENDPOINT,
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION,
          false,
          S3TestConfig.TIMEOUT
        );
        client = new S3Client(options);

        // 关闭不应抛出异常
        client.close();
      });
    });

    /**
     * 测试真实的 API 调用
     */
    describe('RealAPICalls', () => {
      beforeEach(() => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          S3TestConfig.ENDPOINT,
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION,
          false,
          S3TestConfig.TIMEOUT
        );
        client = new S3Client(options);
      });

      afterEach(() => {
        client.close();
      });

      it('listBuckets should return success', 0, async () => {
        const result: S3Result<S3Bucket[]> = await client.listBuckets();

        expect(result).not().assertUndefined();
        expect(result.success).not().assertUndefined();
        expect(result.statusCode).not().assertUndefined();
        // 使用有效凭证，预期成功
        expect(result.success).assertTrue();
        expect(result.data).not().assertUndefined();
      });

      it('headBucket should return true for existing bucket', 0, async () => {
        const exists: boolean = await client.headBucket(S3TestConfig.BUCKET);

        expect(typeof exists).assertEqual('boolean');
        expect(exists).assertTrue();
      });

      it('headBucket should return false for non-existent bucket', 0, async () => {
        const exists: boolean = await client.headBucket('non-existent-bucket-12345-' + Date.now());

        expect(typeof exists).assertEqual('boolean');
        expect(exists).assertFalse();
      });

      it('listObjects should return success', 0, async () => {
        const result: S3Result<S3Object[]> = await client.listObjects(S3TestConfig.BUCKET);

        expect(result).not().assertUndefined();
        expect(result.success).assertTrue();
        expect(result.data).not().assertUndefined();
      });

      it('listObjects with prefix should return filtered results', 0, async () => {
        const result: S3Result<S3Object[]> = await client.listObjects(S3TestConfig.BUCKET, '');

        expect(result).not().assertUndefined();
        expect(result.success).assertTrue();
      });

      it('getObject should return file content', 0, async () => {
        const result: S3Result<ArrayBuffer> = await client.getObject(S3TestConfig.BUCKET, S3TestConfig.TEST_FILE);

        expect(result).not().assertUndefined();
        expect(result.success).assertTrue();
        expect(result.data).not().assertUndefined();
        expect(result.data!.byteLength).assertLarger(0);
      });

      it('getObject should fail for non-existent key', 0, async () => {
        const result: S3Result<ArrayBuffer> = await client.getObject(S3TestConfig.BUCKET, 'non-existent-key-' + Date.now() + '.txt');

        expect(result).not().assertUndefined();
        expect(result.success).assertFalse();
        expect(result.statusCode).assertEqual(404);
      });

      it('headObject should return object metadata', 0, async () => {
        const result: S3Result<S3Object> = await client.headObject(S3TestConfig.BUCKET, S3TestConfig.TEST_FILE);

        expect(result).not().assertUndefined();
        expect(result.success).assertTrue();
        expect(result.data).not().assertUndefined();
        expect(result.data!.key).assertEqual(S3TestConfig.TEST_FILE);
        expect(result.data!.size).assertLarger(0);
      });

      it('headObject should fail for non-existent key', 0, async () => {
        const result: S3Result<S3Object> = await client.headObject(S3TestConfig.BUCKET, 'non-existent-' + Date.now() + '.txt');

        expect(result).not().assertUndefined();
        expect(result.success).assertFalse();
      });

      it('testConnection should return success', 0, async () => {
        const result: S3Result<void> = await client.testConnection();

        expect(result).not().assertUndefined();
        expect(result.success).assertTrue();
      });

      it('putObject and deleteObject should work', 0, async () => {
        const encoder: util.TextEncoder = new util.TextEncoder();
        const testContent: string = 'Test content ' + Date.now();
        const data: Uint8Array = encoder.encodeInto(testContent);
        const testKey: string = 'test-upload-' + Date.now() + '.txt';

        // 上传文件
        const putResult: S3Result<void> = await client.putObject(S3TestConfig.BUCKET, testKey, data.buffer as ArrayBuffer);
        expect(putResult).not().assertUndefined();
        expect(putResult.success).assertTrue();

        // 验证文件存在
        const headResult: S3Result<S3Object> = await client.headObject(S3TestConfig.BUCKET, testKey);
        expect(headResult.success).assertTrue();
        expect(headResult.data!.size).assertEqual(data.length);

        // 读取文件内容
        const getResult: S3Result<ArrayBuffer> = await client.getObject(S3TestConfig.BUCKET, testKey);
        expect(getResult.success).assertTrue();

        const decoder: util.TextDecoder = new util.TextDecoder();
        const readContent: string = decoder.decodeToString(new Uint8Array(getResult.data!));
        expect(readContent).assertEqual(testContent);

        // 删除文件
        const deleteResult: S3Result<void> = await client.deleteObject(S3TestConfig.BUCKET, testKey);
        expect(deleteResult.success).assertTrue();

        // 验证文件已删除
        const verifyResult: S3Result<S3Object> = await client.headObject(S3TestConfig.BUCKET, testKey);
        expect(verifyResult.success).assertFalse();
      });
    });

    /**
     * 测试不同端点配置
     */
    describe('DifferentEndpoints', () => {
      it('should work with custom S3-compatible endpoint', 0, () => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          'https://storage.example.com',
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          'default',
          true,
          S3TestConfig.TIMEOUT
        );
        client = new S3Client(options);

        expect(client).not().assertUndefined();
      });

      it('should work with HTTP endpoint', 0, () => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          'http://localhost:9000',
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          'us-east-1',
          true,
          S3TestConfig.TIMEOUT
        );
        client = new S3Client(options);

        expect(client).not().assertUndefined();
      });

      it('should work with endpoint containing port', 0, () => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          'https://s3.example.com:8443',
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION,
          false,
          S3TestConfig.TIMEOUT
        );
        client = new S3Client(options);

        expect(client).not().assertUndefined();
      });

      it('should work with endpoint containing path', 0, () => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          'https://s3.example.com/s3-api',
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION,
          true,
          S3TestConfig.TIMEOUT
        );
        client = new S3Client(options);

        expect(client).not().assertUndefined();
      });
    });

    /**
     * 测试 MinIO 兼容性
     */
    describe('MinIOCompatibility', () => {
      it('should support MinIO-style configuration', 0, () => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          'http://localhost:9000',
          'minioadmin',
          'minioadmin',
          'us-east-1',
          true,
          S3TestConfig.TIMEOUT
        );
        client = new S3Client(options);

        expect(client).not().assertUndefined();
      });
    });
  });
}
