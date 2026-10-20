import { beforeAll, afterAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Consts, Kdbx, KdbxCredentials, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { StorageType } from '../../../../main/ets/storage';
import { DatabaseLoadWorker } from '../../../../main/ets/workers/DatabaseLoadWorker';
import { DatabaseSaveWorker } from '../../../../main/ets/workers/DatabaseSaveWorker';
import { LoadDatabase } from '../../../../main/ets/workers/DatabaseLoadWorkerParam';
import { ConflictStrategy } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import {
  ConflictMessage,
  MessageType,
  PrewarmMessage,
  PrewarmResultMessage,
  ProgressMessage,
  SuccessMessage,
  TokenSnapshot,
  toErrorMessage,
  toLoadMessage
} from '../../../../main/ets/workers/WorkerParam';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { OAuth2Provider } from '../../../../main/ets/common/oauth2/OAuth2Types';
import { KdbxModeTestHelper } from './KdbxModeTestHelper';

/**
 * Worker 适配类与消息类主线程覆盖：
 * - DatabaseLoadWorker / DatabaseSaveWorker 在主线程实例化后 post* 走 workerPort 空对象
 *   try→throw→catch→showToast 吞错链路（业务流程照常完成，仅消息投递降级）
 * - handlePrewarm 探测远端文件信息（结果经 workerPort 投递失败仅日志）
 * - WorkerParam 消息类构造与工厂（TokenSnapshot / PrewarmResultMessage / toLoadMessage / toErrorMessage）
 */
export default function WorkerMessageCoverageTest() {
  describe('WorkerMessageCoverage', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let loadWorkerPath: string;
    let saveWorkerPath: string;
    const loadWorkerName: string = 'db-worker-message-load.kdbx';
    const saveWorkerName: string = 'db-worker-message-save.kdbx';

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      loadWorkerPath = appContext.filesDir + '/' + loadWorkerName;
      saveWorkerPath = appContext.filesDir + '/' + saveWorkerName;

      const loadDatabase: Kdbx = await KdbxModeTestHelper.createDatabase('WorkerMessageLoadDb', 'worker-message-load-entry');
      await fileManager.write(loadWorkerPath, await loadDatabase.save());

      const saveDatabase: Kdbx = await KdbxModeTestHelper.createDatabase('WorkerMessageSaveDb', 'worker-message-save-entry');
      saveDatabase.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
      await fileManager.write(saveWorkerPath, await saveDatabase.save());
    });

    afterAll(() => {
      for (const p of [loadWorkerPath, saveWorkerPath]) {
        try {
          fs.unlinkSync(p);
        } catch {
          // 文件不存在：忽略
        }
      }
    });

    it('database load worker handles full load on main thread with swallowed post errors', 0, async () => {
      const param: LoadDatabase = KdbxModeTestHelper.makeLoadParam(
        loadWorkerPath, loadWorkerName, KdbxModeTestHelper.DB_PASSWORD);
      // AES 库：容器直传抛 Unsupported 回退全模型路径，
      // postSuccessMessage 内 Kdbx→M0 会话文件包裹后经 workerPort 投递失败被吞
      await new DatabaseLoadWorker().handleLoadDatabase(param);
    });

    it('database load worker handlePrewarm probes file info without crash', 0, async () => {
      const prewarm: PrewarmMessage = new PrewarmMessage(loadWorkerPath, StorageType.LOCAL, {});
      await new DatabaseLoadWorker().handlePrewarm(prewarm);
    });

    it('database load worker handlePrewarm reports unregistered storage as error', 0, async () => {
      // PCLOUD 在 FileStorageFactory 中被注释未注册：KdbxFileManager 构造抛错进入 handlePrewarm 的 catch
      const prewarm: PrewarmMessage = new PrewarmMessage('/data/db/none.kdbx', StorageType.PCLOUD, {});
      await new DatabaseLoadWorker().handlePrewarm(prewarm);
    });

    it('database load worker direct post calls do not crash', 0, async () => {
      const worker: DatabaseLoadWorker = new DatabaseLoadWorker();
      worker.postMessage('direct-load-stage');
      worker.postErrorMessage('direct-load-error');
      worker.postProgressMessage(new ProgressMessage(7, 1, 100));
      await worker.postSuccessMessage(new SuccessMessage(new ArrayBuffer(4), 0, false, null, 'hash'));
    });

    it('database save worker saves chacha20 database on main thread with swallowed post errors', 0, async () => {
      const database: Kdbx = await KdbxModeTestHelper.createDatabase('WorkerMessageSaveDb2', 'worker-message-save-entry-2');
      database.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
      KdbxModeTestHelper.addEntry(database, 'worker-message-save-entry-3');

      await new DatabaseSaveWorker().handleSaveDatabase(
        KdbxModeTestHelper.makeSaveMessage(database, saveWorkerPath, saveWorkerName, null, null, ConflictStrategy.AUTO));

      const saved = await fileManager.read(saveWorkerPath);
      const reopened: Kdbx = await Kdbx.load(saved.content,
        new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD)));
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(reopened);
      expect(titles.includes('worker-message-save-entry-2')).assertTrue();
      expect(titles.includes('worker-message-save-entry-3')).assertTrue();
    });

    it('database save worker direct post calls do not crash', 0, () => {
      const worker: DatabaseSaveWorker = new DatabaseSaveWorker();
      worker.postMessage('direct-save-stage');
      worker.postProgressMessage(new ProgressMessage(9, 1, 100));
      worker.postErrorMessage('direct-save-error', 'detail-text');
      worker.postSuccessMessage(new SuccessMessage(new ArrayBuffer(0), 0, false, null, 'hash'));
      worker.postConflictMessage(new ConflictMessage(111, 'v9'));
    });

    it('token snapshot carries oauth2 credential fields', 0, () => {
      const snapshot: TokenSnapshot = new TokenSnapshot(OAuth2Provider.GITHUB,
        'access-token-1', 'refresh-token-1', 1893456000000, 'Bearer', 'scope-1');
      expect(snapshot.provider).assertEqual(OAuth2Provider.GITHUB);
      expect(snapshot.accessToken).assertEqual('access-token-1');
      expect(snapshot.refreshToken).assertEqual('refresh-token-1');
      expect(snapshot.expiresAt).assertEqual(1893456000000);
      expect(snapshot.tokenType).assertEqual('Bearer');
      expect(snapshot.scope).assertEqual('scope-1');
    });

    it('prewarm result message carries file probe facts', 0, () => {
      const result: PrewarmResultMessage = new PrewarmResultMessage('/data/db/x.kdbx', 123, 'v2', 'probe-error');
      expect(result.type).assertEqual(MessageType.PREWARM_RESULT);
      expect(result.filePath).assertEqual('/data/db/x.kdbx');
      expect(result.size).assertEqual(123);
      expect(result.version).assertEqual('v2');
      expect(result.error).assertEqual('probe-error');

      const minimal: PrewarmResultMessage = new PrewarmResultMessage('/data/db/y.kdbx');
      expect(minimal.version).assertNull();
    });

    it('toLoadMessage maps string and resource payloads', 0, () => {
      const fromString = toLoadMessage('creating_key');
      expect(fromString.type).assertEqual(MessageType.MESSAGE);
      expect(fromString.message).assertEqual('creating_key');

      const fromResource = toLoadMessage($r('app.string.database_too_large'));
      expect(fromResource.type).assertEqual(MessageType.MESSAGE);
      expect(typeof fromResource.message === 'number').assertTrue();
    });

    it('toErrorMessage keeps payload and detail', 0, () => {
      const plain = toErrorMessage('plain-error');
      expect(plain.type).assertEqual(MessageType.ERROR);
      expect(plain.message).assertEqual('plain-error');

      const detailed = toErrorMessage('detailed-error', 'detail-text');
      expect(detailed.message).assertEqual('detailed-error');
      expect(detailed.detail).assertEqual('detail-text');
    });
  });
}
