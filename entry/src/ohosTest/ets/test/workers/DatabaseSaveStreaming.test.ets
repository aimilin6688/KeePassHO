import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Kdbx, KdbxCredentials, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { HashUtils } from '../../../../main/ets/common/utils/HashUtils';
import { StorageType } from '../../../../main/ets/storage';
import { ConflictStrategy } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { ConflictMessage, SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { DatabaseSave } from '../../../../main/ets/workers/DatabaseSave';
import { SaveDatabaseMessage } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { SyncSaveResult, KdbxModeTestHelper } from './KdbxModeTestHelper';
import { Consts } from 'kdbxweb';

/**
 * S6 保存管道流式路径专项测试（DatabaseSave → saveToFile → writeFromFile）。
 *
 * DatabaseSyncMode/DatabaseWorkerMode 使用默认 AES 库（走回退整缓冲路径），
 * 本套件显式构造 ChaCha20 v4 库以激活 saveToFile + writeFromFile 流式管道，
 * 验证：
 * - 无冲突保存：文件写入、contentHash=sha256HexFile、版本基线、X1/X2/X3 临时文件清理
 * - MERGE：合并模型经 saveToFile 写入
 * - OVERWRITE：无条件写入
 * - AES 库回退：canSaveToFile=false → 走整缓冲 save()+write()
 */
function createChaChaDatabase(credentials: KdbxCredentials, name: string): Kdbx {
  const db = Kdbx.create(credentials, name);
  db.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
  return db;
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

function makeSaveMessage(database: Kdbx, filePath: string, fileName: string,
  version: string | null, contentHash: string | null, strategy: string): SaveDatabaseMessage {
  return KdbxModeTestHelper.makeSaveMessage(database, filePath, fileName, version, contentHash, strategy);
}

function listCachePipelineTemps(): string[] {
  const cacheDir = CommonUtils.getCacheDir();
  const names: string[] = fs.listFileSync(cacheDir);
  return names.filter((n: string) =>
    n.startsWith('save_x1_') || n.startsWith('save_x2_') || n.startsWith('save_x3_'));
}

export default function DatabaseSaveStreamingTest() {
  describe('DatabaseSaveStreaming', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let dbPath: string;
    let database: Kdbx;
    let baseVersion: string | null = null;
    let baseHash: string | null = null;
    const PASSWORD: string = KdbxModeTestHelper.DB_PASSWORD;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      dbPath = appContext.filesDir + '/db-save-streaming-test.kdbx';

      // 构造 ChaCha20 v4 库并写入本地真实文件（激活 saveToFile 流式路径）
      const credentials = new KdbxCredentials(ProtectedValue.fromString(PASSWORD));
      database = createChaChaDatabase(credentials, 'StreamingSaveDb');
      KdbxModeTestHelper.addEntry(database, 'stream-base-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      baseHash = await HashUtils.sha256Hex(initialContent);
    });

    /**
     * 流式路径：无冲突保存写入文件、contentHash 与文件真实哈希一致、临时文件清理
     */
    it('streaming save without conflict writes file and cleans temp files', 0, async () => {
      KdbxModeTestHelper.addEntry(database, 'stream-local-entry');
      // canSaveToFile 必须为 true 才进入流式路径
      expect(database.canSaveToFile()).assertTrue();

      const saveMessage = makeSaveMessage(database, dbPath, 'db-save-streaming-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.AUTO);
      const result: SyncSaveResult = await saveSync(saveMessage);
      expect(result.success !== null).assertTrue();
      const success = result.success as SuccessMessage;

      expect(success.isMerge).assertFalse();
      // contentHash 应等于写入文件的真实 SHA256（流式路径用 sha256HexFile 计算）
      const fileContent = await fileManager.read(dbPath);
      expect(success.contentHash).assertEqual(await HashUtils.sha256Hex(fileContent.content));

      // 文件已被真实写入：读回解密验证新条目
      const credentials = new KdbxCredentials(ProtectedValue.fromString(PASSWORD));
      const persisted = await Kdbx.load(fileContent.content, credentials);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(persisted);
      expect(titles.includes('stream-base-entry')).assertTrue();
      expect(titles.includes('stream-local-entry')).assertTrue();

      // 流式路径非合并 data 传空缓冲（主线程不用）
      expect((success.data as ArrayBuffer).byteLength).assertEqual(0);

      // 保存完成后管道临时文件应被清理（finally unlink）
      expect(listCachePipelineTemps().length).assertEqual(0);

      baseVersion = success.version ?? null;
      baseHash = success.contentHash ?? null;
    });

    /**
     * 流式路径 + MERGE：远端变更触发合并，合并模型经 saveToFile 写入
     */
    it('streaming save with MERGE keeps both sides', 0, async () => {
      // 他设备修改远端
      await KdbxModeTestHelper.writeRemoteModification(fileManager, dbPath, 'stream-remote-entry');
      // 本地同时修改
      KdbxModeTestHelper.addEntry(database, 'stream-merge-local-entry');

      const saveMessage = makeSaveMessage(database, dbPath, 'db-save-streaming-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.MERGE);
      const result: SyncSaveResult = await saveSync(saveMessage);
      expect(result.success !== null).assertTrue();
      const success = result.success as SuccessMessage;

      expect(success.isMerge).assertTrue();
      // 合并快照回传（主线程合并还原用）
      expect(success.snapshot instanceof ArrayBuffer).assertTrue();

      // 合并结果写入文件：双方条目都在
      const fileContent = await fileManager.read(dbPath);
      const credentials = new KdbxCredentials(ProtectedValue.fromString(PASSWORD));
      const merged = await Kdbx.load(fileContent.content, credentials);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(merged);
      expect(titles.includes('stream-remote-entry')).assertTrue();
      expect(titles.includes('stream-merge-local-entry')).assertTrue();

      // contentHash 与文件真实哈希一致
      expect(success.contentHash).assertEqual(await HashUtils.sha256Hex(fileContent.content));
      // 临时文件清理
      expect(listCachePipelineTemps().length).assertEqual(0);

      baseVersion = success.version ?? null;
      baseHash = success.contentHash ?? null;
    });

    /**
     * 流式路径 + OVERWRITE：丢弃远端修改，无条件写入本地内容
     */
    it('streaming save with OVERWRITE discards remote change', 0, async () => {
      // 他设备再次修改远端
      await KdbxModeTestHelper.writeRemoteModification(fileManager, dbPath, 'stream-remote-entry-2');
      // 本地同时修改
      KdbxModeTestHelper.addEntry(database, 'stream-overwrite-local-entry');

      const saveMessage = makeSaveMessage(database, dbPath, 'db-save-streaming-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.OVERWRITE);
      const result: SyncSaveResult = await saveSync(saveMessage);
      expect(result.success !== null).assertTrue();
      const success = result.success as SuccessMessage;

      expect(success.isMerge).assertFalse();

      // 文件为本地版本：本地条目在，他设备条目被丢弃
      const fileContent = await fileManager.read(dbPath);
      const credentials = new KdbxCredentials(ProtectedValue.fromString(PASSWORD));
      const overwritten = await Kdbx.load(fileContent.content, credentials);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(overwritten);
      expect(titles.includes('stream-overwrite-local-entry')).assertTrue();
      expect(titles.includes('stream-remote-entry-2')).assertFalse();

      // 临时文件清理
      expect(listCachePipelineTemps().length).assertEqual(0);

      baseVersion = success.version ?? null;
      baseHash = success.contentHash ?? null;
    });

    /**
     * 回退路径：AES 库 canSaveToFile=false，走整缓冲 save()+write()（data 非空）
     */
    it('aes database falls back to buffer save path', 0, async () => {
      // 构造默认 AES 库（canSaveToFile=false）
      const credentials = new KdbxCredentials(ProtectedValue.fromString(PASSWORD));
      const aesDb = Kdbx.create(credentials, 'AesFallbackDb');
      KdbxModeTestHelper.addEntry(aesDb, 'aes-fallback-entry');
      expect(aesDb.canSaveToFile()).assertFalse();

      const aesPath = appContext.filesDir + '/db-save-streaming-aes.kdbx';
      const initialContent: ArrayBuffer = await aesDb.save();
      await fileManager.write(aesPath, initialContent);
      const aesBaseHash = await HashUtils.sha256Hex(initialContent);

      KdbxModeTestHelper.addEntry(aesDb, 'aes-fallback-local');
      const saveMessage = makeSaveMessage(aesDb, aesPath, 'db-save-streaming-aes.kdbx',
        null, aesBaseHash, ConflictStrategy.AUTO);
      const result: SyncSaveResult = await saveSync(saveMessage);
      expect(result.success !== null).assertTrue();
      const success = result.success as SuccessMessage;

      // 回退路径 data 为真实缓冲（非空）
      expect((success.data as ArrayBuffer).byteLength > 0).assertTrue();
      // contentHash 与 data 的哈希一致（回退路径用 sha256Hex）
      expect(success.contentHash).assertEqual(await HashUtils.sha256Hex(success.data as ArrayBuffer));

      // 文件写入验证
      const fileContent = await fileManager.read(aesPath);
      const persisted = await Kdbx.load(fileContent.content, credentials);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(persisted);
      expect(titles.includes('aes-fallback-entry')).assertTrue();
      expect(titles.includes('aes-fallback-local')).assertTrue();

      // 回退路径不产生 save_x1/x2/x3 临时文件
      expect(listCachePipelineTemps().length).assertEqual(0);

      try { fs.unlinkSync(aesPath); } catch (e) { /* best effort */ }
    });
  });
}
