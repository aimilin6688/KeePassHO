import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { HuaweiDriveStorage } from '../../../../../main/ets/storage/huawei/HuaweiDriveStorage';
import { HuaweiDriveStorageConfig } from '../../../../../main/ets/storage/huawei/HuaweiDriveConfig';
import { HuaweiDriveFile, HuaweiDriveClient } from '../../../../../main/ets/storage/huawei/HuaweiDriveClient';
import { HuaweiDriveTestConfig, TestHuaweiDriveStorageConfig } from './HuaweiDriveTestConfig';
import { FileInfo, FileType, WriteOption } from '../../../../../main/ets/storage/IFileStorage';
import { StorageError, StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDriveStorageTest';

function makeDriveFile(id: string, size: number, editedTime: string): HuaweiDriveFile {
  return {
    id: id,
    fileName: 'a.kdbx',
    mimeType: 'application/octet-stream',
    size: size,
    createdTime: '2026-10-08T00:00:00Z',
    editedTime: editedTime,
    parentFolder: []
  };
}

export default function HuaweiDriveStorageTest() {
  // 契约层纯函数用例：不依赖真实 API，始终注册
  describe('HuaweiDriveStorageContract', () => {
    it('buildVersion composes id:size:editedTime fingerprint', 0, () => {
      const file: HuaweiDriveFile = makeDriveFile('f1', 123, '2026-10-08T10:00:00Z');
      expect(HuaweiDriveStorage.buildVersion(file)).assertEqual('f1:123:2026-10-08T10:00:00Z');
    });

    it('buildVersion changes when content size or editedTime changes', 0, () => {
      const v1: string = HuaweiDriveStorage.buildVersion(makeDriveFile('f1', 100, 't1'));
      const v2: string = HuaweiDriveStorage.buildVersion(makeDriveFile('f1', 101, 't1'));
      const v3: string = HuaweiDriveStorage.buildVersion(makeDriveFile('f1', 100, 't2'));
      const v4: string = HuaweiDriveStorage.buildVersion(makeDriveFile('f2', 100, 't1'));
      expect(v1 !== v2).assertTrue();
      expect(v1 !== v3).assertTrue();
      expect(v1 !== v4).assertTrue();
    });

    it('supportsVersionFastPath opts in (version fingerprint + conditional write both ready)', 0, () => {
      const storage: HuaweiDriveStorage = new HuaweiDriveStorage();
      expect(storage.supportsVersionFastPath()).assertTrue();
    });
  });

  // 华为云盘为专有云服务，无法本地自建；未配置有效凭证时整套真实 API 用例不注册
  // （诚实跳过，而非用 mock 数据伪造通过，见 docs/storage-regression-test.md）
  if (!HuaweiDriveTestConfig.isRealApiEnabled()) {
    return;
  }
  describe('HuaweiDriveStorage', () => {
    let storage: HuaweiDriveStorage | undefined;

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
        if (!storage) {
          expect(false).assertTrue();
          return;
        }
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
        if (!storage) { expect(false).assertTrue(); return; }
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
        if (!storage) { expect(false).assertTrue(); return; }
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
        if (!storage) { expect(false).assertTrue(); return; }
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
        if (!storage) { expect(false).assertTrue(); return; }
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
        if (!storage) { expect(false).assertTrue(); return; }
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
        if (!storage) { expect(false).assertTrue(); return; }
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
        if (!storage) { expect(false).assertTrue(); return; }
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
        if (!storage) { expect(false).assertTrue(); return; }
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
        if (!storage) { expect(false).assertTrue(); return; }
        await storage.getInfo('non-existent-file-12345.kdbx');
        expect(true).assertFalse(); // 不应该执行到这里
      } catch (error) {
        const err = error as Error;
        hilog.info(DOMAIN, TAG, 'Expected error for non-existent file info: %{public}s', err.message);
        expect(err).not().assertUndefined();
      }
    });

    /**
     * 契约履约：getInfo 透出 version 指纹（id:size:editedTime）
     */
    it('should_expose_version_fingerprint_in_get_info', 0, async () => {
      if (!storage) { expect(false).assertTrue(); return; }
      const encoder: util.TextEncoder = new util.TextEncoder();
      const data: Uint8Array = encoder.encodeInto('version fingerprint probe');
      const testFileName: string = `test-version-${Date.now()}.txt`;
      await storage.write(testFileName, data.buffer as ArrayBuffer);

      const info: FileInfo = await storage.getInfo(testFileName);
      expect(info.version).not().assertNull();
      // 指纹以 fileId 开头（getInfo.path 即 fileId）
      expect(info.version!.startsWith(info.path + ':')).assertTrue();
      // 指纹含 size
      expect(info.version!.includes(`:${info.size}:`)).assertTrue();
    });

    /**
     * 契约履约：条件写（expectedVersion 匹配时成功，过期时抛 VERSION_CONFLICT 且远端不被覆盖）
     */
    it('should_reject_stale_expected_version_and_keep_remote_intact', 0, async () => {
      if (!storage) { expect(false).assertTrue(); return; }
      const encoder: util.TextEncoder = new util.TextEncoder();
      const remoteData: Uint8Array = encoder.encodeInto('remote-truth-content');
      const testFileName: string = `test-conditional-${Date.now()}.txt`;
      await storage.write(testFileName, remoteData.buffer as ArrayBuffer);

      const info: FileInfo = await storage.getInfo(testFileName);
      const currentVersion: string = info.version ?? '';

      // 匹配版本：条件写成功
      const newData: Uint8Array = encoder.encodeInto('local-new-content');
      const matchOption: WriteOption = { expectedVersion: currentVersion };
      await storage.write(testFileName, newData.buffer as ArrayBuffer, matchOption);

      // 过期版本：抛 VERSION_CONFLICT，远端内容保持为上一步写入值
      const staleOption: WriteOption = { expectedVersion: 'stale:1:old' };
      const conflictData: Uint8Array = encoder.encodeInto('must-not-land');
      let conflicted: boolean = false;
      try {
        await storage.write(testFileName, conflictData.buffer as ArrayBuffer, staleOption);
      } catch (error) {
        const storageError = error as StorageError;
        conflicted = storageError.code === StorageErrorCodes.VERSION_CONFLICT;
      }
      expect(conflicted).assertTrue();

      const readBack: ArrayBuffer = await storage.read(testFileName);
      const decoder: util.TextDecoder = new util.TextDecoder();
      const content: string = decoder.decodeToString(new Uint8Array(readBack));
      expect(content).assertEqual('local-new-content');
    });

    /**
     * 契约履约：writeFromFile 条件写（过期版本抛 VERSION_CONFLICT，远端不被覆盖）
     */
    it('should_reject_stale_expected_version_in_writeFromFile', 0, async () => {
      if (!storage) { expect(false).assertTrue(); return; }
      const encoder: util.TextEncoder = new util.TextEncoder();
      const remoteData: Uint8Array = encoder.encodeInto('remote-truth-content-wf');
      const testFileName: string = `test-conditional-wf-${Date.now()}.txt`;
      await storage.write(testFileName, remoteData.buffer as ArrayBuffer);
      const info: FileInfo = await storage.getInfo(testFileName);

      // 本地源文件
      const srcPath = getTestFilesDir() + `/cond-wf-${Date.now()}.tmp`;
      const file = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, encoder.encodeInto('streamed-must-not-land'));
      await fs.close(file.fd);

      let conflicted: boolean = false;
      try {
        await storage.writeFromFile(testFileName, srcPath, { expectedVersion: 'stale:1:old' });
      } catch (error) {
        const storageError = error as StorageError;
        conflicted = storageError.code === StorageErrorCodes.VERSION_CONFLICT;
      }
      try { await fs.unlink(srcPath); } catch { /* best effort */ }
      expect(conflicted).assertTrue();

      const readBack: ArrayBuffer = await storage.read(testFileName);
      const decoder: util.TextDecoder = new util.TextDecoder();
      expect(decoder.decodeToString(new Uint8Array(readBack))).assertEqual('remote-truth-content-wf');
      // 顺带验证 info.version 格式
      expect(info.version).not().assertNull();
    });
  });
}

function getTestFilesDir(): string {
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
}
