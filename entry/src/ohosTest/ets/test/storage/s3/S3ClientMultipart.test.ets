import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3Client, S3ClientOptionsImpl } from '../../../../../main/ets/storage/s3/S3Client';
import { S3TestConfig } from './S3TestConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'S3ClientMultipartTest';

export default function S3ClientMultipartTest() {
  describe('S3ClientMultipartTest', () => {
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
     * 测试客户端初始化
     */
    it('should_create_client_successfully', 0, () => {
      const isCreated = client !== null && client !== undefined;
      expect(isCreated).assertTrue();
      hilog.info(DOMAIN, TAG, 'S3Client created successfully');
    });

    /**
     * 测试配置正确性
     */
    it('should_have_correct_config', 0, () => {
      expect(S3TestConfig.ENDPOINT).assertContain('https://');
      expect(S3TestConfig.REGION).assertEqual('ap-beijing');
      expect(S3TestConfig.BUCKET.length > 0).assertTrue();
      hilog.info(DOMAIN, TAG, 'S3TestConfig validated successfully');
    });
  });
}
