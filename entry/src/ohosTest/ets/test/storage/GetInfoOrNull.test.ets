import { beforeAll, afterAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CacheStorage } from '../../../../main/ets/storage/cache/CacheStorage';
import { LocalFileStorage } from '../../../../main/ets/storage/local/LocalFileStorage';
import { CacheConstants } from '../../../../main/ets/storage/cache/CacheConstants';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { IFileStorage, FileInfo, FileInfoImpl, FileType } from '../../../../main/ets/storage/IFileStorage';
import { StorageConfig } from '../../../../main/ets/storage/StorageConfig';
import { StorageType } from '../../../../main/ets/storage/StorageType';
import { WriteOption } from '../../../../main/ets/storage/IFileStorage';
import { WebDAVStorage } from '../../../../main/ets/storage/webdav/WebDAVStorage';
import { StorageError, StorageErrorCodes } from '../../../../main/ets/storage/StorageError';
import { FileStorageFactory } from '../../../../main/ets/storage/FileStorageFactory';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { LoadDispatchCache } from '../../../../main/ets/services/kdbx/LoadDispatchCache';
import { RecentFilesService } from '../../../../main/ets/services/RecentFilesService';

/**
 * 探测桩存储：getInfoOrNull 由 getInfo 派生（FILE_INFO_ERROR 映射为 null，其余上抛）
 */
class StubNoProbeStorage implements IFileStorage {
  public existPath: string = '/stub-exist.kdbx';
  public stubSize: number = 123;
  public throwOnGetInfo: boolean = false;

  getPageConfig() {
    return new LocalFileStorage().getPageConfig();
  }

  init(config: StorageConfig): void {
  }

  read(path: string): Promise<ArrayBuffer> {
    return Promise.resolve(new ArrayBuffer(0));
  }

  readToFile(path: string, destPath: string): Promise<FileInfo> {
    const info = new FileInfoImpl();
    info.path = path;
    return Promise.resolve(info);
  }

  write(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void> {
    return Promise.resolve();
  }

  writeFromFile(path: string, srcPath: string, option?: WriteOption): Promise<FileInfo> {
    const info = new FileInfoImpl();
    info.path = path;
    return Promise.resolve(info);
  }

  exists(path: string): Promise<boolean> {
    return Promise.resolve(path === this.existPath);
  }

  getInfo(path: string): Promise<FileInfo> {
    if (this.throwOnGetInfo) {
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, 'remote indeterminate'));
    }
    if (path !== this.existPath) {
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_INFO_ERROR, 'File not found: ' + path));
    }
    const info = new FileInfoImpl();
    info.name = 'stub.kdbx';
    info.size = this.stubSize;
    info.modifiedTime = 1;
    info.path = path;
    info.type = FileType.FILE;
    info.version = null;
    return Promise.resolve(info);
  }

  async getInfoOrNull(path: string): Promise<FileInfo | null> {
    try {
      return await this.getInfo(path);
    } catch (error) {
      const err = error as StorageError;
      if (err.code === StorageErrorCodes.FILE_INFO_ERROR) {
        return null;
      }
      throw err;
    }
  }

  listDir(path: string): Promise<FileInfo[]> {
    return Promise.resolve([]);
  }
}

/**
 * 实现独立 getInfoOrNull 探测的桩存储：验证装饰器透传
 */
class StubProbeCapableStorage extends StubNoProbeStorage {
  public missingPath: string = '/stub-missing.kdbx';

  getInfoOrNull(path: string): Promise<FileInfo | null> {
    if (path === this.missingPath) {
      return Promise.resolve(null);
    }
    return this.getInfo(path);
  }
}

async function writeTestFile(path: string, size: number): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    await fs.write(file.fd, new ArrayBuffer(size));
  } finally {
    await fs.close(file.fd);
  }
}

/**
 * getInfoOrNull（存在性 + 大小一次返回）单元测试：
 * - LOCAL 真实文件：info / null / exists 委托
 * - WebDAV 未初始化：无法判定错误上抛（不映射为 null/false）
 * - KdbxFileManager 存储探测直连
 * - CacheStorage 策略镜像（透传 / 回退 / 远端失败回缓存 / 仅缓存命中与 miss）
 * - RecentFilesService.probeFileInfo 大小写入 LoadDispatchCache
 */
export default function GetInfoOrNullTest() {
  describe('GetInfoOrNullTest', () => {
    let appContext: common.Context;
    let testDir: string;

    beforeAll(() => {
      appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      testDir = appContext.filesDir + '/get-info-or-null-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
      const cacheDir = CacheConstants.getCacheDir();
      if (!fs.accessSync(cacheDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(cacheDir, true);
      }
      CacheConstants.setWorkerCachePolicy(true, false, false);
    });

    afterAll(() => {
      CacheConstants.setWorkerCachePolicy(true, false, false);
    });

    // -------- LOCAL（真实存储） --------

    it('LOCAL getInfoOrNull returns size for existing file', 0, async () => {
      const mgr = new KdbxFileManager(StorageType.LOCAL);
      const path = testDir + '/local-exist.kdbx';
      await writeTestFile(path, 1234);
      const info = await mgr.getInfoOrNull(path);
      expect(info !== null).assertTrue();
      if (info !== null) {
        expect(info.size).assertEqual(1234);
      }
    });

    it('LOCAL getInfoOrNull returns null for missing file', 0, async () => {
      const mgr = new KdbxFileManager(StorageType.LOCAL);
      const info = await mgr.getInfoOrNull(testDir + '/local-missing.kdbx');
      expect(info).assertNull();
    });

    it('LOCAL exists delegates to getInfoOrNull', 0, async () => {
      const mgr = new KdbxFileManager(StorageType.LOCAL);
      const path = testDir + '/local-exists-delegate.kdbx';
      await writeTestFile(path, 8);
      expect(await mgr.exists(path)).assertTrue();
      expect(await mgr.exists(testDir + '/local-missing-2.kdbx')).assertFalse();
    });

    // -------- WebDAV 未初始化（无法判定错误上抛） --------

    it('WebDAV getInfoOrNull propagates indeterminate errors instead of null', 0, async () => {
      const webdav = new WebDAVStorage();
      try {
        await webdav.getInfoOrNull('/some-path.kdbx');
        expect(false).assertTrue();
      } catch (error) {
        const err = error as StorageError;
        expect(err.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
      }
    });

    it('WebDAV exists propagates indeterminate errors instead of false', 0, async () => {
      const webdav = new WebDAVStorage();
      try {
        await webdav.exists('/some-path.kdbx');
        expect(false).assertTrue();
      } catch (error) {
        const err = error as StorageError;
        expect(err.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
      }
    });

    // -------- KdbxFileManager 能力回退 --------

    it('KdbxFileManager getInfoOrNull uses storage probe directly', 0, async () => {
      const factory = FileStorageFactory.getInstance();
      const original = factory.getStorageMap().get(StorageType.LOCAL);
      factory.registerStorage(StorageType.LOCAL, new StubNoProbeStorage());
      try {
        const mgr = new KdbxFileManager(StorageType.LOCAL);
        const info = await mgr.getInfoOrNull('/stub-exist.kdbx');
        expect(info !== null).assertTrue();
        if (info !== null) {
          expect(info.size).assertEqual(123);
        }
        const missing = await mgr.getInfoOrNull('/stub-missing.kdbx');
        expect(missing).assertNull();
      } finally {
        if (original) {
          factory.registerStorage(StorageType.LOCAL, original);
        } else {
          factory.removeStorage(StorageType.LOCAL);
        }
      }
    });

    // -------- CacheStorage 装饰器 --------

    it('CacheStorage getInfoOrNull passes through decorated capability', 0, async () => {
      const cacheStorage = new CacheStorage(new StubProbeCapableStorage());
      const info = await cacheStorage.getInfoOrNull('/stub-exist.kdbx');
      expect(info !== null).assertTrue();
      if (info !== null) {
        expect(info.size).assertEqual(123);
      }
      const missing = await cacheStorage.getInfoOrNull('/stub-missing.kdbx');
      expect(missing).assertNull();
    });

    it('CacheStorage getInfoOrNull passes through decorated probe', 0, async () => {
      const cacheStorage = new CacheStorage(new StubNoProbeStorage());
      const info = await cacheStorage.getInfoOrNull('/stub-exist.kdbx');
      expect(info !== null).assertTrue();
      if (info !== null) {
        expect(info.size).assertEqual(123);
      }
      const missing = await cacheStorage.getInfoOrNull('/stub-missing.kdbx');
      expect(missing).assertNull();
    });

    it('CacheStorage getInfoOrNull falls back to cache copy when remote indeterminate', 0, async () => {
      const stub = new StubNoProbeStorage();
      stub.throwOnGetInfo = true;
      const cacheStorage = new CacheStorage(stub);
      const remotePath = '/stub-exist.kdbx';
      const cachePath = CacheConstants.getCacheFilePath(remotePath);

      // 无缓存副本：远端无法判定 + 缓存 miss → 上抛（保留"无法判定"语义）
      try {
        await cacheStorage.getInfoOrNull(remotePath);
        expect(false).assertTrue();
      } catch (error) {
        expect((error as StorageError).message.includes('remote indeterminate')).assertTrue();
      }

      // 有缓存副本：返回缓存信息（离线可用语义）
      try {
        await writeTestFile(cachePath, 777);
        const fromCache = await cacheStorage.getInfoOrNull(remotePath);
        expect(fromCache !== null).assertTrue();
        if (fromCache !== null) {
          expect(fromCache.size).assertEqual(777);
        }
      } finally {
        try {
          fs.unlinkSync(cachePath);
        } catch {
          // ignore
        }
      }
    });

    it('CacheStorage getInfoOrNull only-cache mode: hit returns info, miss returns null', 0, async () => {
      CacheConstants.setWorkerCachePolicy(true, true, false);
      try {
        const cacheStorage = new CacheStorage(new StubNoProbeStorage());
        const remotePath = '/stub-only-cache.kdbx';
        const cachePath = CacheConstants.getCacheFilePath(remotePath);
        try {
          await writeTestFile(cachePath, 512);
          const hit = await cacheStorage.getInfoOrNull(remotePath);
          expect(hit !== null).assertTrue();
          if (hit !== null) {
            expect(hit.size).assertEqual(512);
          }
        } finally {
          try {
            fs.unlinkSync(cachePath);
          } catch {
            // ignore
          }
        }
        const miss = await cacheStorage.getInfoOrNull('/stub-only-cache-miss.kdbx');
        expect(miss).assertNull();
      } finally {
        CacheConstants.setWorkerCachePolicy(true, false, false);
      }
    });

    // -------- probeFileInfo + LoadDispatchCache --------

    it('probeFileInfo returns info and caches size, missing returns null', 0, async () => {
      const path = testDir + '/probe-file.kdbx';
      await writeTestFile(path, 4096);
      LoadDispatchCache.clear();

      const info = await RecentFilesService.probeFileInfo(StorageType.LOCAL, {}, path);
      expect(info !== null).assertTrue();
      if (info !== null) {
        expect(info.size).assertEqual(4096);
      }
      expect(LoadDispatchCache.get(path)).assertEqual(4096);

      const missingPath = testDir + '/probe-missing.kdbx';
      const missing = await RecentFilesService.probeFileInfo(StorageType.LOCAL, {}, missingPath);
      expect(missing).assertNull();
      expect(LoadDispatchCache.get(missingPath)).assertUndefined();
      LoadDispatchCache.clear();
    });

    it('LoadDispatchCache ignores non-positive sizes', 0, () => {
      const path = '/dispatch-cache-zero.kdbx';
      LoadDispatchCache.put(path, 0);
      expect(LoadDispatchCache.get(path)).assertUndefined();
      LoadDispatchCache.put(path, 100);
      expect(LoadDispatchCache.get(path)).assertEqual(100);
      LoadDispatchCache.clear();
      expect(LoadDispatchCache.get(path)).assertUndefined();
    });
  });
}
