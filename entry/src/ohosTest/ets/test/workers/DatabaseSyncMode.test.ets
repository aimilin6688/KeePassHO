import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { ConflictStrategy } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { StorageType } from '../../../../main/ets/storage';
import { SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { HashUtils } from '../../../../main/ets/common/utils/HashUtils';
import { KdbxModeTestHelper, SyncSaveResult } from './KdbxModeTestHelper';

const DOMAIN = 0x0000;
const TAG = 'DatabaseSyncModeTest';

/**
 * 数据库同步模式单元测试（Constants.ASYNC_LOAD/SAVE_DATABASE = false 的主线程路径）。
 *
 * 直接驱动 DatabaseLoad / DatabaseSave 核心编排：
 * 真实加密构造 KDBX 数据库 → 写入本地沙箱真实文件 → 主线程加载/保存全链路，
 * 覆盖加载成功/凭证错误/文件不存在、保存无冲突条件写入、
 * 双基线冲突检测（AUTO 上报冲突）、MERGE 双方合并、OVERWRITE 覆盖远端。
 * 不使用 mock 数据。
 */
export default function DatabaseSyncModeTest() {
  describe('DatabaseSyncModeTest', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let database: Kdbx;
    let dbPath: string;
    /** 冲突检测基线：远端文件版本（LocalFileStorage 为 size|mtime 复合串） */
    let baseVersion: string | null = null;
    /** 冲突检测基线：远端文件内容 SHA256 */
    let baseHash: string | null = null;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      dbPath = appContext.filesDir + '/db-sync-mode-test.kdbx';

      // 构造真实数据库（真实加密）并写入本地真实文件
      database = await KdbxModeTestHelper.createDatabase('SyncModeDb', 'base-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      baseHash = await KdbxModeTestHelper.sha256Hex(initialContent);
    });

    it('load success returns Kdbx instance with content hash baseline', 0, async () => {
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'db-sync-mode-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);
      const message: SuccessMessage = await KdbxModeTestHelper.loadSync(loadParam);

      // 同步模式：data 直接是 Kdbx 对象引用（无跨线程序列化）
      expect(message.data instanceof Kdbx).assertTrue();

      const loaded = message.data as Kdbx;
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(loaded);
      expect(titles.includes('base-entry')).assertTrue();

      // 加载结果携带远端内容哈希基线，供后续保存冲突检测使用
      expect(message.contentHash).assertEqual(baseHash);
    });

    it('load with wrong password reports error', 0, async () => {
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'db-sync-mode-test.kdbx', 'wrong-password');
      try {
        await KdbxModeTestHelper.loadSync(loadParam);
        expect(false).assertTrue(); // 不应执行到这里
      } catch (error) {
        expect(error instanceof Error).assertTrue();
      }
    });

    it('load not exists file reports error', 0, async () => {
      const loadParam = KdbxModeTestHelper.makeLoadParam(appContext.filesDir + '/not-exists.kdbx',
        'not-exists.kdbx', KdbxModeTestHelper.DB_PASSWORD);
      try {
        await KdbxModeTestHelper.loadSync(loadParam);
        expect(false).assertTrue(); // 不应执行到这里
      } catch (error) {
        expect(error instanceof Error).assertTrue();
      }
    });

    it('save without conflict writes file and refreshes baseline', 0, async () => {
      // 本地修改：添加条目
      KdbxModeTestHelper.addEntry(database, 'sync-local-entry');
      const saveMessage = KdbxModeTestHelper.makeSaveMessage(database, dbPath, 'db-sync-mode-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.AUTO);

      const result: SyncSaveResult = await KdbxModeTestHelper.saveSync(saveMessage);
      expect(result.success !== null).assertTrue();
      const success = result.success as SuccessMessage;

      expect(success.isMerge).assertFalse();
      // LocalFileStorage 版本语义为 size|mtime 复合串
      expect((success.version ?? '').includes('|')).assertTrue();
      // S6 语义：data 一律传空缓冲（§7.4，大缓冲不跨线程）
      expect((success.data as ArrayBuffer).byteLength).assertEqual(0);
      // 新基线 = 落盘文件内容的 SHA256（postSuccess buffer 路径 contentHash = sha256Hex(saved.buffer)，buffer 即写盘内容）
      expect(success.contentHash).assertEqual(await HashUtils.sha256HexFile(dbPath));

      // 文件已被真实写入：读回解密验证新条目
      const fileContent = await fileManager.read(dbPath);
      const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
      const persisted = await Kdbx.load(fileContent.content, credentials);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(persisted);
      expect(titles.includes('base-entry')).assertTrue();
      expect(titles.includes('sync-local-entry')).assertTrue();

      // 更新基线
      baseVersion = success.version ?? null;
      baseHash = success.contentHash ?? null;
    });

    it('save with remote change reports conflict in AUTO strategy', 0, async () => {
      // 他设备修改远端文件（同库副本加条目后写回）
      await KdbxModeTestHelper.writeRemoteModification(fileManager, dbPath, 'remote-entry');
      // 本地同时修改
      KdbxModeTestHelper.addEntry(database, 'local-conflict-entry');
      const saveMessage = KdbxModeTestHelper.makeSaveMessage(database, dbPath, 'db-sync-mode-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.AUTO);

      const result: SyncSaveResult = await KdbxModeTestHelper.saveSync(saveMessage);

      // AUTO 策略：上报冲突，本次不写入
      expect(result.conflict !== null).assertTrue();
      expect(result.success === null).assertTrue();

      // 远端文件保持他设备版本，本地修改未覆盖它
      const fileContent = await fileManager.read(dbPath);
      const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
      const remote = await Kdbx.load(fileContent.content, credentials);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(remote);
      expect(titles.includes('remote-entry')).assertTrue();
      expect(titles.includes('local-conflict-entry')).assertFalse();
    });

    it('save with MERGE strategy keeps both sides', 0, async () => {
      const saveMessage = KdbxModeTestHelper.makeSaveMessage(database, dbPath, 'db-sync-mode-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.MERGE);

      const result: SyncSaveResult = await KdbxModeTestHelper.saveSync(saveMessage);
      expect(result.success !== null).assertTrue();
      const success = result.success as SuccessMessage;

      // 发生了合并
      expect(success.isMerge).assertTrue();

      // 合并结果已写入文件：双方条目都在
      const fileContent = await fileManager.read(dbPath);
      const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
      const merged = await Kdbx.load(fileContent.content, credentials);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(merged);
      expect(titles.includes('remote-entry')).assertTrue();
      expect(titles.includes('local-conflict-entry')).assertTrue();

      // 更新基线
      baseVersion = success.version ?? null;
      baseHash = success.contentHash ?? null;
    });

    it('save with OVERWRITE strategy discards remote change', 0, async () => {
      // 他设备再次修改远端
      await KdbxModeTestHelper.writeRemoteModification(fileManager, dbPath, 'remote-entry-2');
      // 本地同时修改
      KdbxModeTestHelper.addEntry(database, 'local-overwrite-entry');
      const saveMessage = KdbxModeTestHelper.makeSaveMessage(database, dbPath, 'db-sync-mode-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.OVERWRITE);

      const result: SyncSaveResult = await KdbxModeTestHelper.saveSync(saveMessage);
      expect(result.success !== null).assertTrue();
      const success = result.success as SuccessMessage;

      // 覆盖不是合并
      expect(success.isMerge).assertFalse();

      // 文件为本地版本：本地条目在，他设备条目被丢弃
      const fileContent = await fileManager.read(dbPath);
      const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
      const overwritten = await Kdbx.load(fileContent.content, credentials);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(overwritten);
      expect(titles.includes('local-overwrite-entry')).assertTrue();
      expect(titles.includes('remote-entry-2')).assertFalse();

      // 更新基线
      baseVersion = success.version ?? null;
      baseHash = success.contentHash ?? null;
    });
  });
}
