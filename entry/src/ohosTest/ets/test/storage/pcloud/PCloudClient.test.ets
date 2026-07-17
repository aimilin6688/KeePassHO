import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { PCloudClient, PCloudError, PCloudMetadata, PCloudLinkResult } from '../../../../../main/ets/storage/pcloud/PCloudClient';
import { PCloudTestConfig } from './PCloudTestConfig';

const DOMAIN = 0x0000;
const TAG = 'PCloudClientTest';

export default function PCloudClientTest() {
  describe('PCloudClientTest', () => {

    /**
     * 测试客户端创建和基本操作
     */
    describe('Lifecycle', () => {
      it('should create client', 0, () => {
        const client: PCloudClient = new PCloudClient();
        expect(client).not().assertUndefined();
        client.close();
      });

      it('should set access token', 0, () => {
        const client: PCloudClient = new PCloudClient();
        client.setAccessToken('test-token');
        expect(client).not().assertUndefined();
        client.close();
      });

      it('should close without throwing', 0, () => {
        const client: PCloudClient = new PCloudClient();
        client.close();
        expect(true).assertTrue();
      });

      it('should allow multiple close calls', 0, () => {
        const client: PCloudClient = new PCloudClient();
        client.close();
        client.close();
        expect(true).assertTrue();
      });
    });

    /**
     * 测试 PCloudError
     */
    describe('PCloudError', () => {
      it('should create error with code and message', 0, () => {
        const error: PCloudError = new PCloudError(1000, 'Need login');
        expect(error.code).assertEqual(1000);
        expect(error.name).assertEqual('PCloudError');
        expect(error.message).assertContain('1000');
        expect(error.message).assertContain('Need login');
      });

      it('should create error with code only', 0, () => {
        const error: PCloudError = new PCloudError(2005);
        expect(error.code).assertEqual(2005);
        expect(error.name).assertEqual('PCloudError');
      });

      it('should inherit from Error', 0, () => {
        const error: PCloudError = new PCloudError(1000);
        expect(error instanceof Error).assertTrue();
      });

      it('should handle zero error code', 0, () => {
        const error: PCloudError = new PCloudError(0);
        expect(error.code).assertEqual(0);
        expect(error.name).assertEqual('PCloudError');
      });

      it('should handle negative error code', 0, () => {
        const error: PCloudError = new PCloudError(-1, 'custom error');
        expect(error.code).assertEqual(-1);
        expect(error.message).assertContain('custom error');
      });
    });

    /**
     * 测试所有公共 API 方法在 session 关闭后的行为
     * 每个方法在 session 关闭时应抛出 "PCloudClient session is closed" 错误
     */
    describe('SessionClosed', () => {
      let client: PCloudClient;

      beforeEach(() => {
        client = new PCloudClient();
        client.setAccessToken('test-token');
        client.close(); // session 设为 null
      });

      it('listFolder should throw when session closed', 0, async () => {
        let caught: boolean = false;
        try {
          await client.listFolder('d0');
        } catch (error) {
          caught = true;
        }
        expect(caught).assertTrue();
      });

      it('stat should throw when session closed', 0, async () => {
        let caught: boolean = false;
        try {
          await client.stat('f0');
        } catch (error) {
          caught = true;
        }
        expect(caught).assertTrue();
      });

      it('getFileLink should throw when session closed', 0, async () => {
        let caught: boolean = false;
        try {
          await client.getFileLink('f0');
        } catch (error) {
          caught = true;
        }
        expect(caught).assertTrue();
      });

      it('downloadFile should throw when session closed', 0, async () => {
        let caught: boolean = false;
        try {
          await client.downloadFile('f0');
        } catch (error) {
          caught = true;
        }
        expect(caught).assertTrue();
      });

      it('uploadFile should throw when session closed', 0, async () => {
        let caught: boolean = false;
        try {
          await client.uploadFile('d0', 'test.txt', new ArrayBuffer(0));
        } catch (error) {
          caught = true;
        }
        expect(caught).assertTrue();
      });

      it('createFolder should throw when session closed', 0, async () => {
        let caught: boolean = false;
        try {
          await client.createFolder('d0', 'NewFolder');
        } catch (error) {
          caught = true;
        }
        expect(caught).assertTrue();
      });

      it('deleteFile should throw when session closed', 0, async () => {
        let caught: boolean = false;
        try {
          await client.deleteFile('f0');
        } catch (error) {
          caught = true;
        }
        expect(caught).assertTrue();
      });

      it('renameFile should throw when session closed', 0, async () => {
        let caught: boolean = false;
        try {
          await client.renameFile('f0', 'new-name.txt');
        } catch (error) {
          caught = true;
        }
        expect(caught).assertTrue();
      });

      it('userInfo should throw when session closed', 0, async () => {
        let caught: boolean = false;
        try {
          await client.userInfo();
        } catch (error) {
          caught = true;
        }
        expect(caught).assertTrue();
      });
    });
  });
}
