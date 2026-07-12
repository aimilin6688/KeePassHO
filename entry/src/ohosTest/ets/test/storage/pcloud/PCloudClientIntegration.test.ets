import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { PCloudClient, PCloudError, PCloudMetadata } from '../../../../../main/ets/storage/pcloud/PCloudClient';
import { PCloudTestConfig } from './PCloudTestConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const DOMAIN = 0x0000;
const TAG = 'PCloudClientIntegration';

export default function PCloudClientIntegrationTest() {
  describe('PCloudClientIntegrationTest', () => {

    let client: PCloudClient = new PCloudClient();

    beforeEach(() => {
      client = new PCloudClient();
      client.setAccessToken(PCloudTestConfig.PCLOUD_TEST_ACCESS_TOKEN);
    });

    afterEach(() => {
      if (client) {
        client.close();
      }
    });

    /**
     * userInfo — 最轻量的真实 API 调用
     * 验证 token 有效，返回 uid > 0
     */
    describe('RealUserInfo', () => {
      it('should return user info with valid token', 0, async () => {
        const info: Record<string, Object> = await client.userInfo();
        expect(info).not().assertUndefined();
        const uid = info['uid'];
        expect(uid).not().assertUndefined();
        expect(Number(uid)).assertLarger(0);
      });
    });

    /**
     * listFolder — 列出根目录
     */
    describe('RealListFolder', () => {
      it('should list root folder contents', 0, async () => {
        const items: PCloudMetadata[] = await client.listFolder(PCloudTestConfig.ROOT_FOLDER_ID);
        expect(items).not().assertUndefined();
        expect(Array.isArray(items)).assertTrue();

        if (items.length > 0) {
          const firstItem = items[0];
          expect(firstItem.name).not().assertUndefined();
          expect(typeof firstItem.name).assertEqual('string');
          expect(typeof firstItem.isfolder).assertEqual('boolean');
        }
      });
    });

    /**
     * 完整生命周期：
     * 上传 → 在列表中查找 → stat 验证 → 下载验证内容 → 删除
     */
    describe('RealFileLifecycle', () => {
      const testFileName: string = 'pcloud-test-' + Date.now() + '.txt';
      const testContent: string = 'Hello pCloud test at ' + new Date().toISOString();

      let uploadedFileId: string = '';

      it('should upload a test file', 0, async () => {
        const encoder = new util.TextEncoder();
        const data: Uint8Array = encoder.encodeInto(testContent);
        const result: PCloudMetadata = await client.uploadFile(
          PCloudTestConfig.ROOT_FOLDER_ID,
          testFileName,
          data.buffer as ArrayBuffer
        );
        expect(result).not().assertUndefined();
        expect(result.fileid).not().assertUndefined();
        expect(result.name).assertEqual(testFileName);
        uploadedFileId = 'f' + result.fileid;
      });

      it('should find uploaded file in root listing', 0, async () => {
        const items: PCloudMetadata[] = await client.listFolder(PCloudTestConfig.ROOT_FOLDER_ID);
        const found: PCloudMetadata | undefined = items.find(
          (item: PCloudMetadata): boolean => item.name === testFileName
        );
        expect(found).not().assertUndefined();
        expect(found!.name).assertEqual(testFileName);
        expect(found!.isfolder).assertFalse();
      });

      it('should stat the uploaded file', 0, async () => {
        expect(uploadedFileId.length).assertLarger(0);
        const meta: PCloudMetadata = await client.stat(uploadedFileId);
        expect(meta).not().assertUndefined();
        expect(meta.name).assertEqual(testFileName);
        expect(meta.size).assertLarger(0);
      });

      it('should download the uploaded file with correct content', 0, async () => {
        expect(uploadedFileId.length).assertLarger(0);
        const content: ArrayBuffer = await client.downloadFile(uploadedFileId);
        const bytes: Uint8Array = new Uint8Array(content);
        const decoder = new util.TextDecoder();
        const text: string = decoder.decodeToString(bytes);
        expect(text).assertEqual(testContent);
      });

      it('should delete the uploaded file', 0, async () => {
        expect(uploadedFileId.length).assertLarger(0);
        await client.deleteFile(uploadedFileId);

        // 验证文件已删除
        const afterDelete: PCloudMetadata[] = await client.listFolder(PCloudTestConfig.ROOT_FOLDER_ID);
        const deleted: PCloudMetadata | undefined = afterDelete.find(
          (item: PCloudMetadata): boolean => item.name === testFileName
        );
        expect(deleted).assertUndefined();
      });
    });

    /**
     * 文件夹操作
     */
    describe('RealFolderOperations', () => {
      const testFolderName: string = 'pcloud-test-folder-' + Date.now();
      let createdFolderId: string = '';

      it('should create a folder', 0, async () => {
        const result: PCloudMetadata = await client.createFolder(
          PCloudTestConfig.ROOT_FOLDER_ID,
          testFolderName
        );
        expect(result).not().assertUndefined();
        expect(result.name).assertEqual(testFolderName);
        expect(result.isfolder).assertTrue();
        expect(result.folderid).not().assertUndefined();
        createdFolderId = 'd' + result.folderid;
      });

      it('should rename the folder', 0, async () => {
        expect(createdFolderId.length).assertLarger(0);
        const newName: string = testFolderName + '-renamed';
        await client.renameFile(createdFolderId, newName);

        // 验证文件夹已重命名
        const items: PCloudMetadata[] = await client.listFolder(PCloudTestConfig.ROOT_FOLDER_ID);
        const renamed: PCloudMetadata | undefined = items.find(
          (item: PCloudMetadata): boolean => item.name === newName
        );
        expect(renamed).not().assertUndefined();
        expect(renamed!.name).assertEqual(newName);

        // 清理：重命名回原名，然后删除
        if (renamed && renamed.folderid) {
          await client.renameFile('d' + renamed.folderid, testFolderName);
          await client.deleteFile('d' + renamed.folderid);
        }
      });
    });
  });
}
