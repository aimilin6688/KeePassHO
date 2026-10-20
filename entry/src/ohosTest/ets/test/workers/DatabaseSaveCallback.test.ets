import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Consts, Kdbx, KdbxCredentials, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { LocalFileStorage } from '../../../../main/ets/storage/local/LocalFileStorage';
import { FileStorageFactory } from '../../../../main/ets/storage/FileStorageFactory';
import { FileInfo, StorageType, TransferProgressCallback, WriteOption } from '../../../../main/ets/storage';
import { StorageError, StorageErrorCodes } from '../../../../main/ets/storage/StorageError';
import { DatabaseSave } from '../../../../main/ets/workers/DatabaseSave';
import { SaveDatabaseMessage, ConflictStrategy } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { ProgressMessage, SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { SaveDatabaseCallback } from '../../../../main/ets/workers/callback/SaveDatabaseCallback';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { LocationInfo, LocationMode } from '../../../../main/ets/services/beans/LocationParam';
import { KdbxModeTestHelper, SyncSaveResult } from './KdbxModeTestHelper';
import { TestContextHelper } from '../TestContextHelper';

/**
 * 部分进度保存存储：写入完成后仅上报 1%（不补 100%），
 * 驱动上传限频器 finish() 兜底补发末条 100% 分支（真实存储全程上报时该分支不触发）。
 * writeFromFile 覆写：super 不带进度（避免先到 100%），完成后补 1%。
 */
class PartialProgressSaveStorage extends LocalFileStorage {
  public async write(path: string, content: ArrayBuffer, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<void> {
    await super.write(path, content, option);
    if (onProgress) {
      onProgress(1, 100);
    }
  }

  public async writeFromFile(path: string, srcPath: string, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<FileInfo> {
    const info: FileInfo = await super.writeFromFile(path, srcPath, option);
    if (onProgress) {
      onProgress(1, 100);
    }
    return info;
  }
}

/**
 * 写入必败存储：write/writeFromFile 直接抛错（HarmonyOS fs 无 chmod API，
 * 以此驱动保存流程写失败 catch 分支），读取路径继承真实实现保证下载阶段正常。
 */
class FailingWriteStorage extends LocalFileStorage {
  public async write(path: string, content: ArrayBuffer, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<void> {
    throw new Error('EACCES: permission denied, open (failing write storage)');
  }

  public async writeFromFile(path: string, srcPath: string, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<FileInfo> {
    throw new Error('EACCES: permission denied, rename (failing write storage)');
  }
}

/**
 * 首写版本冲突存储：write/writeFromFile 第一次抛 VERSION_CONFLICT（驱动保存流程重试分支），之后真实写入
 */
class ConflictOnceStorage extends LocalFileStorage {
  private conflicted: boolean = false;

  public async write(path: string, content: ArrayBuffer, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<void> {
    if (!this.conflicted) {
      this.conflicted = true;
      throw new StorageError(StorageErrorCodes.VERSION_CONFLICT, 'version conflict (conflict-once storage)');
    }
    return await super.write(path, content, option);
  }

  public async writeFromFile(path: string, srcPath: string, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<FileInfo> {
    if (!this.conflicted) {
      this.conflicted = true;
      throw new StorageError(StorageErrorCodes.VERSION_CONFLICT, 'version conflict (conflict-once storage)');
    }
    return await super.writeFromFile(path, srcPath, option, onProgress);
  }
}

/**
 * 二次 getInfo 失败存储：守卫预检（第 1 次）真实放行，postSuccess 兜底 getInfo（第 2 次）抛错，
 * 驱动 postSuccess 的 catch 分支
 */
class SecondGetInfoFailStorage extends LocalFileStorage {
  private getInfoCount: number = 0;

  public async getInfo(path: string): Promise<FileInfo> {
    this.getInfoCount++;
    if (this.getInfoCount >= 2) {
      throw new Error('stat failed (second-get-info-fail storage)');
    }
    return await super.getInfo(path);
  }
}

/**
 * DatabaseSave 回调与分支覆盖：
 * - 缓冲/流式两条上传路径的进度回调与 finish() 兜底 100%
 * - 版本基线单独篡改（哈希一致）触发 AUTO 冲突
 * - newPassword 改主密码、newKeyLocation 切换密钥文件（重新打开验证）
 * - 损坏数据载荷走外层 catch、CP1 超限拒绝（设置快照恢复）
 * - 写入必败存储分别触发缓冲/流式写入失败 catch
 */
export default function DatabaseSaveCallbackTest() {
  describe('DatabaseSaveCallback', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let bufferPath: string;
    let streamPath: string;
    let conflictPath: string;
    let passwordPath: string;
    let keySwitchPath: string;
    let keyfilePath: string;
    let corruptPath: string;
    let guardPath: string;
    let bufferFailPath: string;
    let streamFailPath: string;
    let conflictRetryPath: string;
    let mergeRetryPath: string;
    let mergeFailPath: string;
    let getInfoFailPath: string;

    const bufferName: string = 'db-save-callback-buffer.kdbx';
    const streamName: string = 'db-save-callback-stream.kdbx';
    const conflictName: string = 'db-save-callback-conflict.kdbx';
    const passwordName: string = 'db-save-callback-password.kdbx';
    const keySwitchName: string = 'db-save-callback-key.kdbx';
    const keyfileName: string = 'db-save-callback.key';
    const corruptName: string = 'db-save-callback-corrupt.kdbx';
    const guardName: string = 'db-save-callback-guard.kdbx';
    const bufferFailName: string = 'db-save-callback-writefail.kdbx';
    const streamFailName: string = 'db-save-callback-streamfail.kdbx';
    const conflictRetryName: string = 'db-save-callback-conflict-retry.kdbx';
    const mergeRetryName: string = 'db-save-callback-merge-retry.kdbx';
    const mergeFailName: string = 'db-save-callback-merge-fail.kdbx';
    const getInfoFailName: string = 'db-save-callback-getinfo-fail.kdbx';

    /**
     * 以带 onProgress 回调的同步模式执行一次保存
     */
    const saveSyncWithProgress = (message: SaveDatabaseMessage,
      onProgress: (message: ProgressMessage) => void): Promise<SyncSaveResult> => {
      return new Promise<SyncSaveResult>((resolve, reject) => {
        const callback: SaveDatabaseCallback = {
          onSuccess: (success: SuccessMessage) => {
            const result = new SyncSaveResult();
            result.success = success;
            resolve(result);
          },
          onError: (errorMessage: string) => {
            reject(new Error(errorMessage));
          },
          onProgress: onProgress
        };
        new DatabaseSave(callback).handleSaveDatabase(message);
      });
    };

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      await SettingsService.getInstance().init(await TestContextHelper.getUIAbilityContext());
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new PartialProgressSaveStorage());

      const baseDir: string = appContext.filesDir;
      bufferPath = baseDir + '/' + bufferName;
      streamPath = baseDir + '/' + streamName;
      conflictPath = baseDir + '/' + conflictName;
      passwordPath = baseDir + '/' + passwordName;
      keySwitchPath = baseDir + '/' + keySwitchName;
      keyfilePath = baseDir + '/' + keyfileName;
      corruptPath = baseDir + '/' + corruptName;
      guardPath = baseDir + '/' + guardName;
      bufferFailPath = baseDir + '/' + bufferFailName;
      streamFailPath = baseDir + '/' + streamFailName;
      conflictRetryPath = baseDir + '/' + conflictRetryName;
      mergeRetryPath = baseDir + '/' + mergeRetryName;
      mergeFailPath = baseDir + '/' + mergeFailName;
      getInfoFailPath = baseDir + '/' + getInfoFailName;
    });

    afterAll(() => {
      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new LocalFileStorage());
      for (const p of [bufferPath, streamPath, conflictPath, passwordPath, keySwitchPath,
        keyfilePath, corruptPath, guardPath, bufferFailPath, streamFailPath,
        conflictRetryPath, mergeRetryPath, mergeFailPath, getInfoFailPath]) {
        try {
          fs.unlinkSync(p);
        } catch {
          // 文件不存在：忽略
        }
      }
    });

    it('aes save reports buffer upload progress through onProgress callback', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveBufferProgressDb', 'save-buffer-progress-entry');
      await fileManager.write(bufferPath, await database.save());
      KdbxModeTestHelper.addEntry(database, 'save-buffer-progress-second');

      const progressPercents: number[] = [];
      const result: SyncSaveResult = await saveSyncWithProgress(
        KdbxModeTestHelper.makeSaveMessage(database, bufferPath, bufferName, null, null, ConflictStrategy.AUTO),
        (message: ProgressMessage) => {
          progressPercents.push(message.percent);
        });

      expect(result.success !== null).assertTrue();
      expect(progressPercents.length >= 2).assertTrue();
      expect(progressPercents[progressPercents.length - 1]).assertEqual(100);
    });

    it('chacha20 save reports stream upload progress through onProgress callback', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveStreamProgressDb', 'save-stream-progress-entry');
      database.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
      await fileManager.write(streamPath, await database.save());
      KdbxModeTestHelper.addEntry(database, 'save-stream-progress-second');

      const progressPercents: number[] = [];
      const result: SyncSaveResult = await saveSyncWithProgress(
        KdbxModeTestHelper.makeSaveMessage(database, streamPath, streamName, null, null, ConflictStrategy.AUTO),
        (message: ProgressMessage) => {
          progressPercents.push(message.percent);
        });

      expect(result.success !== null).assertTrue();
      expect(progressPercents.length >= 2).assertTrue();
      expect(progressPercents[progressPercents.length - 1]).assertEqual(100);
    });

    it('version-only baseline mismatch with matching hash triggers AUTO conflict', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveVersionConflictDb', 'save-version-conflict-entry');
      await fileManager.write(conflictPath, await database.save());

      const first: SyncSaveResult = await KdbxModeTestHelper.saveSync(
        KdbxModeTestHelper.makeSaveMessage(database, conflictPath, conflictName, null, null, ConflictStrategy.AUTO));
      expect(first.success !== null).assertTrue();
      const version: string | null = (first.success as SuccessMessage).version ?? null;
      const contentHash: string | null = (first.success as SuccessMessage).contentHash ?? null;
      expect(version).not().assertNull();
      expect(contentHash).not().assertNull();

      KdbxModeTestHelper.addEntry(database, 'save-version-conflict-second');
      const result: SyncSaveResult = await KdbxModeTestHelper.saveSync(
        KdbxModeTestHelper.makeSaveMessage(database, conflictPath, conflictName,
          'bogus-version-' + Date.now(), contentHash, ConflictStrategy.AUTO));

      expect(result.conflict !== null).assertTrue();
    });

    it('saving with newPassword re-encrypts database with new master password', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveNewPasswordDb', 'save-new-password-entry');
      await fileManager.write(passwordPath, await database.save());

      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, passwordPath, passwordName, null, null);
      dbFileParam.newPassword = 'New-Pass-456';
      const result: SyncSaveResult = await KdbxModeTestHelper.saveSync(
        new SaveDatabaseMessage(database, dbFileParam, ConflictStrategy.AUTO));
      expect(result.success !== null).assertTrue();

      const saved = await fileManager.read(passwordPath);
      const reopened: Kdbx = await Kdbx.load(saved.content,
        new KdbxCredentials(ProtectedValue.fromString('New-Pass-456')));
      expect(KdbxModeTestHelper.collectEntryTitles(reopened).includes('save-new-password-entry')).assertTrue();

      let oldPasswordRejected = false;
      try {
        await Kdbx.load(saved.content,
          new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD)));
      } catch {
        oldPasswordRejected = true;
      }
      expect(oldPasswordRejected).assertTrue();
    });

    it('saving with newKeyLocation switches database to new key file', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveNewKeyDb', 'save-new-key-entry');
      await fileManager.write(keySwitchPath, await database.save());

      const keyBytes: ArrayBuffer = new ArrayBuffer(32);
      const keyView: Uint8Array = new Uint8Array(keyBytes);
      for (let i = 0; i < keyView.length; i++) {
        keyView[i] = Math.floor(Math.random() * 256);
      }
      await fileManager.write(keyfilePath, keyBytes);

      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, keySwitchPath, keySwitchName, null, null);
      const keyLocation: LocationInfo = {
        mode: LocationMode.SELECT,
        filePath: keyfilePath,
        fileName: keyfileName,
        storageType: StorageType.LOCAL,
        storageConfig: {}
      };
      dbFileParam.newKeyLocation = keyLocation;
      const result: SyncSaveResult = await KdbxModeTestHelper.saveSync(
        new SaveDatabaseMessage(database, dbFileParam, ConflictStrategy.AUTO));
      expect(result.success !== null).assertTrue();

      const saved = await fileManager.read(keySwitchPath);
      const reopened: Kdbx = await Kdbx.load(saved.content,
        new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD), keyBytes));
      expect(KdbxModeTestHelper.collectEntryTitles(reopened).includes('save-new-key-entry')).assertTrue();
    });

    it('corrupt database payload fails with save error', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveCorruptDb', 'save-corrupt-entry');
      await fileManager.write(corruptPath, await database.save());
      const first: SyncSaveResult = await KdbxModeTestHelper.saveSync(
        KdbxModeTestHelper.makeSaveMessage(database, corruptPath, corruptName, null, null, ConflictStrategy.AUTO));
      expect(first.success !== null).assertTrue();
      const version: string | null = (first.success as SuccessMessage).version ?? null;
      const contentHash: string | null = (first.success as SuccessMessage).contentHash ?? null;

      const garbage: ArrayBuffer = new ArrayBuffer(64);
      const garbageView: Uint8Array = new Uint8Array(garbage);
      for (let i = 0; i < garbageView.length; i++) {
        garbageView[i] = 0xAB;
      }
      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, corruptPath, corruptName, version, contentHash);
      let rejected = false;
      try {
        await KdbxModeTestHelper.saveSync(new SaveDatabaseMessage(garbage, dbFileParam, ConflictStrategy.AUTO));
      } catch {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('guard rejects database save when max size limit is zero (CP1)', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveGuardDb', 'save-guard-entry');
      await fileManager.write(guardPath, await database.save());

      const originalLimit: number = SettingsService.getSync<number>(SettingsService.KEY_DATABASE_MAX_SIZE,
        SettingsService.KEY_DATABASE_MAX_SIZE_DEFAULT);
      await SettingsService.put(SettingsService.KEY_DATABASE_MAX_SIZE, 0);
      try {
        let rejected = false;
        let message = '';
        try {
          await KdbxModeTestHelper.saveSync(
            KdbxModeTestHelper.makeSaveMessage(database, guardPath, guardName, null, null, ConflictStrategy.AUTO));
        } catch (e) {
          rejected = true;
          message = (e as Error).message;
        }
        expect(rejected).assertTrue();
        expect(message.length > 0).assertTrue();
      } finally {
        await SettingsService.put(SettingsService.KEY_DATABASE_MAX_SIZE, originalLimit);
      }
    });

    it('failing buffer write makes aes save reject with error', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveBufferFailDb', 'save-buffer-fail-entry');
      await fileManager.write(bufferFailPath, await database.save());
      KdbxModeTestHelper.addEntry(database, 'save-buffer-fail-second');

      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new FailingWriteStorage());
      try {
        let rejected = false;
        try {
          await KdbxModeTestHelper.saveSync(
            KdbxModeTestHelper.makeSaveMessage(database, bufferFailPath, bufferFailName, null, null,
              ConflictStrategy.AUTO));
        } catch {
          rejected = true;
        }
        expect(rejected).assertTrue();
      } finally {
        FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new PartialProgressSaveStorage());
      }
    });

    it('failing stream write makes chacha20 save reject with error', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveStreamFailDb', 'save-stream-fail-entry');
      database.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
      await fileManager.write(streamFailPath, await database.save());
      KdbxModeTestHelper.addEntry(database, 'save-stream-fail-second');

      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new FailingWriteStorage());
      try {
        let rejected = false;
        try {
          await KdbxModeTestHelper.saveSync(
            KdbxModeTestHelper.makeSaveMessage(database, streamFailPath, streamFailName, null, null,
              ConflictStrategy.AUTO));
        } catch {
          rejected = true;
        }
        expect(rejected).assertTrue();
      } finally {
        FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new PartialProgressSaveStorage());
      }
    });

    it('first write version conflict retries and saves', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveConflictRetryDb', 'save-conflict-retry-entry');
      await fileManager.write(conflictRetryPath, await database.save());
      KdbxModeTestHelper.addEntry(database, 'save-conflict-retry-second');

      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new ConflictOnceStorage());
      try {
        const result: SyncSaveResult = await KdbxModeTestHelper.saveSync(
          KdbxModeTestHelper.makeSaveMessage(database, conflictRetryPath, conflictRetryName, null, null,
            ConflictStrategy.AUTO));
        const success: SuccessMessage | null = result.success;
        expect(success !== null).assertTrue();

        const saved = await fileManager.read(conflictRetryPath);
        const reopened: Kdbx = await Kdbx.load(saved.content,
          new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD)));
        const titles: string[] = KdbxModeTestHelper.collectEntryTitles(reopened);
        expect(titles.includes('save-conflict-retry-second')).assertTrue();
      } finally {
        FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new PartialProgressSaveStorage());
      }
    });

    it('merge strategy retries after write version conflict', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveMergeRetryDb', 'save-merge-retry-entry');
      await fileManager.write(mergeRetryPath, await database.save());
      KdbxModeTestHelper.addEntry(database, 'save-merge-retry-second');

      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new ConflictOnceStorage());
      try {
        const result: SyncSaveResult = await KdbxModeTestHelper.saveSync(
          KdbxModeTestHelper.makeSaveMessage(database, mergeRetryPath, mergeRetryName,
            'stale-version-' + Date.now(), 'stale-hash-' + Date.now(), ConflictStrategy.MERGE));
        const success: SuccessMessage | null = result.success;
        expect(success !== null).assertTrue();
        if (success !== null) {
          expect(success.isMerge).assertTrue();
        }

        const saved = await fileManager.read(mergeRetryPath);
        const reopened: Kdbx = await Kdbx.load(saved.content,
          new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD)));
        const titles: string[] = KdbxModeTestHelper.collectEntryTitles(reopened);
        expect(titles.includes('save-merge-retry-entry')).assertTrue();
        expect(titles.includes('save-merge-retry-second')).assertTrue();
      } finally {
        FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new PartialProgressSaveStorage());
      }
    });

    it('merge strategy surfaces write failure as error', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveMergeFailDb', 'save-merge-fail-entry');
      await fileManager.write(mergeFailPath, await database.save());
      KdbxModeTestHelper.addEntry(database, 'save-merge-fail-second');

      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new FailingWriteStorage());
      try {
        let rejected = false;
        try {
          await KdbxModeTestHelper.saveSync(
            KdbxModeTestHelper.makeSaveMessage(database, mergeFailPath, mergeFailName,
              'stale-version-' + Date.now(), 'stale-hash-' + Date.now(), ConflictStrategy.MERGE));
        } catch {
          rejected = true;
        }
        expect(rejected).assertTrue();
      } finally {
        FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new PartialProgressSaveStorage());
      }
    });

    it('postSuccess getInfo failure rejects save', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('SaveGetInfoFailDb', 'save-getinfo-fail-entry');
      await fileManager.write(getInfoFailPath, await database.save());
      KdbxModeTestHelper.addEntry(database, 'save-getinfo-fail-second');

      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new SecondGetInfoFailStorage());
      try {
        let rejected = false;
        try {
          await KdbxModeTestHelper.saveSync(
            KdbxModeTestHelper.makeSaveMessage(database, getInfoFailPath, getInfoFailName, null, null,
              ConflictStrategy.AUTO));
        } catch {
          rejected = true;
        }
        expect(rejected).assertTrue();
      } finally {
        FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new PartialProgressSaveStorage());
      }
    });
  });
}
