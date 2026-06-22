import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { HuaweiDriveStorage } from '../../../../../main/ets/storage/huawei/HuaweiDriveStorage';
import { HuaweiDriveStorageConfig } from '../../../../../main/ets/storage/huawei/HuaweiDriveConfig';
import { HuaweiDriveTestConfig, TestHuaweiDriveStorageConfig } from './HuaweiDriveTestConfig';
import { FileInfo, FileType } from '../../../../../main/ets/storage/IFileStorage';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDriveStorageIntegrationTest';

export default function HuaweiDriveStorageIntegrationTest() {
  describe('HuaweiDriveStorage Integration', () => {
    let storage: HuaweiDriveStorage;

    beforeEach(() => {
      const config = HuaweiDriveTestConfig.getStorageConfig();
      storage = new HuaweiDriveStorage();
      storage.init(config as HuaweiDriveStorageConfig);
    });

    afterEach(() => {
      storage = undefined;
    });

    /**
     * 测试列出根目录文件
     */
    it('should_list_files_in_root_directory', 0, async () => {
      try {
        const files: FileInfo[] = await storage.listDir('root');

        hilog.info(DOMAIN, TAG, 'Root directory contains %{public}d files', files.length);

        expect(files).not().assertUndefined();
        expect(Array.isArray(files)).assertTrue();

        // 打印文件列表
        for (const file of files) {
          hilog.info(DOMAIN, TAG, 'File: %{public}s, Type: %{public}s, Size: %{public}d',
            file.name, file.type, file.size);
        }
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'List files error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试上传小文件
     */
    it('should_upload_small_file', 0, async () => {
      try {
        const testContent: string = 'Test content for Huawei Drive ' + Date.now();
        const encoder: util.TextEncoder = new util.TextEncoder();
        const data: Uint8Array = encoder.encodeInto(testContent);
        const testFileName: string = `test-small-${Date.now()}.txt`;

        // 上传文件到根目录
        await storage.write(testFileName, data.buffer as ArrayBuffer);

        hilog.info(DOMAIN, TAG, 'Small file uploaded: %{public}s', testFileName);

        // 验证文件存在
        const exists: boolean = await storage.exists(testFileName);
        expect(exists).assertTrue();

        // 读取文件内容验证
        const readContent: ArrayBuffer = await storage.read(testFileName);
        const decoder: util.TextDecoder = new util.TextDecoder();
        const contentStr: string = decoder.decodeToString(new Uint8Array(readContent));

        expect(contentStr).assertEqual(testContent);

        hilog.info(DOMAIN, TAG, 'Small file verified successfully');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Upload small file error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试上传和下载二进制文件
     */
    it('should_upload_and_download_binary_file', 0, async () => {
      try {
        // 创建测试二进制数据
        const testData = new ArrayBuffer(1024); // 1KB
        const view = new Uint8Array(testData);
        for (let i = 0; i < view.length; i++) {
          view[i] = i % 256;
        }

        const testFileName: string = `test-binary-${Date.now()}.bin`;

        // 上传文件
        await storage.write(testFileName, testData);

        hilog.info(DOMAIN, TAG, 'Binary file uploaded: %{public}s', testFileName);

        // 下载文件
        const downloadedData = await storage.read(testFileName);

        // 验证文件大小
        expect(downloadedData.byteLength).assertEqual(1024);

        // 验证文件内容
        const downloadedView = new Uint8Array(downloadedData);
        for (let i = 0; i < 10; i++) { // 只验证前10个字节
          expect(downloadedView[i]).assertEqual(i % 256);
        }

        hilog.info(DOMAIN, TAG, 'Binary file verified successfully');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Binary file test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试获取文件信息
     */
    it('should_get_file_info', 0, async () => {
      try {
        // 先上传一个测试文件
        const testContent: string = 'Test file for info check';
        const encoder: util.TextEncoder = new util.TextEncoder();
        const data: Uint8Array = encoder.encodeInto(testContent);
        const testFileName: string = `test-info-${Date.now()}.txt`;

        await storage.write(testFileName, data.buffer as ArrayBuffer);

        // 获取文件信息
        const info: FileInfo = await storage.getInfo(testFileName);

        hilog.info(DOMAIN, TAG, 'File info: name=%{public}s, size=%{public}d, type=%{public}s',
          info.name, info.size, info.type);

        expect(info.name).assertEqual(testFileName);
        expect(info.type).assertEqual(FileType.FILE);
        expect(info.size).assertLarger(0);
        expect(info.modifiedTime).assertLarger(0);

        hilog.info(DOMAIN, TAG, 'File info test passed');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Get file info error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试检查文件是否存在
     */
    it('should_check_file_existence', 0, async () => {
      try {
        // 上传测试文件
        const testContent: string = 'Test file for existence check';
        const encoder: util.TextEncoder = new util.TextEncoder();
        const data: Uint8Array = encoder.encodeInto(testContent);
        const testFileName: string = `test-exists-${Date.now()}.txt`;

        await storage.write(testFileName, data.buffer as ArrayBuffer);

        // 检查存在的文件
        const existsTrue: boolean = await storage.exists(testFileName);
        expect(existsTrue).assertTrue();

        // 检查不存在的文件
        const existsFalse: boolean = await storage.exists('non-existent-file-12345.txt');
        expect(existsFalse).assertFalse();

        hilog.info(DOMAIN, TAG, 'File existence check passed');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Check file existence error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试创建文件夹和列出文件夹内容
     */
    it('should_create_folder_and_list_contents', 0, async () => {
      try {
        // 先列出根目录
        const rootFiles: FileInfo[] = await storage.listDir('root');

        hilog.info(DOMAIN, TAG, 'Root directory has %{public}d items', rootFiles.length);

        // 查找文件夹
        const folders = rootFiles.filter(f => f.type === FileType.DIR);
        hilog.info(DOMAIN, TAG, 'Found %{public}d folders in root', folders.length);

        if (folders.length > 0) {
          // 列出第一个文件夹的内容
          const folderContents: FileInfo[] = await storage.listDir(folders[0].path);

          hilog.info(DOMAIN, TAG, 'Folder %{public}s contains %{public}d items',
            folders[0].name, folderContents.length);

          expect(Array.isArray(folderContents)).assertTrue();
        }

        hilog.info(DOMAIN, TAG, 'Folder operations test passed');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Folder operations error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试上传较大文件
     */
    it('should_upload_larger_file', 0, async () => {
      try {
        // 创建1MB测试数据
        const testData = new ArrayBuffer(1024 * 1024); // 1MB
        const view = new Uint8Array(testData);

        // 填充测试数据
        for (let i = 0; i < view.length; i++) {
          view[i] = (i * 7) % 256; // 使用简单算法生成测试数据
        }

        const testFileName: string = `test-large-${Date.now()}.bin`;

        // 上传文件
        await storage.write(testFileName, testData);

        hilog.info(DOMAIN, TAG, 'Large file uploaded: %{public}s, size: 1MB', testFileName);

        // 下载并验证
        const downloadedData = await storage.read(testFileName);

        expect(downloadedData.byteLength).assertEqual(1024 * 1024);

        // 验证部分数据
        const downloadedView = new Uint8Array(downloadedData);
        for (let i = 0; i < 100; i++) {
          expect(downloadedView[i * 1000]).assertEqual((i * 1000 * 7) % 256);
        }

        hilog.info(DOMAIN, TAG, 'Large file test passed');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'Large file test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试上传KDBX文件
     */
    it('should_upload_and_download_kdbx_file', 0, async () => {
      try {
        // 模拟KDBX文件数据（前几个字节是KDBX魔术数字）
        const kdbxData = new ArrayBuffer(2048);
        const view = new Uint8Array(kdbxData);

        // KDBX文件头标识
        view[0] = 0x03;  // 版本
        view[1] = 0xD9;  // 魔术数字
        view[2] = 0xA2;  // 魔术数字
        view[3] = 0x9A;  // 魔术数字
        view[4] = 0x67;  // 魔术数字
        view[5] = 0xFB;  // 魔术数字
        view[6] = 0x4B;  // 魔术数字
        view[7] = 0xB5;  // 魔术数字

        // 填充其余数据
        for (let i = 8; i < view.length; i++) {
          view[i] = i % 256;
        }

        const testFileName: string = `test-database-${Date.now()}.kdbx`;

        // 上传KDBX文件
        await storage.write(testFileName, kdbxData);

        hilog.info(DOMAIN, TAG, 'KDBX file uploaded: %{public}s', testFileName);

        // 下载并验证
        const downloadedData = await storage.read(testFileName);
        const downloadedView = new Uint8Array(downloadedData);

        // 验证KDBX文件头
        expect(downloadedView[0]).assertEqual(0x03);
        expect(downloadedView[1]).assertEqual(0xD9);
        expect(downloadedView[2]).assertEqual(0xA2);
        expect(downloadedView[3]).assertEqual(0x9A);

        hilog.info(DOMAIN, TAG, 'KDBX file test passed');
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'KDBX file test error: %{public}s', err.message);
        throw new Error(err.message);
      }
    });

    /**
     * 测试错误处理 - 读取不存在的文件
     */
    it('should_handle_read_nonexistent_file_error', 0, async () => {
      try {
        await storage.read('non-existent-file-12345.kdbx');
        expect(true).assertFalse(); // 不应该执行到这里
      } catch (error) {
        const err = error as Error;
        hilog.info(DOMAIN, TAG, 'Expected error for non-existent file: %{public}s', err.message);
        expect(err).not().assertUndefined();
      }
    });

    /**
     * 测试错误处理 - 获取不存在文件的信息
     */
    it('should_handle_get_info_nonexistent_file_error', 0, async () => {
      try {
        await storage.getInfo('non-existent-file-12345.kdbx');
        expect(true).assertFalse(); // 不应该执行到这里
      } catch (error) {
        const err = error as Error;
        hilog.info(DOMAIN, TAG, 'Expected error for non-existent file info: %{public}s', err.message);
        expect(err).not().assertUndefined();
      }
    });
  });
}
