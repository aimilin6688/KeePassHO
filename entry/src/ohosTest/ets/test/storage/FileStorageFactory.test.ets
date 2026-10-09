import { afterAll, afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { FileStorage, FileStorageFactory } from '../../../../main/ets/storage/FileStorageFactory';
import { StorageType } from '../../../../main/ets/storage/StorageType';
import { IFileStorage, FileInfo, WriteOption } from '../../../../main/ets/storage/IFileStorage';
import { PageConfig, StorageConfig } from '../../../../main/ets/storage/StorageConfig';
import { CacheStorage } from '../../../../main/ets/storage/cache/CacheStorage';
import { S3PageConfig } from '../../../../main/ets/storage/s3/S3Config';

/** 手搓 IFileStorage 桩，用于 register/removeStorage 测试（不引入 hamock） */
class StubFileStorage implements IFileStorage {
  getPageConfig(): PageConfig {
    return S3PageConfig;
  }
  init(_config: StorageConfig): void {}
  read(_path: string): Promise<ArrayBuffer> {
    return Promise.resolve(new ArrayBuffer(0));
  }
  readToFile(_path: string, _destPath: string): Promise<FileInfo> {
    return Promise.reject(new Error('not implemented'));
  }
  write(_path: string, _content: ArrayBuffer, _option?: WriteOption): Promise<void> {
    return Promise.resolve();
  }
  writeFromFile(_path: string, _srcPath: string, _option?: WriteOption): Promise<FileInfo> {
    return Promise.reject(new Error('not implemented'));
  }
  exists(_path: string): Promise<boolean> {
    return Promise.resolve(false);
  }
  getInfo(_path: string): Promise<FileInfo> {
    return Promise.reject(new Error('not implemented'));
  }
  getInfoOrNull(_path: string): Promise<FileInfo | null> {
    return Promise.resolve(null);
  }
  listDir(_path: string): Promise<Array<FileInfo>> {
    return Promise.resolve([]);
  }
}

export default function FileStorageFactoryTest() {
  describe('FileStorageFactoryTest', () => {

    beforeAll(() => {
      // 确保基线干净：PCLOUD / BAIDU_NETDISK 默认未注册
      FileStorageFactory.getInstance().removeStorage(StorageType.PCLOUD);
      FileStorageFactory.getInstance().removeStorage(StorageType.BAIDU_NETDISK);
    });

    afterEach(() => {
      // 恢复默认注册表：移除测试中可能注册的桩
      FileStorageFactory.getInstance().removeStorage(StorageType.PCLOUD);
      FileStorageFactory.getInstance().removeStorage(StorageType.BAIDU_NETDISK);
    });

    afterAll(() => {
      FileStorageFactory.getInstance().removeStorage(StorageType.PCLOUD);
      FileStorageFactory.getInstance().removeStorage(StorageType.BAIDU_NETDISK);
    });

    describe('Singleton', () => {
      it('getInstance should return the same instance', 0, () => {
        const a: FileStorageFactory = FileStorageFactory.getInstance();
        const b: FileStorageFactory = FileStorageFactory.getInstance();
        expect(a === b).assertTrue();
      });
    });

    describe('Default_registrations', () => {
      it('should have LOCAL registered', 0, () => {
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.LOCAL)).assertTrue();
      });
      it('should have WEBDAV registered', 0, () => {
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.WEBDAV)).assertTrue();
      });
      it('should have S3 registered', 0, () => {
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.S3)).assertTrue();
      });
      it('should have ONEDRIVE registered', 0, () => {
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.ONEDRIVE)).assertTrue();
      });
      it('should have FTP registered', 0, () => {
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.FTP)).assertTrue();
      });
      it('should have HUAWEI_DRIVE registered', 0, () => {
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.HUAWEI_DRIVE)).assertTrue();
      });

      it('should NOT have PCLOUD registered by default', 0, () => {
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.PCLOUD)).assertFalse();
      });
      it('should NOT have BAIDU_NETDISK registered by default', 0, () => {
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.BAIDU_NETDISK)).assertFalse();
      });

      it('storageMap should contain 6 default entries', 0, () => {
        expect(FileStorageFactory.getInstance().getStorageMap().size).assertEqual(6);
      });
    });

    describe('getStorage', () => {
      it('should return a storage for LOCAL', 0, () => {
        const s: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.LOCAL);
        expect(s).not().assertUndefined();
      });

      it('LOCAL should return the raw storage (NOT wrapped in CacheStorage)', 0, () => {
        const s: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.LOCAL);
        expect(s instanceof CacheStorage).assertFalse();
      });

      it('LOCAL should return the same instance across calls (no per-call wrapping)', 0, () => {
        const a: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.LOCAL);
        const b: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.LOCAL);
        expect(a === b).assertTrue();
      });

      it('S3 should be wrapped in CacheStorage', 0, () => {
        const s: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.S3);
        expect(s instanceof CacheStorage).assertTrue();
      });

      it('WEBDAV should be wrapped in CacheStorage', 0, () => {
        const s: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.WEBDAV);
        expect(s instanceof CacheStorage).assertTrue();
      });

      it('ONEDRIVE should be wrapped in CacheStorage', 0, () => {
        const s: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.ONEDRIVE);
        expect(s instanceof CacheStorage).assertTrue();
      });

      it('FTP should be wrapped in CacheStorage', 0, () => {
        const s: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.FTP);
        expect(s instanceof CacheStorage).assertTrue();
      });

      it('HUAWEI_DRIVE should be wrapped in CacheStorage', 0, () => {
        const s: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.HUAWEI_DRIVE);
        expect(s instanceof CacheStorage).assertTrue();
      });

      it('non-LOCAL storages should return a NEW CacheStorage instance each call', 0, () => {
        const a: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.S3);
        const b: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.S3);
        expect(a === b).assertFalse();
      });

      it('should throw for unregistered PCLOUD', 0, () => {
        try {
          FileStorageFactory.getInstance().getStorage(StorageType.PCLOUD);
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertContain('PCLOUD');
          expect((e as Error).message).assertContain('not registered');
        }
      });

      it('should throw for unregistered BAIDU_NETDISK', 0, () => {
        try {
          FileStorageFactory.getInstance().getStorage(StorageType.BAIDU_NETDISK);
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertContain('BAIDU_NETDISK');
        }
      });
    });

    describe('registerStorage_removeStorage', () => {
      it('registerStorage should make hasStorage true', 0, () => {
        const stub: StubFileStorage = new StubFileStorage();
        FileStorageFactory.getInstance().registerStorage(StorageType.PCLOUD, stub);
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.PCLOUD)).assertTrue();
      });

      it('getStorage for newly registered non-LOCAL type should wrap in CacheStorage', 0, () => {
        const stub: StubFileStorage = new StubFileStorage();
        FileStorageFactory.getInstance().registerStorage(StorageType.PCLOUD, stub);
        const s: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.PCLOUD);
        expect(s instanceof CacheStorage).assertTrue();
      });

      it('registered LOCAL-type storage should return raw (no wrap)', 0, () => {
        // LOCAL 始终走 raw 分支
        const s: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.LOCAL);
        expect(s instanceof CacheStorage).assertFalse();
      });

      it('removeStorage should make hasStorage false', 0, () => {
        const stub: StubFileStorage = new StubFileStorage();
        FileStorageFactory.getInstance().registerStorage(StorageType.PCLOUD, stub);
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.PCLOUD)).assertTrue();
        FileStorageFactory.getInstance().removeStorage(StorageType.PCLOUD);
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.PCLOUD)).assertFalse();
      });

      it('removeStorage for non-existent type is a no-op', 0, () => {
        // BAIDU_NETDISK 未注册，移除不应抛出
        FileStorageFactory.getInstance().removeStorage(StorageType.BAIDU_NETDISK);
        expect(FileStorageFactory.getInstance().hasStorage(StorageType.BAIDU_NETDISK)).assertFalse();
      });

      it('registerStorage can override an existing registration', 0, () => {
        const stub1: StubFileStorage = new StubFileStorage();
        const stub2: StubFileStorage = new StubFileStorage();
        FileStorageFactory.getInstance().registerStorage(StorageType.PCLOUD, stub1);
        FileStorageFactory.getInstance().registerStorage(StorageType.PCLOUD, stub2);
        expect(FileStorageFactory.getInstance().getStorageMap().get(StorageType.PCLOUD) === stub2).assertTrue();
      });
    });

    describe('getStorageMap', () => {
      it('should return a Map containing all registered types', 0, () => {
        const map: Map<StorageType, IFileStorage> = FileStorageFactory.getInstance().getStorageMap();
        expect(map.has(StorageType.LOCAL)).assertTrue();
        expect(map.has(StorageType.WEBDAV)).assertTrue();
        expect(map.has(StorageType.S3)).assertTrue();
        expect(map.has(StorageType.ONEDRIVE)).assertTrue();
        expect(map.has(StorageType.FTP)).assertTrue();
        expect(map.has(StorageType.HUAWEI_DRIVE)).assertTrue();
      });

      it('should reflect register/remove changes', 0, () => {
        const stub: StubFileStorage = new StubFileStorage();
        FileStorageFactory.getInstance().registerStorage(StorageType.PCLOUD, stub);
        expect(FileStorageFactory.getInstance().getStorageMap().has(StorageType.PCLOUD)).assertTrue();
        FileStorageFactory.getInstance().removeStorage(StorageType.PCLOUD);
        expect(FileStorageFactory.getInstance().getStorageMap().has(StorageType.PCLOUD)).assertFalse();
      });
    });

    describe('FileStorage_static_facade', () => {
      it('FileStorage.getStorage should delegate to the singleton', 0, () => {
        const a: IFileStorage = FileStorage.getStorage(StorageType.LOCAL);
        const b: IFileStorage = FileStorageFactory.getInstance().getStorage(StorageType.LOCAL);
        expect(a === b).assertTrue();
      });

      it('FileStorage.hasStorage should reflect singleton state', 0, () => {
        expect(FileStorage.hasStorage(StorageType.LOCAL)).assertTrue();
        expect(FileStorage.hasStorage(StorageType.PCLOUD)).assertFalse();
      });

      it('FileStorage.registerStorage / removeStorage should affect singleton', 0, () => {
        const stub: StubFileStorage = new StubFileStorage();
        FileStorage.registerStorage(StorageType.PCLOUD, stub);
        expect(FileStorage.hasStorage(StorageType.PCLOUD)).assertTrue();
        FileStorage.removeStorage(StorageType.PCLOUD);
        expect(FileStorage.hasStorage(StorageType.PCLOUD)).assertFalse();
      });

      it('FileStorage.getAllPageConfig should return one PageConfig per registered storage', 0, () => {
        const configs: PageConfig[] = FileStorage.getAllPageConfig();
        expect(configs.length).assertEqual(FileStorageFactory.getInstance().getStorageMap().size);
        for (let i = 0; i < configs.length; i++) {
          expect(configs[i]).not().assertUndefined();
          expect(configs[i].pageUrl).assertContain('storage/');
        }
      });

      it('FileStorage.getAllPageConfig should grow after registerStorage', 0, () => {
        const before: number = FileStorage.getAllPageConfig().length;
        const stub: StubFileStorage = new StubFileStorage();
        FileStorage.registerStorage(StorageType.PCLOUD, stub);
        const after: number = FileStorage.getAllPageConfig().length;
        expect(after).assertEqual(before + 1);
        FileStorage.removeStorage(StorageType.PCLOUD);
        expect(FileStorage.getAllPageConfig().length).assertEqual(before);
      });
    });
  });
}
