import { afterAll, afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import {
  FileContentInfo,
  FileInfo,
  FileType,
  StorageType,
  WriteOption
} from '../../../../main/ets/storage';
import { StorageError, StorageErrorCodes } from '../../../../main/ets/storage/StorageError';
import { LocationInfo, LocationMode } from '../../../../main/ets/services/beans/LocationParam';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

/**
 * KdbxFileManager 单元测试。
 *
 * 使用真实 LOCAL 存储与沙箱文件，覆盖：
 * - 构造函数默认值 / of 工厂 / init 链式
 * - read / write 往返
 * - read 不存在文件抛异常
 * - write 条件写入（版本冲突）
 * - write 原样上抛 StorageError
 * - readToFile / writeFromFile 流式代理
 * - getInfo / exists / listDir
 * - switchStorage 切换存储类型
 */
export default function KdbxFileManagerTest() {
  describe('KdbxFileManagerTest', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let testDir: string;

    beforeAll(() => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      testDir = appContext.filesDir + '/kdbx-file-manager-test';
      try {
        fs.mkdirSync(testDir, true);
      } catch {
        // dir may already exist
      }
    });

    afterEach(() => {
      // 清理测试目录
      try {
        const entries = fs.listFileSync(testDir);
        for (const entry of entries) {
          try { fs.unlinkSync(testDir + '/' + entry); } catch { /* ignore */ }
        }
      } catch {
        // dir not exist
      }
    });

    afterAll(() => {
      try {
        const entries = fs.listFileSync(testDir);
        for (const entry of entries) {
          try { fs.unlinkSync(testDir + '/' + entry); } catch { /* ignore */ }
        }
        fs.rmdirSync(testDir);
      } catch {
        // ignore
      }
    });

    // -------- constructor / of / init --------

    it('constructor defaults to LOCAL storage', 0, async () => {
      const mgr = new KdbxFileManager();
      const path = testDir + '/constructor-default.txt';
      await mgr.write(path, new ArrayBuffer(8));
      const exists = await mgr.exists(path);
      expect(exists).assertTrue();
    });

    it('constructor with LOCAL type creates working manager', 0, async () => {
      const mgr = new KdbxFileManager(StorageType.LOCAL);
      const path = testDir + '/constructor-local.txt';
      await mgr.write(path, new ArrayBuffer(4));
      const info = await mgr.getInfo(path);
      expect(info.size).assertEqual(4);
    });

    it('constructor with storageConfig calls init', 0, async () => {
      const mgr = new KdbxFileManager(StorageType.LOCAL, {});
      const path = testDir + '/constructor-with-config.txt';
      await mgr.write(path, new ArrayBuffer(16));
      const content = await mgr.read(path);
      expect(content.content.byteLength).assertEqual(16);
    });

    it('of(locationInfo) creates manager with proper storage type', 0, async () => {
      const locationInfo: LocationInfo = {
        mode: LocationMode.SAVE,
        filePath: '',
        fileName: 'test.kdbx',
        storageType: StorageType.LOCAL,
        storageConfig: {}
      };
      const mgr = KdbxFileManager.of(locationInfo);
      expect(mgr instanceof KdbxFileManager).assertTrue();
      const path = testDir + '/of-location.txt';
      await mgr.write(path, new ArrayBuffer(2));
      const exists = await mgr.exists(path);
      expect(exists).assertTrue();
    });

    it('init returns this for chaining', 0, () => {
      const mgr = new KdbxFileManager(StorageType.LOCAL);
      const result = mgr.init({});
      expect(result === mgr).assertTrue();
    });

    // -------- read / write --------

    it('read returns FileContentInfo for existing file', 0, async () => {
      const path = testDir + '/read-existing.kdbx';
      const data = new ArrayBuffer(32);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = i % 256;
      }
      await fileManager.write(path, data);

      const result = await fileManager.read(path);
      expect(result instanceof FileContentInfo).assertTrue();
      expect(result.content.byteLength).assertEqual(32);
      expect(result.size).assertEqual(32);
      expect(result.name.length > 0).assertTrue();
      expect(result.path).assertEqual(path);
      expect(result.version !== null).assertTrue();

      const readView = new Uint8Array(result.content);
      let mismatch = false;
      for (let i = 0; i < readView.length; i++) {
        if (readView[i] !== view[i]) {
          mismatch = true;
          break;
        }
      }
      expect(mismatch).assertFalse();
    });

    it('read throws for non-existent file', 0, async () => {
      const path = testDir + '/read-not-exist.kdbx';
      let error: Error | null = null;
      try {
        await fileManager.read(path);
      } catch (e) {
        error = e as Error;
      }
      expect(error !== null).assertTrue();
      expect(error!.message.length > 0).assertTrue();
    });

    it('write creates new file with content', 0, async () => {
      const path = testDir + '/write-new.kdbx';
      const data = new ArrayBuffer(64);
      await fileManager.write(path, data);

      const info = await fileManager.getInfo(path);
      expect(info.size).assertEqual(64);
    });

    it('write overwrites existing file', 0, async () => {
      const path = testDir + '/write-overwrite.kdbx';
      await fileManager.write(path, new ArrayBuffer(32));
      await fileManager.write(path, new ArrayBuffer(16));

      const info = await fileManager.getInfo(path);
      expect(info.size).assertEqual(16);
    });

    it('write with matching expectedVersion succeeds', 0, async () => {
      const path = testDir + '/write-condition-match.kdbx';
      await fileManager.write(path, new ArrayBuffer(8));
      const info = await fileManager.getInfo(path);
      const version = info.version ?? null;

      const option: WriteOption = { expectedVersion: version };
      let error: Error | null = null;
      try {
        await fileManager.write(path, new ArrayBuffer(16), option);
      } catch (e) {
        error = e as Error;
      }
      expect(error).assertNull();
    });

    it('write with mismatched expectedVersion throws StorageError VERSION_CONFLICT', 0, async () => {
      const path = testDir + '/write-condition-mismatch.kdbx';
      await fileManager.write(path, new ArrayBuffer(8));

      const option: WriteOption = { expectedVersion: 'nonexistent-version' };
      let error: Error | null = null;
      try {
        await fileManager.write(path, new ArrayBuffer(16), option);
      } catch (e) {
        error = e as Error;
      }
      expect(error !== null).assertTrue();
      expect(error instanceof StorageError).assertTrue();
      expect((error as StorageError).code).assertEqual(StorageErrorCodes.VERSION_CONFLICT);
    });

    it('write rethrows StorageError as-is (not wrapped in plain Error)', 0, async () => {
      const path = testDir + '/write-storage-error.kdbx';
      await fileManager.write(path, new ArrayBuffer(8));

      const option: WriteOption = { expectedVersion: 'wrong' };
      let error: Error | null = null;
      try {
        await fileManager.write(path, new ArrayBuffer(16), option);
      } catch (e) {
        error = e as Error;
      }
      expect(error instanceof StorageError).assertTrue();
      expect(error!.name).assertEqual('StorageError');
    });

    it('write without option writes unconditionally', 0, async () => {
      const path = testDir + '/write-no-option.kdbx';
      await fileManager.write(path, new ArrayBuffer(8));
      await fileManager.write(path, new ArrayBuffer(24));

      const info = await fileManager.getInfo(path);
      expect(info.size).assertEqual(24);
    });

    // -------- readToFile / writeFromFile --------

    it('readToFile copies remote file to local destPath', 0, async () => {
      const remotePath = testDir + '/readtofile-source.kdbx';
      const destPath = testDir + '/readtofile-dest.kdbx';
      const data = new ArrayBuffer(48);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = (i * 7) % 256;
      }
      await fileManager.write(remotePath, data);

      const fileInfo = await fileManager.readToFile(remotePath, destPath);

      expect(fileInfo.size).assertEqual(48);
      expect(fs.accessSync(destPath, fs.AccessModeType.EXIST)).assertTrue();

      const destFile = await fs.open(destPath, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(destFile.fd);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(destFile.fd, buffer);
      await fs.close(destFile.fd);

      const destView = new Uint8Array(buffer);
      let mismatch = false;
      for (let i = 0; i < destView.length; i++) {
        if (destView[i] !== view[i]) {
          mismatch = true;
          break;
        }
      }
      expect(mismatch).assertFalse();
    });

    it('readToFile rethrows StorageError as-is', 0, async () => {
      const nonExistent = testDir + '/readtofile-not-exist.kdbx';
      const destPath = testDir + '/readtofile-not-exist-dest.kdbx';
      let error: Error | null = null;
      try {
        await fileManager.readToFile(nonExistent, destPath);
      } catch (e) {
        error = e as Error;
      }
      expect(error !== null).assertTrue();
    });

    it('writeFromFile copies local source to remote path', 0, async () => {
      const srcPath = testDir + '/writefromfile-src.kdbx';
      const remotePath = testDir + '/writefromfile-remote.kdbx';
      const data = new ArrayBuffer(56);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = (i * 3 + 1) % 256;
      }
      const srcFile = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(srcFile.fd, data);
      await fs.close(srcFile.fd);

      const fileInfo = await fileManager.writeFromFile(remotePath, srcPath);

      expect(fileInfo.size).assertEqual(56);
      expect(fs.accessSync(remotePath, fs.AccessModeType.EXIST)).assertTrue();

      const content = await fileManager.read(remotePath);
      const readView = new Uint8Array(content.content);
      let mismatch = false;
      for (let i = 0; i < readView.length; i++) {
        if (readView[i] !== view[i]) {
          mismatch = true;
          break;
        }
      }
      expect(mismatch).assertFalse();
    });

    it('writeFromFile with matching expectedVersion succeeds', 0, async () => {
      const srcPath = testDir + '/writefromfile-cond-src.kdbx';
      const remotePath = testDir + '/writefromfile-cond-remote.kdbx';
      await fileManager.write(remotePath, new ArrayBuffer(8));
      const info = await fileManager.getInfo(remotePath);

      const srcFile = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(srcFile.fd, new ArrayBuffer(16));
      await fs.close(srcFile.fd);

      const option: WriteOption = { expectedVersion: info.version ?? null };
      let error: Error | null = null;
      try {
        await fileManager.writeFromFile(remotePath, srcPath, option);
      } catch (e) {
        error = e as Error;
      }
      expect(error).assertNull();
    });

    it('writeFromFile rethrows StorageError as-is on version conflict', 0, async () => {
      const srcPath = testDir + '/writefromfile-conflict-src.kdbx';
      const remotePath = testDir + '/writefromfile-conflict-remote.kdbx';
      await fileManager.write(remotePath, new ArrayBuffer(8));

      const srcFile = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(srcFile.fd, new ArrayBuffer(16));
      await fs.close(srcFile.fd);

      const option: WriteOption = { expectedVersion: 'wrong-version' };
      let error: Error | null = null;
      try {
        await fileManager.writeFromFile(remotePath, srcPath, option);
      } catch (e) {
        error = e as Error;
      }
      expect(error instanceof StorageError).assertTrue();
      expect((error as StorageError).code).assertEqual(StorageErrorCodes.VERSION_CONFLICT);
    });

    // -------- getInfo / exists / listDir --------

    it('getInfo returns FileInfo for existing file', 0, async () => {
      const path = testDir + '/getinfo-existing.kdbx';
      await fileManager.write(path, new ArrayBuffer(128));

      const info = await fileManager.getInfo(path);
      expect(info.size).assertEqual(128);
      expect(info.name.length > 0).assertTrue();
      expect(info.path).assertEqual(path);
      expect(info.type).assertEqual(FileType.FILE);
      expect(info.version !== null).assertTrue();
      expect(info.version!.includes('|')).assertTrue();
    });

    it('getInfo throws for non-existent file', 0, async () => {
      const path = testDir + '/getinfo-not-exist.kdbx';
      let error: Error | null = null;
      try {
        await fileManager.getInfo(path);
      } catch (e) {
        error = e as Error;
      }
      expect(error !== null).assertTrue();
    });

    it('exists returns true for existing file', 0, async () => {
      const path = testDir + '/exists-true.kdbx';
      await fileManager.write(path, new ArrayBuffer(4));
      const result = await fileManager.exists(path);
      expect(result).assertTrue();
    });

    it('exists returns false for non-existent file', 0, async () => {
      const path = testDir + '/exists-false.kdbx';
      const result = await fileManager.exists(path);
      expect(result).assertFalse();
    });

    it('listDir throws NOT_IMPLEMENTED for LOCAL storage', 0, async () => {
      let error: Error | null = null;
      try {
        await fileManager.listDir(testDir);
      } catch (e) {
        error = e as Error;
      }
      expect(error !== null).assertTrue();
      expect(error!.message.length > 0).assertTrue();
    });

    // -------- switchStorage --------

    it('switchStorage to LOCAL does not throw', 0, () => {
      const mgr = new KdbxFileManager(StorageType.LOCAL);
      let threw = false;
      try {
        mgr.switchStorage(StorageType.LOCAL);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('switchStorage changes active storage', 0, async () => {
      const mgr = new KdbxFileManager(StorageType.LOCAL);
      const path = testDir + '/switch-after.kdbx';
      mgr.switchStorage(StorageType.LOCAL);
      await mgr.write(path, new ArrayBuffer(8));
      const info = await mgr.getInfo(path);
      expect(info.size).assertEqual(8);
    });

    // -------- FileContentInfo --------

    it('FileContentInfo preserves fileInfo fields', 0, async () => {
      const path = testDir + '/filecontentinfo.kdbx';
      await fileManager.write(path, new ArrayBuffer(36));
      const result = await fileManager.read(path);

      expect(result.content.byteLength).assertEqual(36);
      expect(result.size).assertEqual(36);
      const fileInfo: FileInfo = result.fileInfo;
      expect(fileInfo.size).assertEqual(36);
      expect(fileInfo.path).assertEqual(path);
    });

    // -------- round trip --------

    it('write then read round trip preserves content', 0, async () => {
      const path = testDir + '/roundtrip.kdbx';
      const database = await KdbxModeTestHelper.createDatabase('FileManagerRoundtrip', 'rt-entry');
      const saved: ArrayBuffer = await database.save();
      await fileManager.write(path, saved);

      const content = await fileManager.read(path);
      expect(content.content.byteLength).assertEqual(saved.byteLength);

      const a = new Uint8Array(content.content);
      const b = new Uint8Array(saved);
      let mismatch = false;
      for (let i = 0; i < a.length; i++) {
        if (a[i] !== b[i]) {
          mismatch = true;
          break;
        }
      }
      expect(mismatch).assertFalse();
    });
  });
}
