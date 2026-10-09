import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { Kdbx } from 'kdbxweb';
import { FileStorageFactory } from '../../../../main/ets/storage/FileStorageFactory';
import { LocalFileStorage } from '../../../../main/ets/storage/local/LocalFileStorage';
import { WebDAVStorage } from '../../../../main/ets/storage/webdav/WebDAVStorage';
import { CacheConstants } from '../../../../main/ets/storage/cache/CacheConstants';
import { FileInfo, StorageType } from '../../../../main/ets/storage';
import { LoadDatabase } from '../../../../main/ets/workers/DatabaseLoadWorkerParam';
import { SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { AuthType } from '../../../../main/ets/services/TypeDefined';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { KdbxModeTestHelper } from './KdbxModeTestHelper';

/**
 * 可计数的本地存储子类：opt-in 版本快速路径 + 统计 readToFile 调用次数。
 * 注册到 WEBDAV 类型上，使工厂自动套上 CacheStorage 装饰器（产品形态：远端存储 + 本地缓存），
 * readToFile 次数即"是否发生全量下载"。
 */
class CountingFastPathStorage extends LocalFileStorage {
  public static readToFileCount: number = 0;

  public async readToFile(path: string, destPath: string): Promise<FileInfo> {
    CountingFastPathStorage.readToFileCount++;
    return super.readToFile(path, destPath);
  }

  public supportsVersionFastPath(): boolean {
    return true;
  }
}

/**
 * 加载链路版本快速路径专项测试（P3）：
 * - 首次打开（无缓存元数据）：全量下载并回填缓存 + meta
 * - 二次打开（远端未变）：命中快速路径，零下载，基线三元组一致
 * - 远端已变：miss → 全量下载，内容包含对端修改
 * - force_refresh（下拉刷新）：即使版本一致也必下载
 */
export default function DatabaseLoadFastPathTest() {
  describe('DatabaseLoadFastPath', () => {
    let appContext: common.Context;
    let dbPath: string;
    let loadParam: LoadDatabase;
    let firstVersion: string | null = null;
    let firstHash: string | null = null;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      dbPath = appContext.filesDir + '/db-load-fastpath-test.kdbx';
      // 干净起点：清掉历史缓存与元数据
      await CacheConstants.deleteCache(dbPath);
      CacheConstants.setWorkerCachePolicy(true, false, false);
      // 注册计数存储（afterAll 恢复，不影响其他套件）
      FileStorageFactory.getInstance().registerStorage(StorageType.WEBDAV, new CountingFastPathStorage());

      const database: Kdbx = await KdbxModeTestHelper.createDatabase('LoadFastPathDb', 'load-base-entry');
      const content: ArrayBuffer = await database.save();
      const fileManager = new KdbxFileManager(StorageType.LOCAL);
      await fileManager.write(dbPath, content);

      loadParam = new LoadDatabase(dbPath, 'db-load-fastpath-test.kdbx', KdbxModeTestHelper.DB_PASSWORD,
        AuthType.PASSWORD, undefined, StorageType.WEBDAV, {});
    });

    afterAll(() => {
      FileStorageFactory.getInstance().registerStorage(StorageType.WEBDAV, new WebDAVStorage());
    });

    /**
     * 首次打开：无缓存元数据 → 全量下载（1 次），成功且基线三元组就绪
     */
    it('first open downloads and seeds cache meta', 0, async () => {
      CountingFastPathStorage.readToFileCount = 0;
      const message: SuccessMessage = await KdbxModeTestHelper.loadSync(loadParam);
      expect(CountingFastPathStorage.readToFileCount).assertEqual(1);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(message.data as Kdbx);
      expect(titles.includes('load-base-entry')).assertTrue();
      firstVersion = message.version ?? null;
      firstHash = message.contentHash ?? null;
      expect(firstVersion).not().assertNull();
      expect(firstHash).not().assertNull();
    });

    /**
     * 远端未变的二次打开：命中快速路径 → 零下载，基线三元组与首次一致
     */
    it('second open with unchanged remote hits fast path (no download)', 0, async () => {
      CountingFastPathStorage.readToFileCount = 0;
      const message: SuccessMessage = await KdbxModeTestHelper.loadSync(loadParam);
      expect(CountingFastPathStorage.readToFileCount).assertEqual(0);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(message.data as Kdbx);
      expect(titles.includes('load-base-entry')).assertTrue();
      expect(message.version ?? null).assertEqual(firstVersion);
      // 命中时 T0 即远端内容，实算哈希与首次一致（D2：命中后仍实算 sha256）
      expect(message.contentHash ?? null).assertEqual(firstHash);
    });

    /**
     * 远端已被他机修改：miss → 全量下载 → 打开内容含对端修改
     */
    it('open after remote change misses fast path and downloads', 0, async () => {
      const fileManager = new KdbxFileManager(StorageType.LOCAL);
      await KdbxModeTestHelper.writeRemoteModification(fileManager, dbPath, 'load-remote-entry');
      CountingFastPathStorage.readToFileCount = 0;
      const message: SuccessMessage = await KdbxModeTestHelper.loadSync(loadParam);
      expect(CountingFastPathStorage.readToFileCount).assertEqual(1);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(message.data as Kdbx);
      expect(titles.includes('load-base-entry')).assertTrue();
      expect(titles.includes('load-remote-entry')).assertTrue();
      firstVersion = message.version ?? null;
      firstHash = message.contentHash ?? null;
    });

    /**
     * force_refresh（下拉刷新）：版本一致也必下载（一次性标志在 miss 判定时被消费）
     */
    it('force refresh always downloads even when version matches', 0, async () => {
      CacheConstants.setWorkerCachePolicy(true, false, true);
      try {
        CountingFastPathStorage.readToFileCount = 0;
        const message: SuccessMessage = await KdbxModeTestHelper.loadSync(loadParam);
        expect(CountingFastPathStorage.readToFileCount).assertEqual(1);
        expect(KdbxModeTestHelper.collectEntryTitles(message.data as Kdbx).includes('load-remote-entry')).assertTrue();
      } finally {
        CacheConstants.setWorkerCachePolicy(true, false, false);
      }
    });

    /**
     * 刷新后再次打开：元数据已随下载回填，重新命中快速路径
     */
    it('open after refresh hits fast path again', 0, async () => {
      CountingFastPathStorage.readToFileCount = 0;
      const message: SuccessMessage = await KdbxModeTestHelper.loadSync(loadParam);
      expect(CountingFastPathStorage.readToFileCount).assertEqual(0);
      expect(message.version ?? null).assertEqual(firstVersion);
    });
  });
}
