import { afterEach, beforeEach, describe, expect, it } from '@ohos/hypium';
import { PCloudStorage } from '../../../../../main/ets/storage/pcloud/PCloudStorage';
import { PCloudStorageConfig } from '../../../../../main/ets/storage/pcloud/PCloudConfig';
import { StorageError, StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { FileType, FileInfo } from '../../../../../main/ets/storage/IFileStorage';
import { StorageType } from '../../../../../main/ets/storage/StorageType';
import { PCloudTestConfig } from './PCloudTestConfig';
import { StorageConfig } from '../../../../../main/ets/storage/StorageConfig';
import { util } from '@kit.ArkTS';

export default function PCloudStorageTest() {
  describe('PCloudStorageTest', () => {

    // ==================== 1. PageConfig ====================
    describe('PageConfig', () => {
      it('should return correct PCloudPageConfig', 0, () => {
        const storage: PCloudStorage = new PCloudStorage();
        const cfg = storage.getPageConfig();
        expect(cfg).not().assertUndefined();
        expect(cfg.icon).not().assertUndefined();
        expect(cfg.title).assertEqual('pCloud');
        expect(cfg.pageUrl).assertEqual('storage/pcloud/PCloudPage');
      });
    });

    // ==================== 2. 初始化 ====================
    describe('Initialization', () => {
      let storage: PCloudStorage;

      afterEach(() => {
        // PCloudStorage 没有 close 方法，不需要清理
      });

      it('should create instance', 0, () => {
        storage = new PCloudStorage();
        expect(storage).not().assertUndefined();
      });

      it('should initialize with config', 0, () => {
        storage = new PCloudStorage();
        storage.init(PCloudTestConfig.createStorageConfig() as StorageConfig);
        const cfg = storage.getPageConfig();
        expect(cfg).not().assertUndefined();
        expect(cfg.storageType).assertEqual(StorageType.PCLOUD);
      });
    });

    // ==================== 3. 未初始化保护 ====================
    describe('UninitializedGuard', () => {
      it('read should throw when not initialized', 0, async () => {
        const storage: PCloudStorage = new PCloudStorage();
        try {
          await storage.read('d0/somefile.txt');
          expect(true).assertFalse();
        } catch (error) {
          const e = error as StorageError;
          expect(e.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
        }
      });

      it('write should throw when not initialized', 0, async () => {
        const storage: PCloudStorage = new PCloudStorage();
        try {
          await storage.write('d0/test.txt', new ArrayBuffer(0));
          expect(true).assertFalse();
        } catch (error) {
          const e = error as StorageError;
          expect(e.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
        }
      });

      it('exists should throw when not initialized', 0, async () => {
        const storage: PCloudStorage = new PCloudStorage();
        try {
          await storage.exists('d0');
          expect(true).assertFalse();
        } catch (error) {
          const e = error as StorageError;
          expect(e.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
        }
      });

      it('getInfo should throw when not initialized', 0, async () => {
        const storage: PCloudStorage = new PCloudStorage();
        try {
          await storage.getInfo('d0');
          expect(true).assertFalse();
        } catch (error) {
          const e = error as StorageError;
          expect(e.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
        }
      });

      it('listDir should throw when not initialized', 0, async () => {
        const storage: PCloudStorage = new PCloudStorage();
        try {
          await storage.listDir('d0');
          expect(true).assertFalse();
        } catch (error) {
          const e = error as StorageError;
          expect(e.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
        }
      });
    });

    // ==================== 4. 写入路径格式校验 ====================
    describe('WritePathValidation', () => {
      let storage: PCloudStorage;

      beforeEach(() => {
        storage = new PCloudStorage();
        storage.init(PCloudTestConfig.createStorageConfig() as StorageConfig);
      });

      it('should reject write path without slash', 0, async () => {
        let caught: boolean = false;
        try {
          await storage.write('invalidpath', new ArrayBuffer(0));
        } catch (error) {
          const e = error as StorageError;
          expect(e.code).assertEqual(StorageErrorCodes.FILE_WRITE_ERROR);
          caught = true;
        }
        expect(caught).assertTrue();
      });
    });

    // ==================== 5. 真实 API: listDir ====================
    describe('RealAPIListDir', () => {
      let storage: PCloudStorage;

      beforeEach(() => {
        storage = new PCloudStorage();
        storage.init(PCloudTestConfig.createStorageConfig() as StorageConfig);
      });

      it('should list root folder contents', 0, async () => {
        const files: FileInfo[] = await storage.listDir(PCloudTestConfig.ROOT_FOLDER_ID);
        expect(files).not().assertUndefined();
        expect(Array.isArray(files)).assertTrue();
      });
    });

    // ==================== 6. 真实 API: exists ====================
    describe('RealAPIExists', () => {
      let storage: PCloudStorage;

      beforeEach(() => {
        storage = new PCloudStorage();
        storage.init(PCloudTestConfig.createStorageConfig() as StorageConfig);
      });

      it('should return true for root folder', 0, async () => {
        const exists: boolean = await storage.exists(PCloudTestConfig.ROOT_FOLDER_ID);
        expect(exists).assertTrue();
      });

      it('should return false for non-existent path', 0, async () => {
        const exists: boolean = await storage.exists('f999999999');
        expect(exists).assertFalse();
      });
    });

    // ==================== 7. 真实 API: getInfo ====================
    describe('RealAPIGetInfo', () => {
      let storage: PCloudStorage;

      beforeEach(() => {
        storage = new PCloudStorage();
        storage.init(PCloudTestConfig.createStorageConfig() as StorageConfig);
      });

      it('should get info for root folder', 0, async () => {
        const info: FileInfo = await storage.getInfo(PCloudTestConfig.ROOT_FOLDER_ID);
        expect(info).not().assertUndefined();
        expect(info.name).not().assertUndefined();
        expect(info.type).assertEqual(FileType.DIR);
      });

      it('should throw for non-existent path', 0, async () => {
        try {
          await storage.getInfo('f999999999');
          expect(true).assertFalse();
        } catch (error) {
          const e = error as StorageError;
          expect(e.code).assertEqual(StorageErrorCodes.FILE_INFO_ERROR);
        }
      });
    });

    // ==================== 8. 真实 API: read ====================
    describe('RealAPIRead', () => {
      let storage: PCloudStorage;

      beforeEach(() => {
        storage = new PCloudStorage();
        storage.init(PCloudTestConfig.createStorageConfig() as StorageConfig);
      });

      it('should throw for non-existent file', 0, async () => {
        try {
          await storage.read('f999999999');
          expect(true).assertFalse();
        } catch (error) {
          const e = error as StorageError;
          expect(e.code).assertEqual(StorageErrorCodes.FILE_READ_ERROR);
        }
      });
    });

    // ==================== 9. 真实 API: write 完整生命周期 ====================
    describe('RealAPIWriteLifecycle', () => {
      let storage: PCloudStorage;

      beforeEach(() => {
        storage = new PCloudStorage();
        storage.init(PCloudTestConfig.createStorageConfig() as StorageConfig);
      });

      it('should write temp file, verify and read back', 0, async () => {
        const encoder: util.TextEncoder = new util.TextEncoder();
        const testName: string = 'pstorage-test-' + Date.now() + '.txt';
        const testContent: string = 'PCloudStorage test write/read at ' + Date.now();
        const testPath: string = PCloudTestConfig.ROOT_FOLDER_ID + '/' + testName;
        const data: Uint8Array = encoder.encodeInto(testContent);

        // 写入
        await storage.write(testPath, data.buffer as ArrayBuffer);

        // 验证存在
        const existsResult: boolean = await storage.exists(testPath);
        expect(existsResult).assertTrue();

        // 读取并验证内容
        const readContent: ArrayBuffer = await storage.read(testPath);
        const bytes: Uint8Array = new Uint8Array(readContent);
        const decoder: util.TextDecoder = new util.TextDecoder();
        const text: string = decoder.decodeToString(bytes);
        expect(text).assertEqual(testContent);
      });
    });

    // ==================== 10. 真实 API: getInfo for file ====================
    describe('RealAPIGetInfoForFile', () => {
      let storage: PCloudStorage;

      beforeEach(() => {
        storage = new PCloudStorage();
        storage.init(PCloudTestConfig.createStorageConfig() as StorageConfig);
      });

      it('should get info for an existing file after write', 0, async () => {
        const encoder: util.TextEncoder = new util.TextEncoder();
        const testName: string = 'pstorage-getinfo-' + Date.now() + '.txt';
        const testContent: string = 'getInfo test content';
        const testPath: string = PCloudTestConfig.ROOT_FOLDER_ID + '/' + testName;
        const data: Uint8Array = encoder.encodeInto(testContent);

        // 先写入一个文件
        await storage.write(testPath, data.buffer as ArrayBuffer);

        // 获取文件信息
        const info: FileInfo = await storage.getInfo(testPath);
        expect(info).not().assertUndefined();
        expect(info.name).assertEqual(testName);
        expect(info.type).assertEqual(FileType.FILE);
        expect(info.size).assertLarger(0);
      });
    });
  });
}
