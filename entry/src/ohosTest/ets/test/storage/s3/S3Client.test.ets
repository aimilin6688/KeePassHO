import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Client, S3ClientOptionsImpl } from '../../../../../main/ets/storage/s3/S3Client';
import { S3Object, S3Result, S3Bucket } from '../../../../../main/ets/storage/s3/S3Types';
import { S3TestConfig } from './S3TestConfig';
import { TestFixtures } from '../TestFixtures';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'S3ClientTest';


export default function S3ClientTest() {
  describe('S3ClientTest', () => {

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
      beforeAll(async () => {
        // 上传 rawfile 中的真实 KDBX 数据库文件到测试桶，供 getObject/headObject 用例使用
        const fixture: ArrayBuffer = await TestFixtures.loadUnitTestKdbx();
        const setupClient = new S3Client(S3TestConfig.getClientOptions());
        try {
          const putResult = await setupClient.putObject(S3TestConfig.BUCKET, S3TestConfig.TEST_FILE, fixture);
          if (!putResult.success) {
            throw new Error(`upload test fixture failed: statusCode=${putResult.statusCode}, message=${putResult.message}`);
          }
          hilog.info(DOMAIN, TAG, 'RealAPICalls setup: uploaded unit-test.kdbx (%{public}d bytes) as %{public}s',
            fixture.byteLength, S3TestConfig.TEST_FILE);
        } finally {
          setupClient.close();
        }
      });

      beforeEach(() => {
        const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
          S3TestConfig.ENDPOINT,
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION,
          S3TestConfig.PATH_STYLE,
          S3TestConfig.TIMEOUT
        );
        client = new S3Client(options);
      });

      it('listBuckets should return success', 0, async () => {
        const result: S3Result<S3Bucket[]> = await client.listBuckets();

        expect(result).not().assertUndefined();
        expect(result.success).assertTrue();
        expect(result.statusCode).assertEqual(200);
        expect(result.data).not().assertUndefined();
        // 自建 SeaweedFS 必须能看到测试桶
        const names: string[] = (result.data ?? []).map((bucket: S3Bucket) => bucket.name);
        expect(names.includes(S3TestConfig.BUCKET)).assertTrue();
      });

      it('headBucket should return true for existing bucket', 0, async () => {
        // 直接输出配置信息
        hilog.info(DOMAIN, TAG, `Config: endpoint=${S3TestConfig.ENDPOINT}, bucket=${S3TestConfig.BUCKET}, region=${S3TestConfig.REGION}, pathStyle=${S3TestConfig.PATH_STYLE}`);

        const exists: boolean = await client.headBucket(S3TestConfig.BUCKET);

        hilog.info(DOMAIN, TAG, `headBucket result: ${exists}`);
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

        hilog.info(DOMAIN, TAG, `listObjects result: success=${result.success}, statusCode=${result.statusCode}, message=${result.message}`);
        expect(result).not().assertUndefined();
        expect(result.success).assertTrue();
        expect(result.data).not().assertUndefined();
      });

      it('listObjects with prefix should return filtered results', 0, async () => {
        const result: S3Result<S3Object[]> = await client.listObjects(S3TestConfig.BUCKET, '');

        hilog.info(DOMAIN, TAG, `listObjects with prefix result: success=${result.success}, statusCode=${result.statusCode}`);
        expect(result).not().assertUndefined();
        expect(result.success).assertTrue();
      });

      it('getObject should return file content', 0, async () => {
        const result: S3Result<ArrayBuffer> = await client.getObject(S3TestConfig.BUCKET, S3TestConfig.TEST_FILE);
        const fixture: ArrayBuffer = await TestFixtures.loadUnitTestKdbx();

        hilog.info(DOMAIN, TAG, 'getObject result: success=%{public}s, statusCode=%{public}d, message=%{public}s', String(result.success), result.statusCode, result.message);
        expect(result).not().assertUndefined();
        expect(result.success).assertTrue();
        expect(result.data).not().assertUndefined();
        // 内容必须与上传的真实 KDBX 夹具完全一致
        expect(result.data!.byteLength).assertEqual(fixture.byteLength);
        expect(TestFixtures.assertKdbxMagic(result.data!)).assertTrue();
      });

      it('getObject should fail for non-existent key', 0, async () => {
        const result: S3Result<ArrayBuffer> = await client.getObject(S3TestConfig.BUCKET, 'non-existent-key-' + Date.now() + '.txt');

        hilog.info(DOMAIN, TAG, `getObject non-existent result: success=${result.success}, statusCode=${result.statusCode}`);
        expect(result).not().assertUndefined();
        expect(result.success).assertFalse();
        expect(result.statusCode).assertEqual(404);
      });

      it('headObject should return object metadata', 0, async () => {
        const result: S3Result<S3Object> = await client.headObject(S3TestConfig.BUCKET, S3TestConfig.TEST_FILE);
        const fixture: ArrayBuffer = await TestFixtures.loadUnitTestKdbx();

        hilog.info(DOMAIN, TAG, 'headObject result: success=%{public}s, statusCode=%{public}d', String(result.success), result.statusCode);
        expect(result).not().assertUndefined();
        expect(result.success).assertTrue();
        expect(result.data).not().assertUndefined();
        expect(result.data!.key).assertEqual(S3TestConfig.TEST_FILE);
        // 大小必须与上传的真实 KDBX 夹具一致
        expect(result.data!.size).assertEqual(fixture.byteLength);
      });

      it('headObject should fail for non-existent key', 0, async () => {
        const result: S3Result<S3Object> = await client.headObject(S3TestConfig.BUCKET, 'non-existent-' + Date.now() + '.txt');

        expect(result).not().assertUndefined();
        expect(result.success).assertFalse();
      });

      it('testConnection should return success', 0, async () => {
        const result: S3Result<void> = await client.testConnection();

        hilog.info(DOMAIN, TAG, `testConnection result: success=${result.success}, statusCode=${result.statusCode}`);
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
