import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3SignatureV4 } from '../../../../../main/ets/storage/s3/S3SignatureV4';
import { S3TestConfig } from './S3TestConfig';
import { util } from '@kit.ArkTS';


export default function S3SignatureV4Test() {
  describe('S3SignatureV4Test', () => {

    /**
     * 测试签名对象创建
     */
    describe('Initialization', () => {
      it('should create signer instance', 0, () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        expect(signer).not().assertUndefined();
      });
    });

    /**
     * 测试请求签名
     */
    describe('signRequest', () => {
      it('should generate signed headers for GET request', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'GET',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'test.txt',
          S3TestConfig.PATH_STYLE
        );

        expect(headers).not().assertUndefined();
        expect(headers.has('host')).assertTrue();
        expect(headers.has('x-amz-date')).assertTrue();
        expect(headers.has('x-amz-content-sha256')).assertTrue();
        expect(headers.has('authorization')).assertTrue();
      });

      it('should generate signed headers for PUT request', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const encoder: util.TextEncoder = new util.TextEncoder();
        const payload: Uint8Array = encoder.encodeInto('test content');

        const headers: Map<string, string> = await signer.signRequest(
          'PUT',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'upload.txt',
          S3TestConfig.PATH_STYLE,
          new Map([['content-type', 'application/octet-stream']]),
          payload.buffer as ArrayBuffer
        );

        expect(headers).not().assertUndefined();
        expect(headers.has('authorization')).assertTrue();
        expect(headers.has('content-type')).assertTrue();
      });

      it('should generate signed headers for path-style URL', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'GET',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'path/file.txt',
          true // pathStyle
        );

        expect(headers).not().assertUndefined();
        expect(headers.has('authorization')).assertTrue();
      });

      it('should include correct algorithm in authorization header', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'GET',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'test.txt',
          S3TestConfig.PATH_STYLE
        );

        const authorization: string | undefined = headers.get('authorization');
        expect(authorization).not().assertUndefined();
        expect(authorization!.startsWith('AWS4-HMAC-SHA256')).assertTrue();
      });

      it('should include access key in credential', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'GET',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'test.txt',
          S3TestConfig.PATH_STYLE
        );

        const authorization: string | undefined = headers.get('authorization');
        expect(authorization).not().assertUndefined();
        expect(authorization!.includes(S3TestConfig.ACCESS_KEY_ID)).assertTrue();
      });

      it('should include region in credential scope', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'GET',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'test.txt',
          S3TestConfig.PATH_STYLE
        );

        const authorization: string | undefined = headers.get('authorization');
        expect(authorization).not().assertUndefined();
        expect(authorization!.includes(S3TestConfig.REGION)).assertTrue();
      });

      it('should include service "s3" in credential scope', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'GET',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'test.txt',
          S3TestConfig.PATH_STYLE
        );

        const authorization: string | undefined = headers.get('authorization');
        expect(authorization).not().assertUndefined();
        expect(authorization!.includes('/s3/')).assertTrue();
      });

      it('should handle empty key', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'GET',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          '',
          S3TestConfig.PATH_STYLE
        );

        expect(headers).not().assertUndefined();
        expect(headers.has('authorization')).assertTrue();
      });

      it('should handle special characters in key', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'GET',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'path/with spaces/file.txt',
          S3TestConfig.PATH_STYLE
        );

        expect(headers).not().assertUndefined();
        expect(headers.has('authorization')).assertTrue();
      });

      it('should handle DELETE method', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'DELETE',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'delete-me.txt',
          S3TestConfig.PATH_STYLE
        );

        expect(headers).not().assertUndefined();
        expect(headers.has('authorization')).assertTrue();
      });

      it('should handle HEAD method', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'HEAD',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'check-me.txt',
          S3TestConfig.PATH_STYLE
        );

        expect(headers).not().assertUndefined();
        expect(headers.has('authorization')).assertTrue();
      });
    });

    /**
     * 测试 ListBuckets 签名
     */
    describe('signListBuckets', () => {
      it('should generate signed headers for list buckets', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        // 解析 host
        let host: string = S3TestConfig.ENDPOINT;
        if (host.startsWith('https://')) {
          host = host.substring(8);
        } else if (host.startsWith('http://')) {
          host = host.substring(7);
        }

        const headers: Map<string, string> = await signer.signListBuckets(
          S3TestConfig.ENDPOINT,
          host
        );

        expect(headers).not().assertUndefined();
        expect(headers.has('host')).assertTrue();
        expect(headers.has('x-amz-date')).assertTrue();
        expect(headers.has('x-amz-content-sha256')).assertTrue();
        expect(headers.has('authorization')).assertTrue();
      });

      it('should include correct algorithm in authorization', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        let host: string = S3TestConfig.ENDPOINT;
        if (host.startsWith('https://')) {
          host = host.substring(8);
        }

        const headers: Map<string, string> = await signer.signListBuckets(
          S3TestConfig.ENDPOINT,
          host
        );

        const authorization: string | undefined = headers.get('authorization');
        expect(authorization).not().assertUndefined();
        expect(authorization!.startsWith('AWS4-HMAC-SHA256')).assertTrue();
      });
    });

    /**
     * 测试不同区域的签名
     */
    describe('DifferentRegions', () => {
      it('should work with different regions', 0, async () => {
        const apSigner: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          'ap-northeast-1'
        );
        const headers: Map<string, string> = await apSigner.signRequest(
          'GET',
          'https://s3.ap-northeast-1.amazonaws.com',
          'example-bucket',
          'test.txt',
          false
        );

        const authorization: string | undefined = headers.get('authorization');
        expect(authorization).not().assertUndefined();
        expect(authorization!.includes('ap-northeast-1')).assertTrue();
      });

      it('should work with eu-west-1 region', 0, async () => {
        const euSigner: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          'eu-west-1'
        );
        const headers: Map<string, string> = await euSigner.signRequest(
          'GET',
          'https://s3.eu-west-1.amazonaws.com',
          'example-bucket',
          'test.txt',
          false
        );

        const authorization: string | undefined = headers.get('authorization');
        expect(authorization).not().assertUndefined();
        expect(authorization!.includes('eu-west-1')).assertTrue();
      });
    });

    /**
     * 测试时间戳格式
     */
    describe('TimestampFormat', () => {
      it('should generate valid x-amz-date format', 0, async () => {
        const signer: S3SignatureV4 = new S3SignatureV4(
          S3TestConfig.ACCESS_KEY_ID,
          S3TestConfig.SECRET_ACCESS_KEY,
          S3TestConfig.REGION
        );
        const headers: Map<string, string> = await signer.signRequest(
          'GET',
          S3TestConfig.ENDPOINT,
          S3TestConfig.BUCKET,
          'test.txt',
          false
        );

        const amzDate: string | undefined = headers.get('x-amz-date');
        expect(amzDate).not().assertUndefined();
        // 格式应该是 YYYYMMDDTHHMMSSZ
        expect(amzDate!.length).assertEqual(16);
        expect(amzDate!.includes('T')).assertTrue();
        expect(amzDate!.endsWith('Z')).assertTrue();
      });
    });
  });
}
