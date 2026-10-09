import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CacheStorage } from '../../../../../main/ets/storage/cache/CacheStorage';
import { CacheConstants } from '../../../../../main/ets/storage/cache/CacheConstants';
import { CacheMeta, CacheMetaService } from '../../../../../main/ets/storage/cache/CacheMetaService';
import { LocalFileStorage } from '../../../../../main/ets/storage/local/LocalFileStorage';
import { FileInfo } from '../../../../../main/ets/storage';
import { CommonUtils } from '../../../../../main/ets/common/utils/CommonUtils';

async function writeBytes(path: string, bytes: number[]): Promise<void> {
  const data = new ArrayBuffer(bytes.length);
  const view = new Uint8Array(data);
  for (let i = 0; i < bytes.length; i++) {
    view[i] = bytes[i] % 256;
  }
  const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  await fs.write(file.fd, data);
  await fs.close(file.fd);
}

async function readBytes(path: string): Promise<number[]> {
  const file = await fs.open(path, fs.OpenMode.READ_ONLY);
  const stat = await fs.stat(file.fd);
  const buf = new ArrayBuffer(stat.size);
  await fs.read(file.fd, buf);
  await fs.close(file.fd);
  return Array.from(new Uint8Array(buf));
}

/**
 * 缓存元数据 + 版本快速路径单元测试（加载链路 P2 / P3.2 / P4 / P5）
 * 底层用 LocalFileStorage，由 CacheStorage 装饰（非 LOCAL 存储的产品形态）
 */
export default function CacheStorageVersionMetaTest() {
  describe('CacheStorageVersionMetaTest', () => {
    let testDir: string;
    let cacheStorage: CacheStorage;
    let remotePath: string;
    let remoteVersion: string;
    let remoteSize: number;

    beforeAll(async () => {
      const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      testDir = appContext.filesDir + '/cache-version-meta-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
      cacheStorage = new CacheStorage(new LocalFileStorage());
      // 主线程测试：以快照方式固定缓存策略（开启缓存 / 非仅缓存 / 非强制刷新）
      CacheConstants.setWorkerCachePolicy(true, false, false);

      remotePath = testDir + '/remote.kdbx';
      await writeBytes(remotePath, [1, 2, 3, 4, 5, 6, 7, 8]);
      await CacheConstants.deleteCache(remotePath);
      // 首次 readToFile：下载 + 回填缓存 + 写 meta（P2）
      await cacheStorage.readToFile(remotePath, testDir + '/dest-first.kdbx');
      const info: FileInfo = await cacheStorage.getInfo(remotePath);
      remoteVersion = info.version ?? '';
      remoteSize = info.size;
    });

    /**
     * P2：正常模式 readToFile 下载后回填缓存文件与版本元数据
     */
    it('readToFile backfills cache file and meta', 0, () => {
      const cachePath: string = CacheConstants.getCacheFilePath(remotePath);
      expect(fs.accessSync(cachePath, fs.AccessModeType.EXIST)).assertTrue();
      const meta: CacheMeta | null = CacheMetaService.readMeta(remotePath);
      expect(meta).not().assertNull();
      expect((meta as CacheMeta).version).assertEqual(remoteVersion);
      expect((meta as CacheMeta).size).assertEqual(remoteSize);
    });

    /**
     * P3.2：版本 + 尺寸双比对命中 → 本地拷贝，内容一致
     */
    it('readCacheToFile hits when version and size match', 0, async () => {
      const dest: string = testDir + '/dest-hit.kdbx';
      const hit: boolean = await cacheStorage.readCacheToFile(remotePath, dest, remoteVersion, remoteSize);
      expect(hit).assertTrue();
      expect(JSON.stringify(await readBytes(dest)))
        .assertEqual(JSON.stringify(await readBytes(remotePath)));
    });

    /**
     * 版本不一致 → miss（远端已变）
     */
    it('readCacheToFile misses on version mismatch', 0, async () => {
      const dest: string = testDir + '/dest-miss-version.kdbx';
      const hit: boolean = await cacheStorage.readCacheToFile(remotePath, dest, remoteVersion + '-changed', remoteSize);
      expect(hit).assertFalse();
    });

    /**
     * 尺寸不一致 → miss（弱 ETag / 秒级 mtime 的第二道防线）
     */
    it('readCacheToFile misses on size mismatch', 0, async () => {
      const dest: string = testDir + '/dest-miss-size.kdbx';
      const hit: boolean = await cacheStorage.readCacheToFile(remotePath, dest, remoteVersion, remoteSize + 1);
      expect(hit).assertFalse();
    });

    /**
     * 缓存文件被删（保留 meta）→ copyFile 失败 → miss（fail-safe 走下载）
     */
    it('readCacheToFile misses when cache file removed', 0, async () => {
      const cachePath: string = CacheConstants.getCacheFilePath(remotePath);
      const backup: string = testDir + '/cache-backup.bin';
      await fs.copyFile(cachePath, backup);
      await fs.unlink(cachePath);
      try {
        const dest: string = testDir + '/dest-miss-nocache.kdbx';
        const hit: boolean = await cacheStorage.readCacheToFile(remotePath, dest, remoteVersion, remoteSize);
        expect(hit).assertFalse();
      } finally {
        await fs.copyFile(backup, cachePath);
        await fs.unlink(backup);
      }
    });

    /**
     * force_refresh（下拉刷新 / 冲突重载）：同样先比对 —— 版本+尺寸一致则命中本地副本，
     * 省掉全量下载；语义仍是"拉最新"，内容未变时无需重复传输
     */
    it('readCacheToFile hits on force refresh when version matches', 0, async () => {
      CacheConstants.setWorkerCachePolicy(true, false, true);
      try {
        const dest: string = testDir + '/dest-force.kdbx';
        const hit: boolean = await cacheStorage.readCacheToFile(remotePath, dest, remoteVersion, remoteSize);
        expect(hit).assertTrue();
        expect(JSON.stringify(await readBytes(dest)))
          .assertEqual(JSON.stringify(await readBytes(remotePath)));
      } finally {
        CacheConstants.setWorkerCachePolicy(true, false, false);
      }
    });

    /**
     * force_refresh 且远端已变（版本不一致）→ miss，回落 readToFile 全量下载
     */
    it('readCacheToFile misses on force refresh when version changed', 0, async () => {
      CacheConstants.setWorkerCachePolicy(true, false, true);
      try {
        const dest: string = testDir + '/dest-force-changed.kdbx';
        const hit: boolean = await cacheStorage.readCacheToFile(remotePath, dest, remoteVersion + '-changed', remoteSize);
        expect(hit).assertFalse();
      } finally {
        CacheConstants.setWorkerCachePolicy(true, false, false);
      }
    });

    /**
     * 仅缓存模式：让位 readToFile 的仅缓存分支
     */
    it('readCacheToFile misses on only-use-cache', 0, async () => {
      CacheConstants.setWorkerCachePolicy(true, true, false);
      try {
        const dest: string = testDir + '/dest-only-cache.kdbx';
        const hit: boolean = await cacheStorage.readCacheToFile(remotePath, dest, remoteVersion, remoteSize);
        expect(hit).assertFalse();
      } finally {
        CacheConstants.setWorkerCachePolicy(true, false, false);
      }
    });

    /**
     * 关闭本地缓存开关：装饰器透明，快速路径不参与
     */
    it('readCacheToFile misses when local cache disabled', 0, async () => {
      CacheConstants.setWorkerCachePolicy(false, false, false);
      try {
        const dest: string = testDir + '/dest-disabled.kdbx';
        const hit: boolean = await cacheStorage.readCacheToFile(remotePath, dest, remoteVersion, remoteSize);
        expect(hit).assertFalse();
      } finally {
        CacheConstants.setWorkerCachePolicy(true, false, false);
      }
    });

    /**
     * P4：writeFromFile 保存后回写 meta（版本 = 远端写入后事实），随后快速路径可直接命中
     */
    it('writeFromFile refreshes meta with written version', 0, async () => {
      const savedPath: string = testDir + '/remote-saved.kdbx';
      await writeBytes(savedPath, [9, 9, 9, 9]);
      const srcPath: string = testDir + '/src-saved.kdbx';
      await writeBytes(srcPath, [7, 7, 7, 7, 7, 7]);
      const written: FileInfo = await cacheStorage.writeFromFile(savedPath, srcPath);
      const meta: CacheMeta | null = CacheMetaService.readMeta(savedPath);
      expect(meta).not().assertNull();
      expect((meta as CacheMeta).version).assertEqual(written.version ?? null);
      expect((meta as CacheMeta).size).assertEqual(written.size);

      // 保存后立刻"打开"：命中快速路径
      const dest: string = testDir + '/dest-after-save.kdbx';
      const hit: boolean = await cacheStorage.readCacheToFile(savedPath, dest, written.version ?? '', written.size);
      expect(hit).assertTrue();
      expect(JSON.stringify(await readBytes(dest))).assertEqual(JSON.stringify([7, 7, 7, 7, 7, 7]));
    });

    /**
     * P5：清理缓存时元数据一并删除，不留孤儿
     */
    it('deleteCache removes meta sidecar', 0, async () => {
      const doomed: string = testDir + '/remote-doomed.kdbx';
      await writeBytes(doomed, [1, 1, 1]);
      await cacheStorage.readToFile(doomed, testDir + '/dest-doomed.kdbx');
      expect(CacheMetaService.readMeta(doomed)).not().assertNull();
      await CacheConstants.deleteCache(doomed);
      expect(CacheMetaService.readMeta(doomed)).assertNull();
      expect(fs.accessSync(CacheConstants.getCacheFilePath(doomed), fs.AccessModeType.EXIST)).assertFalse();
    });
  });
}
