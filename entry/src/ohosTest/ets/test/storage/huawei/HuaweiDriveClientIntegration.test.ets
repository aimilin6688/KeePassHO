import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { HuaweiDriveClient, HuaweiDriveClientOptions, HuaweiDriveFile, HttpResponse } from '../../../../../main/ets/storage/huawei/HuaweiDriveClient';
import { HuaweiDriveTestConfig } from './HuaweiDriveTestConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDriveClientIntegrationTest';

export default function HuaweiDriveClientIntegrationTest() {
  describe('HuaweiDriveClient Integration', () => {
    let client: HuaweiDriveClient;

    beforeEach(() => {
      const options: HuaweiDriveClientOptions = {
        apiBaseUrl: HuaweiDriveTestConfig.API_BASE_URL,
        accessToken: HuaweiDriveTestConfig.ACCESS_TOKEN,
        timeout: HuaweiDriveTestConfig.TIMEOUT
      };
      client = new HuaweiDriveClient(options);
    });

    afterEach(() => {
      client.close();
    });

    /**
     * 测试验证连接
     */
    it('should_validate_connection', 0, async () => {
      try {
        const response: HttpResponse = await client.valid();

        hilog.info(DOMAIN, TAG, 'Validation response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();
        expect(response.statusCode).assertEqual(200);
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Validation error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试获取根目录信息
     */
    it('should_get_root_directory_info', 0, async () => {
      try {
        const response: HttpResponse = await client.getInfo('root');

        hilog.info(DOMAIN, TAG, 'Root info response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();

        if (response.success && response.body) {
          const jsonStr = String.fromCharCode.apply(null, Array.from(new Uint8Array(response.body)));
          const data = JSON.parse(jsonStr);

          hilog.info(DOMAIN, TAG, 'Root directory: %{public}s', JSON.stringify(data));

          const file: HuaweiDriveFile = client.parseFile(data);

          expect(file.id).not().assertUndefined();
          hilog.info(DOMAIN, TAG, 'Root directory ID: %{public}s', file.id);
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Get root info error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试列出根目录文件
     */
    it('should_list_files_in_root', 0, async () => {
      try {
        const response: HttpResponse = await client.list('root');

        hilog.info(DOMAIN, TAG, 'List files response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();

        if (response.success && response.body) {
          const jsonStr = String.fromCharCode.apply(null, Array.from(new Uint8Array(response.body)));
          const data = JSON.parse(jsonStr);

          const files: HuaweiDriveFile[] = client.parseFileList(data);

          hilog.info(DOMAIN, TAG, 'Found %{public}d files in root directory', files.length);

          expect(Array.isArray(files)).assertTrue();

          // 打印前几个文件
          for (let i = 0; i < Math.min(5, files.length); i++) {
            hilog.info(DOMAIN, TAG, 'File %{public}d: %{public}s, Type: %{public}s, Size: %{public}d',
              i + 1, files[i].fileName, files[i].mimeType, files[i].size);
          }
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'List files error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试上传文件
     */
    it('should_upload_file', 0, async () => {
      try {
        const testContent = 'Test upload content ' + Date.now();
        const testData = new TextEncoder().encode(testContent);

        const response: HttpResponse = await client.upload(
          'root',
          `test-upload-${Date.now()}.txt`,
          testData.buffer as ArrayBuffer
        );

        hilog.info(DOMAIN, TAG, 'Upload response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response).not().assertUndefined();

        if (response.success && response.body) {
          const jsonStr = String.fromCharCode.apply(null, Array.from(new Uint8Array(response.body)));
          const data = JSON.parse(jsonStr);

          hilog.info(DOMAIN, TAG, 'Uploaded file data: %{public}s', jsonStr);

          const file: HuaweiDriveFile = client.parseFile(data);

          expect(file.fileName).not().assertUndefined();
          hilog.info(DOMAIN, TAG, 'Uploaded file ID: %{public}s', file.id);
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Upload error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试下载文件
     */
    it('should_download_file', 0, async () => {
      try {
        // 先上传一个测试文件
        const testContent = 'Test download content ' + Date.now();
        const testData = new TextEncoder().encode(testContent);

        const uploadResponse: HttpResponse = await client.upload(
          'root',
          `test-download-${Date.now()}.txt`,
          testData.buffer as ArrayBuffer
        );

        if (uploadResponse.success && uploadResponse.body) {
          const jsonStr = String.fromCharCode.apply(null, Array.from(new Uint8Array(uploadResponse.body)));
          const data = JSON.parse(jsonStr);
          const uploadedFile: HuaweiDriveFile = client.parseFile(data);

          // 下载文件
          const downloadResponse: HttpResponse = await client.download(uploadedFile.id);

          hilog.info(DOMAIN, TAG, 'Download response: status=%{public}d, success=%{public}s',
            downloadResponse.statusCode, downloadResponse.success.toString());

          expect(downloadResponse).not().assertUndefined();
          expect(downloadResponse.body).not().assertUndefined();

          if (downloadResponse.body) {
            const downloadedContent = new TextDecoder().decode(downloadResponse.body);

            hilog.info(DOMAIN, TAG, 'Downloaded content length: %{public}d', downloadedContent.length);

            expect(downloadedContent).assertEqual(testContent);
          }
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Download error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试获取文件信息
     */
    it('should_get_file_info', 0, async () => {
      try {
        // 先上传一个测试文件
        const testContent = 'Test file info ' + Date.now();
        const testData = new TextEncoder().encode(testContent);

        const uploadResponse: HttpResponse = await client.upload(
          'root',
          `test-info-${Date.now()}.txt`,
          testData.buffer as ArrayBuffer
        );

        if (uploadResponse.success && uploadResponse.body) {
          const jsonStr = String.fromCharCode.apply(null, Array.from(new Uint8Array(uploadResponse.body)));
          const data = JSON.parse(jsonStr);
          const uploadedFile: HuaweiDriveFile = client.parseFile(data);

          // 获取文件信息
          const infoResponse: HttpResponse = await client.getInfo(uploadedFile.id);

          hilog.info(DOMAIN, TAG, 'Get info response: status=%{public}d, success=%{public}s',
            infoResponse.statusCode, infoResponse.success.toString());

          expect(infoResponse).not().assertUndefined();

          if (infoResponse.success && infoResponse.body) {
            const infoJsonStr = String.fromCharCode.apply(null, Array.from(new Uint8Array(infoResponse.body)));
            const infoData = JSON.parse(infoJsonStr);

            const fileInfo: HuaweiDriveFile = client.parseFile(infoData);

            hilog.info(DOMAIN, TAG, 'File info: name=%{public}s, size=%{public}d',
              fileInfo.fileName, fileInfo.size);

            expect(fileInfo.id).assertEqual(uploadedFile.id);
            expect(fileInfo.size).assertLarger(0);
          }
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Get file info error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试错误处理 - 不存在的文件
     */
    it('should_handle_nonexistent_file_error', 0, async () => {
      try {
        const response: HttpResponse = await client.getInfo('nonexistent-file-id-12345');

        hilog.info(DOMAIN, TAG, 'Nonexistent file response: status=%{public}d, success=%{public}s',
          response.statusCode, response.success.toString());

        expect(response.success).assertFalse();
        expect(response.statusCode).assertEqual(404);
      } catch (error) {
        const err = error as Error;
        hilog.info(DOMAIN, TAG, 'Expected error for nonexistent file: %{public}s', err.message);
        expect(err).not().assertUndefined();
      }
    });
  });
}
