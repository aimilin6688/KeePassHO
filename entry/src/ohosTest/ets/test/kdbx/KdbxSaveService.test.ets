import { afterAll, afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { Kdbx, KdbxCredentials, Consts, KdbxError, ProtectedValue } from 'kdbxweb';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import KdbxSaveService from '../../../../main/ets/services/kdbx/KdbxSaveService';
import { SaveDatabaseCallback } from '../../../../main/ets/workers/callback/SaveDatabaseCallback';
import { ToastSaveDatabaseCallback } from '../../../../main/ets/workers/callback/ToastSaveDatabaseCallback';
import { ConflictStrategy, SaveDatabaseMessage } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { ConflictMessage, LoadMessage, MessageType, ProgressMessage, SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { StorageType } from '../../../../main/ets/storage';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

const TEST_TIMEOUT_MS: number = 60000;

/**
 * SaveCallbackTracker — captures all callback invocations for assertion
 */
class SaveCallbackTracker implements SaveDatabaseCallback {
  public successCount: number = 0;
  public errorCount: number = 0;
  public messageCount: number = 0;
  public conflictCount: number = 0;
  public lastErrorMessage: string = '';
  public lastMessageString: string = '';
  public lastSuccessMessage: SuccessMessage | null = null;
  public lastConflictMessage: ConflictMessage | null = null;
  public progressCount: number = 0;
  public lastProgressMessage: ProgressMessage | null = null;

  onSuccess(message: SuccessMessage): void {
    this.successCount++;
    this.lastSuccessMessage = message;
  }

  onError(message: string): void {
    this.errorCount++;
    this.lastErrorMessage = message;
  }

  onMessage(message: string): void {
    this.messageCount++;
    this.lastMessageString = message;
  }

  onConflict(message: ConflictMessage): void {
    this.conflictCount++;
    this.lastConflictMessage = message;
  }

  onProgress(message: ProgressMessage): void {
    this.progressCount++;
    this.lastProgressMessage = message;
  }
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_resolve, reject) =>
      setTimeout(() => reject(new Error('Test timed out after ' + timeoutMs + 'ms')), timeoutMs)
    )
  ]);
}

interface AsyncSaveCheckResult {
  success: boolean;
  error: string;
  message: SuccessMessage | null;
}

interface SaveCheckResult {
  success: boolean;
  error: string;
}

interface ConflictCheckResult {
  conflict: boolean;
  error: string;
}

/**
 * KdbxSaveService 单元测试。
 *
 * 覆盖：
 * - saveDatabase 错误路径（无数据库 / RELOAD 策略无数据库）
 * - saveDatabaseFromUi 便捷入口（清空图标缓存 + 默认 Toast 回调）
 * - addCustomIcon 错误路径与图标添加
 * - 静态分发器：onSuccess / onConflict / onMessage / onError（有/无回调）
 * - callbackWarp：onError / onMessage / onConflict / onSuccess(非合并)
 * - handleSuccess：非合并更新基线 / 合并还原模型
 * - saveDatabaseAsync 端到端保存（真实 Worker）
 * - saveDatabase 端到端保存（真实 Worker + saveLock + handleSuccess）
 */
export default function KdbxSaveServiceTest() {
  describe('KdbxSaveServiceTest', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let dbPath: string;

    beforeAll(() => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      dbPath = appContext.filesDir + '/kdbx-save-service-test.kdbx';
    });

    afterEach(() => {
      FileService.getInstance().initDbFileParam();
    });

    afterAll(() => {
      FileService.getInstance().initDbFileParam();
      try { fs.unlinkSync(dbPath); } catch { /* ignore */ }
    });

    // ==================== Error paths (synchronous) ====================

    it('saveDatabase with no database calls onError', 0, () => {
      FileService.getInstance().initDbFileParam();
      const tracker = new SaveCallbackTracker();
      KdbxSaveService.saveDatabase(tracker);
      expect(tracker.errorCount).assertEqual(1);
      expect(tracker.successCount).assertEqual(0);
    });

    it('saveDatabase with no database and no callback does not throw', 0, () => {
      FileService.getInstance().initDbFileParam();
      let threw = false;
      try {
        KdbxSaveService.saveDatabase();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('saveDatabase with RELOAD strategy and no database calls onError', 0, () => {
      FileService.getInstance().initDbFileParam();
      const tracker = new SaveCallbackTracker();
      KdbxSaveService.saveDatabase(tracker, ConflictStrategy.RELOAD);
      expect(tracker.errorCount).assertEqual(1);
    });

    it('saveDatabase with RELOAD strategy and no callback does not throw', 0, () => {
      FileService.getInstance().initDbFileParam();
      let threw = false;
      try {
        KdbxSaveService.saveDatabase(undefined, ConflictStrategy.RELOAD);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('saveDatabaseFromUi with no database calls custom callback onError', 0, () => {
      FileService.getInstance().initDbFileParam();
      const tracker = new SaveCallbackTracker();
      KdbxSaveService.saveDatabaseFromUi(tracker);
      expect(tracker.errorCount).assertEqual(1);
    });

    it('saveDatabaseFromUi with no database and no callback does not throw', 0, () => {
      FileService.getInstance().initDbFileParam();
      let threw = false;
      try {
        KdbxSaveService.saveDatabaseFromUi();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('saveDatabaseFromUi with no database and ToastSaveDatabaseCallback does not throw', 0, () => {
      FileService.getInstance().initDbFileParam();
      const toastCb = new ToastSaveDatabaseCallback();
      let threw = false;
      try {
        KdbxSaveService.saveDatabaseFromUi(toastCb);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    // ==================== Dispatch helpers (synchronous) ====================

    it('onSuccess dispatches to callback.onSuccess', 0, () => {
      const tracker = new SaveCallbackTracker();
      const message = new SuccessMessage(new ArrayBuffer(0), 100, false, 'v1', 'h1');
      KdbxSaveService.onSuccess(message, tracker);
      expect(tracker.successCount).assertEqual(1);
      expect(tracker.lastSuccessMessage!.modifiedTime).assertEqual(100);
    });

    it('onSuccess without callback is a no-op', 0, () => {
      const message = new SuccessMessage(new ArrayBuffer(0), 0, false, null, null);
      let threw = false;
      try {
        KdbxSaveService.onSuccess(message, undefined);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onConflict dispatches to callback.onConflict', 0, () => {
      const tracker = new SaveCallbackTracker();
      const conflict = new ConflictMessage(12345, 'remote-v');
      KdbxSaveService.onConflict(conflict, tracker);
      expect(tracker.conflictCount).assertEqual(1);
      expect(tracker.lastConflictMessage!.remoteModifiedTime).assertEqual(12345);
      expect(tracker.lastConflictMessage!.remoteVersion).assertEqual('remote-v');
    });

    it('onConflict without callback is a no-op', 0, () => {
      const conflict = new ConflictMessage(0, null);
      let threw = false;
      try {
        KdbxSaveService.onConflict(conflict, undefined);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onMessage dispatches to callback.onMessage', 0, () => {
      const tracker = new SaveCallbackTracker();
      const loadMessage = new LoadMessage(MessageType.MESSAGE, 'loading_key');
      KdbxSaveService.onMessage(loadMessage, tracker);
      expect(tracker.messageCount).assertEqual(1);
      expect(tracker.lastMessageString.length > 0).assertTrue();
    });

    it('onMessage without callback is a no-op', 0, () => {
      const loadMessage = new LoadMessage(MessageType.MESSAGE, 'msg');
      let threw = false;
      try {
        KdbxSaveService.onMessage(loadMessage, undefined);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onProgress dispatches to callback.onProgress', 0, () => {
      const tracker = new SaveCallbackTracker();
      const progress = new ProgressMessage(60, 600, 1000);
      KdbxSaveService.onProgress(progress, tracker);
      expect(tracker.progressCount).assertEqual(1);
      expect(tracker.lastProgressMessage !== null).assertTrue();
      expect(tracker.lastProgressMessage!.percent).assertEqual(60);
      expect(tracker.lastProgressMessage!.transferredBytes).assertEqual(600);
    });

    it('onProgress without callback is a no-op', 0, () => {
      let threw = false;
      try {
        KdbxSaveService.onProgress(new ProgressMessage(1, 10, 100), undefined);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onProgress with legacy callback missing onProgress is a no-op', 0, () => {
      // 旧格式回调（未实现 onProgress 可选成员）不受影响
      const legacy: SaveDatabaseCallback = {
        onSuccess: (_message: SuccessMessage): void => {
        }
      };
      let threw = false;
      try {
        KdbxSaveService.onProgress(new ProgressMessage(1, 10, 100), legacy);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onError dispatches to callback.onError', 0, () => {
      const tracker = new SaveCallbackTracker();
      const loadMessage = new LoadMessage(MessageType.ERROR, 'test_error');
      KdbxSaveService.onError(loadMessage, tracker);
      expect(tracker.errorCount).assertEqual(1);
      expect(tracker.lastErrorMessage.length > 0).assertTrue();
    });

    it('onError without callback is a no-op', 0, () => {
      const loadMessage = new LoadMessage(MessageType.ERROR, 'err');
      let threw = false;
      try {
        KdbxSaveService.onError(loadMessage, undefined);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onError with detail composes prefix and detail', 0, () => {
      const tracker = new SaveCallbackTracker();
      const loadMessage = new LoadMessage(MessageType.ERROR, 'kdf_error_prefix', 'bad argon2 version');
      KdbxSaveService.onError(loadMessage, tracker);
      expect(tracker.errorCount).assertEqual(1);
      expect(tracker.lastErrorMessage).assertEqual('kdf_error_prefix: bad argon2 version');
    });

    it('onError without detail passes prefix only', 0, () => {
      const tracker = new SaveCallbackTracker();
      const loadMessage = new LoadMessage(MessageType.ERROR, 'kdf_error_only');
      KdbxSaveService.onError(loadMessage, tracker);
      expect(tracker.errorCount).assertEqual(1);
      expect(tracker.lastErrorMessage).assertEqual('kdf_error_only');
    });

    it('onError with resource-id message appends detail after localized prefix', 0, () => {
      // 复用 kdbxErrorPayload 生成资源 ID 载体（FileCorrupt → kdbx_error_FileCorrupt）
      let payload: string | number = '';
      try {
        throw new KdbxError(Consts.ErrorCodes.FileCorrupt, 'x');
      } catch (e) {
        payload = KdbxUtils.kdbxErrorPayload(e);
      }
      const tracker = new SaveCallbackTracker();
      const loadMessage = new LoadMessage(MessageType.ERROR, payload, 'bad argon2 version');
      KdbxSaveService.onError(loadMessage, tracker);
      // 前缀是否本地化取决于 ResourceManager 上下文，断言仅锁定明细拼接位置
      expect(tracker.lastErrorMessage.endsWith(': bad argon2 version')).assertTrue();
    });

    // ==================== callbackWarp (synchronous) ====================

    it('callbackWarp onError calls callback onError and release', 0, () => {
      const tracker = new SaveCallbackTracker();
      let released = false;
      const wrapped = KdbxSaveService.callbackWarp(tracker, () => { released = true; });
      wrapped.onError?.('warp-error');
      expect(tracker.errorCount).assertEqual(1);
      expect(tracker.lastErrorMessage).assertEqual('warp-error');
      expect(released).assertTrue();
    });

    it('callbackWarp onError clears pending credential change fields', 0, () => {
      // F1 回归：改密保存失败后，待应用的改密凭证字段（newPassword/notUseKeyFile 等）
      // 必须被清理，否则残留字段会被后续普通保存静默应用，导致非预期改密（用户被锁在库外）
      FileService.getInstance().initDbFileParam();
      const param = FileService.getDbFileParam();
      param.newPassword = 'NewPass!23';
      param.notUseKeyFile = true;

      const tracker = new SaveCallbackTracker();
      let released = false;
      const wrapped = KdbxSaveService.callbackWarp(tracker, () => { released = true; });
      wrapped.onError?.('save-failed');

      expect(tracker.errorCount).assertEqual(1);
      expect(tracker.lastErrorMessage).assertEqual('save-failed');
      expect(released).assertTrue();
      expect(param.newPassword).assertUndefined();
      expect(param.notUseKeyFile).assertFalse();
    });

    it('callbackWarp onMessage passes through to callback', 0, () => {
      const tracker = new SaveCallbackTracker();
      let released = false;
      const wrapped = KdbxSaveService.callbackWarp(tracker, () => { released = true; });
      wrapped.onMessage?.('warp-message');
      expect(tracker.messageCount).assertEqual(1);
      expect(tracker.lastMessageString).assertEqual('warp-message');
      expect(released).assertFalse();
    });

    it('callbackWarp onProgress passes through without release', 0, () => {
      const tracker = new SaveCallbackTracker();
      let released = false;
      const wrapped = KdbxSaveService.callbackWarp(tracker, () => { released = true; });
      wrapped.onProgress?.(new ProgressMessage(33, 330, 1000));
      expect(tracker.progressCount).assertEqual(1);
      expect(tracker.lastProgressMessage !== null).assertTrue();
      expect(tracker.lastProgressMessage!.percent).assertEqual(33);
      // 进度为非终态消息，不释放保存互斥锁
      expect(released).assertFalse();
    });

    it('callbackWarp onConflict calls release', 0, () => {
      const tracker = new SaveCallbackTracker();
      let released = false;
      const wrapped = KdbxSaveService.callbackWarp(tracker, () => { released = true; });
      const conflict = new ConflictMessage(999, 'conflict-v');
      wrapped.onConflict?.(conflict);
      expect(released).assertTrue();
    });

    it('callbackWarp onSuccess non-merge calls handleSuccess and callback', 0, () => {
      const database = Kdbx.create(new KdbxCredentials(ProtectedValue.fromString('test')), 'WarpDb');
      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, '/test.kdbx', 'test.kdbx', null, null);
      FileService.setDbFileParam(dbFileParam);

      const tracker = new SaveCallbackTracker();
      let released = false;
      const wrapped = KdbxSaveService.callbackWarp(tracker, () => { released = true; });
      const message = new SuccessMessage(new ArrayBuffer(0), 555, false, 'warp-v', 'warp-h');
      wrapped.onSuccess?.(message);

      expect(tracker.successCount).assertEqual(1);
      expect(released).assertTrue();
      expect(FileService.getDbFileParam().modifiedTime).assertEqual(555);
      expect(FileService.getDbFileParam().version).assertEqual('warp-v');
      expect(FileService.getDbFileParam().contentHash).assertEqual('warp-h');
    });

    it('callbackWarp without inner callback does not throw on onError', 0, () => {
      let released = false;
      const wrapped = KdbxSaveService.callbackWarp(undefined, () => { released = true; });
      let threw = false;
      try {
        wrapped.onError?.('no-inner');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(released).assertTrue();
    });

    // ==================== handleSuccess ====================

    it('handleSuccess non-merge updates baseline and calls callback', 0, () => {
      const database = Kdbx.create(new KdbxCredentials(ProtectedValue.fromString('test')), 'HandleDb');
      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, '/test.kdbx', 'test.kdbx', null, null);
      FileService.setDbFileParam(dbFileParam);

      const tracker = new SaveCallbackTracker();
      let released = false;
      const message = new SuccessMessage(new ArrayBuffer(0), 777, false, 'hs-v', 'hs-h');

      KdbxSaveService.handleSuccess(message, tracker, () => { released = true; });

      expect(tracker.successCount).assertEqual(1);
      expect(released).assertTrue();
      expect(FileService.getDbFileParam().modifiedTime).assertEqual(777);
      expect(FileService.getDbFileParam().version).assertEqual('hs-v');
      expect(FileService.getDbFileParam().contentHash).assertEqual('hs-h');
    });

    it('handleSuccess merge updates database in dbFileParam', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('MergeHandleDb', 'merge-handle-entry');
      const savedBuffer: ArrayBuffer = await database.save();
      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, dbPath, 'merge-handle.kdbx', null, null);
      FileService.setDbFileParam(dbFileParam);

      const tracker = new SaveCallbackTracker();
      let released = false;
      const message = new SuccessMessage(savedBuffer, 888, true, 'merge-v', 'merge-h');

      await withTimeout(new Promise<void>((resolve, reject) => {
        KdbxSaveService.handleSuccess(message, {
          onSuccess: (msg: SuccessMessage) => {
            tracker.onSuccess(msg);
            resolve();
          },
          onError: (err: string) => {
            tracker.onError(err);
            reject(new Error(err));
          }
        }, () => { released = true; });
      }), TEST_TIMEOUT_MS);

      expect(tracker.successCount).assertEqual(1);
      expect(released).assertTrue();
      expect(FileService.getDbFileParam().modifiedTime).assertEqual(888);
      expect(FileService.getDbFileParam().version).assertEqual('merge-v');
      expect(FileService.getDbFileParam().contentHash).assertEqual('merge-h');
      const newDb = FileService.getDbFileParam().database;
      expect(newDb instanceof Kdbx).assertTrue();
      const titles = KdbxModeTestHelper.collectEntryTitles(newDb);
      expect(titles.includes('merge-handle-entry')).assertTrue();
    });

    it('handleSuccess without callback does not throw (non-merge)', 0, () => {
      const database = Kdbx.create(new KdbxCredentials(ProtectedValue.fromString('t')), 'NoCb');
      FileService.setDbFileParam(KdbxModeTestHelper.makeDbFileParam(database, '/t.kdbx', 't.kdbx', null, null));
      let released = false;
      const message = new SuccessMessage(new ArrayBuffer(0), 0, false, null, null);
      let threw = false;
      try {
        KdbxSaveService.handleSuccess(message, undefined, () => { released = true; });
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(released).assertTrue();
    });

    // ==================== addCustomIcon ====================

    it('addCustomIcon with empty images calls onError', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('IconEmptyDb', 'icon-empty-entry');
      FileService.getInstance().initDbFileParam();
      const tracker = new SaveCallbackTracker();
      await KdbxSaveService.addCustomIcon(database, [], tracker);
      expect(tracker.errorCount > 0).assertTrue();
      expect(tracker.lastErrorMessage).assertEqual('Invalid database or base64 image');
    });

    it('addCustomIcon with invalid base64 calls onError per image', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('IconInvalidDb', 'icon-invalid-entry');
      FileService.getInstance().initDbFileParam();
      const tracker = new SaveCallbackTracker();
      const initialIconCount = database.meta.customIcons.size;
      await KdbxSaveService.addCustomIcon(database, ['no-comma-data', 'also-no-comma'], tracker);
      expect(database.meta.customIcons.size).assertEqual(initialIconCount);
      expect(tracker.errorCount >= 1).assertTrue();
    });

    it('addCustomIcon with valid base64 adds icons and triggers save', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('IconValidDb', 'icon-valid-entry');
      FileService.getInstance().initDbFileParam();
      const tracker = new SaveCallbackTracker();
      const initialIconCount = database.meta.customIcons.size;
      const validBase64 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      await KdbxSaveService.addCustomIcon(database, [validBase64], tracker);
      expect(database.meta.customIcons.size).assertEqual(initialIconCount + 1);
      expect(tracker.errorCount > 0).assertTrue();
    });

    it('addCustomIcon with mix of valid and invalid base64 adds only valid icons', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('IconMixDb', 'icon-mix-entry');
      FileService.getInstance().initDbFileParam();
      const tracker = new SaveCallbackTracker();
      const initialIconCount = database.meta.customIcons.size;
      const validBase64 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      await KdbxSaveService.addCustomIcon(database, ['invalid-no-comma', validBase64], tracker);
      expect(database.meta.customIcons.size).assertEqual(initialIconCount + 1);
    });

    it('addCustomIcon with no callback does not throw on error', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('IconNoCbDb', 'icon-nocb-entry');
      FileService.getInstance().initDbFileParam();
      let threw = false;
      try {
        await KdbxSaveService.addCustomIcon(database, [], undefined);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    // ==================== End-to-end save (async, worker) ====================

    it('saveDatabaseAsync writes file and calls onSuccess', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('AsyncSaveDb', 'async-save-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      const baseHash = await KdbxModeTestHelper.sha256Hex(initialContent);

      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, dbPath, 'async-save.kdbx', null, baseHash);
      const saveReq = new SaveDatabaseMessage(database, dbFileParam, ConflictStrategy.AUTO);

      KdbxModeTestHelper.addEntry(database, 'async-local-entry');

      let releaseCalled = false;
      const result = await withTimeout(new Promise<AsyncSaveCheckResult>(
        (resolve) => {
          KdbxSaveService.saveDatabaseAsync(saveReq, {
            onSuccess: (msg: SuccessMessage) => { resolve({ success: true, error: '', message: msg }); },
            onError: (err: string) => { resolve({ success: false, error: err, message: null }); }
          }, () => { releaseCalled = true; }).catch((error: Error) => {
            resolve({ success: false, error: error.message, message: null });
          });
        }
      ), TEST_TIMEOUT_MS);

      expect(result.success).assertTrue();
      expect(result.message !== null).assertTrue();
      expect(result.message!.isMerge).assertFalse();
      expect(result.message!.contentHash !== null).assertTrue();
      expect(result.message!.version !== null).assertTrue();

      const fileContent = await fileManager.read(dbPath);
      const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
      const persisted = await Kdbx.load(fileContent.content, credentials);
      const titles = KdbxModeTestHelper.collectEntryTitles(persisted);
      expect(titles.includes('async-save-entry')).assertTrue();
      expect(titles.includes('async-local-entry')).assertTrue();
    });

    it('saveDatabase writes file and updates baseline', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('E2ESaveDb', 'e2e-save-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      const baseHash = await KdbxModeTestHelper.sha256Hex(initialContent);

      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, dbPath, 'e2e-save.kdbx', null, baseHash);
      FileService.setDbFileParam(dbFileParam);

      KdbxModeTestHelper.addEntry(database, 'e2e-local-entry');

      const result = await withTimeout(new Promise<SaveCheckResult>(
        (resolve) => {
          KdbxSaveService.saveDatabase({
            onSuccess: (msg: SuccessMessage) => { resolve({ success: true, error: '' }); },
            onError: (err: string) => { resolve({ success: false, error: err }); }
          });
        }
      ), TEST_TIMEOUT_MS);

      expect(result.success).assertTrue();

      const fileContent = await fileManager.read(dbPath);
      const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
      const persisted = await Kdbx.load(fileContent.content, credentials);
      const titles = KdbxModeTestHelper.collectEntryTitles(persisted);
      expect(titles.includes('e2e-save-entry')).assertTrue();
      expect(titles.includes('e2e-local-entry')).assertTrue();

      const updatedParam = FileService.getDbFileParam();
      expect(updatedParam.modifiedTime > 0).assertTrue();
      expect(updatedParam.version !== null).assertTrue();
      expect(updatedParam.contentHash !== null).assertTrue();
    });

    it('saveDatabase with AUTO strategy and remote change reports conflict', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('ConflictDb', 'conflict-base-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      const baseHash = await KdbxModeTestHelper.sha256Hex(initialContent);

      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, dbPath, 'conflict.kdbx', null, baseHash);
      FileService.setDbFileParam(dbFileParam);

      await KdbxModeTestHelper.writeRemoteModification(fileManager, dbPath, 'remote-conflict-entry');
      KdbxModeTestHelper.addEntry(database, 'local-conflict-entry');

      const result = await withTimeout(new Promise<ConflictCheckResult>(
        (resolve) => {
          KdbxSaveService.saveDatabase({
            onSuccess: (msg: SuccessMessage) => { resolve({ conflict: false, error: '' }); },
            onError: (err: string) => { resolve({ conflict: false, error: err }); },
            onConflict: (msg: ConflictMessage) => { resolve({ conflict: true, error: '' }); }
          });
        }
      ), TEST_TIMEOUT_MS);

      expect(result.conflict).assertTrue();

      const fileContent = await fileManager.read(dbPath);
      const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
      const remote = await Kdbx.load(fileContent.content, credentials);
      const titles = KdbxModeTestHelper.collectEntryTitles(remote);
      expect(titles.includes('remote-conflict-entry')).assertTrue();
      expect(titles.includes('local-conflict-entry')).assertFalse();
    });

    // ==================== RELOAD 策略与改密意图（F4 回归） ====================

    it('saveDatabase RELOAD with pending credential change reports abandoned error', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('ReloadPendDb', 'reload-pend-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      const baseHash = await KdbxModeTestHelper.sha256Hex(initialContent);

      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, dbPath, 'reload-pend.kdbx', null, baseHash);
      FileService.setDbFileParam(dbFileParam);
      // 模拟改密页发起保存前写入的待应用凭证字段
      FileService.getDbFileParam().newPassword = 'NewPass!23';
      FileService.getDbFileParam().notUseKeyFile = true;

      const result = await withTimeout(new Promise<SaveCheckResult>(
        (resolve) => {
          KdbxSaveService.saveDatabase({
            onSuccess: (msg: SuccessMessage) => { resolve({ success: true, error: '' }); },
            onError: (err: string) => { resolve({ success: false, error: err }); }
          }, ConflictStrategy.RELOAD);
        }
      ), TEST_TIMEOUT_MS);

      // F4：改密意图随重载被放弃 → 回调 onError（改密页停留提示），不得误报 onSuccess
      expect(result.success).assertFalse();
      expect(result.error.length > 0).assertTrue();
      // F1：待应用凭证字段已清理
      const param = FileService.getDbFileParam();
      expect(param.newPassword).assertUndefined();
      expect(param.notUseKeyFile).assertFalse();
    });

    it('saveDatabase RELOAD without pending change still calls onSuccess', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('ReloadPlainDb', 'reload-plain-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      const baseHash = await KdbxModeTestHelper.sha256Hex(initialContent);

      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, dbPath, 'reload-plain.kdbx', null, baseHash);
      FileService.setDbFileParam(dbFileParam);

      const result = await withTimeout(new Promise<SaveCheckResult>(
        (resolve) => {
          KdbxSaveService.saveDatabase({
            onSuccess: (msg: SuccessMessage) => { resolve({ success: true, error: '' }); },
            onError: (err: string) => { resolve({ success: false, error: err }); }
          }, ConflictStrategy.RELOAD);
        }
      ), TEST_TIMEOUT_MS);

      // 普通保存的 RELOAD（放弃本地修改）语义不变：重载成功回调 onSuccess
      expect(result.success).assertTrue();
      const param = FileService.getDbFileParam();
      expect(param.newPassword).assertUndefined();
    });

    // ==================== 零分量凭证防御（漏洞 #1 回归） ====================

    it('saveDatabase with keyfile-only switch and notUseKeyFile blocked as empty credentials', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('EmptyCredDb', 'empty-cred-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      const baseHash = await KdbxModeTestHelper.sha256Hex(initialContent);

      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, dbPath, 'empty-cred.kdbx', null, baseHash);
      FileService.setDbFileParam(dbFileParam);
      // 模拟双勾状态：仅密钥文件切换（newPassword=''）+ 不使用密钥文件
      FileService.getDbFileParam().newPassword = '';
      FileService.getDbFileParam().notUseKeyFile = true;

      const result = await withTimeout(new Promise<SaveCheckResult>(
        (resolve) => {
          KdbxSaveService.saveDatabase({
            onSuccess: (msg: SuccessMessage) => { resolve({ success: true, error: '' }); },
            onError: (err: string) => { resolve({ success: false, error: err }); }
          });
        }
      ), TEST_TIMEOUT_MS);

      // 纵深防御：拦截不落盘、回调 onError、待应用字段清理（F1 不变量）
      expect(result.success).assertFalse();
      expect(result.error.length > 0).assertTrue();
      const param = FileService.getDbFileParam();
      expect(param.newPassword).assertUndefined();
      expect(param.notUseKeyFile).assertFalse();
      // 文件未被改写：仍可凭原密码解锁
      const fileContent = await fileManager.read(dbPath);
      const reloaded = await Kdbx.load(fileContent.content,
        new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD)));
      expect(KdbxModeTestHelper.collectEntryTitles(reloaded).includes('empty-cred-entry')).assertTrue();
    });
  });
}
