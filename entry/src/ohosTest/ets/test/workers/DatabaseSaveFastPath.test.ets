import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { Consts, Kdbx, KdbxCredentials, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { FileStorageFactory } from '../../../../main/ets/storage/FileStorageFactory';
import { LocalFileStorage } from '../../../../main/ets/storage/local/LocalFileStorage';
import { FileInfo, StorageType } from '../../../../main/ets/storage';
import { ConflictStrategy, SaveDatabaseMessage } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { ConflictMessage, SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { DatabaseSave } from '../../../../main/ets/workers/DatabaseSave';
import { HashUtils } from '../../../../main/ets/common/utils/HashUtils';
import { SyncSaveResult, KdbxModeTestHelper } from './KdbxModeTestHelper';

/**
 * 可计数的 LOCAL 存储子类：opt-in 版本快速路径能力 + 统计 readToFile 调用次数，
 * 用于断言保存链路的快速路径命中/未命中（readToFile 次数即"是否发生全量下载"）
 */
class CountingFastPathLocalFileStorage extends LocalFileStorage {
  public static readToFileCount: number = 0;

  public async readToFile(path: string, destPath: string): Promise<FileInfo> {
    CountingFastPathLocalFileStorage.readToFileCount++;
    return super.readToFile(path, destPath);
  }

  public supportsVersionFastPath(): boolean {
    return true;
  }
}

function saveSync(saveMessage: SaveDatabaseMessage): Promise<SyncSaveResult> {
  return new Promise<SyncSaveResult>((resolve, reject) => {
    new DatabaseSave({
      onSuccess: (success: SuccessMessage) => {
        const result = new SyncSaveResult();
        result.success = success;
        resolve(result);
      },
      onConflict: (conflict: ConflictMessage) => {
        const result = new SyncSaveResult();
        result.conflict = conflict;
        resolve(result);
      },
      onError: (errorMessage: string) => {
        reject(new Error(errorMessage));
      }
    }).handleSaveDatabase(saveMessage);
  });
}

/**
 * S8 版本预检快速路径专项测试：
 * - 命中（expectedVersion 与守卫预检版本一致 + 存储声明能力）：跳过全量下载 + sha256，直接条件写入
 * - 未命中（无版本基线）：走全量下载 + 哈希校验路径，行为与既有语义一致
 * 通过注册计数存储子类观测 readToFile 调用次数验证下载是否发生
 */
export default function DatabaseSaveFastPathTest() {
  describe('DatabaseSaveFastPath', () => {
    let appContext: common.Context;
    let dbPath: string;
    let database: Kdbx;
    let baseVersion: string | null = null;
    let baseHash: string | null = null;
    const PASSWORD: string = KdbxModeTestHelper.DB_PASSWORD;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      dbPath = appContext.filesDir + '/db-save-fastpath-test.kdbx';
      // 注册计数存储子类（afterAll 恢复，不影响其他套件）
      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new CountingFastPathLocalFileStorage());

      // 构造 ChaCha20 v4 库并写入本地真实文件
      const credentials = new KdbxCredentials(ProtectedValue.fromString(PASSWORD));
      database = Kdbx.create(credentials, 'FastPathDb');
      database.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
      KdbxModeTestHelper.addEntry(database, 'fastpath-base-entry');
      const initialContent: ArrayBuffer = await database.save();
      const fileManager = new KdbxFileManager(StorageType.LOCAL);
      await fileManager.write(dbPath, initialContent);
      baseHash = await HashUtils.sha256Hex(initialContent);
      const info: FileInfo = await fileManager.getInfo(dbPath);
      baseVersion = info.version ?? null;
      expect(baseVersion).not().assertNull();
    });

    afterAll(() => {
      // 恢复原始 LOCAL 存储，避免影响后续套件
      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new LocalFileStorage());
    });

    /**
     * 快速路径命中：版本一致 + 能力声明 → 零下载，直接条件写入成功
     */
    it('version-matched save skips download and writes conditionally', 0, async () => {
      KdbxModeTestHelper.addEntry(database, 'fastpath-local-entry');
      CountingFastPathLocalFileStorage.readToFileCount = 0;

      const saveMessage = KdbxModeTestHelper.makeSaveMessage(database, dbPath, 'db-save-fastpath-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.AUTO);
      const result: SyncSaveResult = await saveSync(saveMessage);
      expect(result.success).not().assertNull();

      // 未发生全量下载（快速路径命中）
      expect(CountingFastPathLocalFileStorage.readToFileCount).assertEqual(0);

      // 文件被真实写入：读回解密验证新条目
      const fileManager = new KdbxFileManager(StorageType.LOCAL);
      const fileContent = await fileManager.read(dbPath);
      const credentials = new KdbxCredentials(ProtectedValue.fromString(PASSWORD));
      const persisted = await Kdbx.load(fileContent.content, credentials);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(persisted);
      expect(titles.includes('fastpath-base-entry')).assertTrue();
      expect(titles.includes('fastpath-local-entry')).assertTrue();

      // 成功消息带回新版本基线（下次保存可继续命中快速路径）
      const success = result.success as SuccessMessage;
      expect(success.version).not().assertNull();
      baseVersion = success.version ?? null;
      baseHash = success.contentHash ?? null;
    });

    /**
     * 快速路径未命中（无版本基线）：走全量下载 + 哈希校验，无冲突保存成功
     */
    it('save without version baseline falls back to full download path', 0, async () => {
      KdbxModeTestHelper.addEntry(database, 'fastpath-second-entry');
      CountingFastPathLocalFileStorage.readToFileCount = 0;

      const saveMessage = KdbxModeTestHelper.makeSaveMessage(database, dbPath, 'db-save-fastpath-test.kdbx',
        null, baseHash, ConflictStrategy.AUTO);
      const result: SyncSaveResult = await saveSync(saveMessage);
      expect(result.success).not().assertNull();

      // 发生了全量下载（快速路径未命中）
      expect(CountingFastPathLocalFileStorage.readToFileCount).assertEqual(1);

      const success = result.success as SuccessMessage;
      baseVersion = success.version ?? null;
      baseHash = success.contentHash ?? null;
    });

    /**
     * 快速路径命中后连续保存（用上次返回的新基线）持续命中
     */
    it('subsequent save with refreshed baseline hits fast path again', 0, async () => {
      KdbxModeTestHelper.addEntry(database, 'fastpath-third-entry');
      CountingFastPathLocalFileStorage.readToFileCount = 0;

      const saveMessage = KdbxModeTestHelper.makeSaveMessage(database, dbPath, 'db-save-fastpath-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.AUTO);
      const result: SyncSaveResult = await saveSync(saveMessage);
      expect(result.success).not().assertNull();
      expect(CountingFastPathLocalFileStorage.readToFileCount).assertEqual(0);

      const success = result.success as SuccessMessage;
      baseVersion = success.version ?? null;
      baseHash = success.contentHash ?? null;
      expect(baseVersion).not().assertNull();
    });
  });
}
