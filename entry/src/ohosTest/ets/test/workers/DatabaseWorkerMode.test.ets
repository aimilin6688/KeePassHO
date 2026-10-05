import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { worker } from '@kit.ArkTS';
import { Kdbx, KdbxCredentials, KdbxSnapshot, ProtectedValue } from 'kdbxweb';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { ConflictStrategy } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { StorageType } from '../../../../main/ets/storage';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { ConflictMessage, LoadMessage, MessageType, SuccessMessage, WorkerMessage } from '../../../../main/ets/workers/WorkerParam';
import { KdbxModeTestHelper } from './KdbxModeTestHelper';

const DOMAIN = 0x0000;
const TAG = 'DatabaseWorkerModeTest';

/**
 * 数据库 Worker 异步模式单元测试（Constants.ASYNC_LOAD/SAVE_DATABASE = true 的线程路径）。
 *
 * 真实启动 ThreadWorker（DatabaseLoadWorker / DatabaseSaveWorker），走完整消息链路：
 * 主线程序列化 → worker 线程加载/保存/冲突处理 → postMessage 回传。
 * 覆盖 Worker 边界序列化往返、异步加载（成功/凭证错误）、异步保存（无冲突条件写入、
 * MERGE 双方合并）。数据库与文件全部真实构造，不使用 mock 数据。
 */
export default function DatabaseWorkerModeTest() {
  describe('DatabaseWorkerModeTest', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let database: Kdbx;
    let dbPath: string;
    let baseVersion: string | null = null;
    let baseHash: string | null = null;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      dbPath = appContext.filesDir + '/db-worker-mode-test.kdbx';

      // 构造真实数据库（真实加密）并写入本地真实文件
      database = await KdbxModeTestHelper.createDatabase('WorkerModeDb', 'worker-base-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      baseHash = await KdbxModeTestHelper.sha256Hex(initialContent);
    });

    it('worker boundary serialization roundtrip keeps entries', 0, async () => {
      // 异步模式的跨线程边界：Kdbx 对象序列化为 KPSN 二进制快照 ArrayBuffer
      const buffer: ArrayBuffer = await KdbxUtils.kdbxToArrayBuffer(database);
      expect(buffer instanceof ArrayBuffer).assertTrue();
      expect(KdbxSnapshot.isSnapshot(buffer)).assertTrue();
      expect(buffer.byteLength > 0).assertTrue();

      // 主线程从 ArrayBuffer 还原为 Kdbx 对象（KPSN 快照直达路径）
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'db-worker-mode-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);
      const restored: Kdbx = await KdbxUtils.arrayBufferToKdbx(buffer, loadParam);

      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(restored);
      expect(titles.includes('worker-base-entry')).assertTrue();
    });

    it('worker load success returns serialized database', 0, async () => {
      const w: worker.ThreadWorker = KdbxModeTestHelper.createLoadWorker();
      try {
        const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'db-worker-mode-test.kdbx',
          KdbxModeTestHelper.DB_PASSWORD);
        const pending = KdbxModeTestHelper.waitWorkerResult(w, KdbxModeTestHelper.WORKER_TIMEOUT);
        // 加载链路：主线程 JSON 序列化参数发往 worker
        w.postMessage(JSON.stringify(loadParam));

        const message: WorkerMessage = await pending;
        expect(message.type).assertEqual(MessageType.SUCCESS);

        // 异步模式：data 为跨线程传输的 KPSN 快照 ArrayBuffer，非 Kdbx 引用
        const success = message as SuccessMessage;
        expect(success.data instanceof ArrayBuffer).assertTrue();
        expect(KdbxSnapshot.isSnapshot(success.data as ArrayBuffer)).assertTrue();

        // 还原后条目完整
        const restored: Kdbx = await KdbxUtils.arrayBufferToKdbx(success.data as ArrayBuffer, loadParam);
        const titles: string[] = KdbxModeTestHelper.collectEntryTitles(restored);
        expect(titles.includes('worker-base-entry')).assertTrue();
        // 内容哈希基线随消息回传
        expect(success.contentHash).assertEqual(baseHash);
        // 非合并保存不附带合并模型快照
        expect(success.snapshot).assertUndefined();
      } finally {
        w.terminate();
      }
    });

    it('worker load with wrong password reports error', 0, async () => {
      const w: worker.ThreadWorker = KdbxModeTestHelper.createLoadWorker();
      try {
        const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'db-worker-mode-test.kdbx', 'wrong-password');
        const pending = KdbxModeTestHelper.waitWorkerResult(w, KdbxModeTestHelper.WORKER_TIMEOUT);
        w.postMessage(JSON.stringify(loadParam));

        const message: WorkerMessage = await pending;
        expect(message.type).assertEqual(MessageType.ERROR);
        const errorMessage = message as LoadMessage;
        expect(String(errorMessage.message).length > 0).assertTrue();
      } finally {
        w.terminate();
      }
    });

    it('worker save without conflict writes file', 0, async () => {
      // 本地修改
      KdbxModeTestHelper.addEntry(database, 'worker-local-entry');
      // 异步模式边界：先在主线程把 Kdbx 序列化为 ArrayBuffer（与 KdbxSaveService.saveDatabaseAsync 一致）
      const saveMessage = KdbxModeTestHelper.makeSaveMessage(database, dbPath, 'db-worker-mode-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.AUTO);
      saveMessage.data = await KdbxUtils.kdbxToArrayBuffer(database);

      const w: worker.ThreadWorker = KdbxModeTestHelper.createSaveWorker();
      try {
        const pending = KdbxModeTestHelper.waitWorkerResult(w, KdbxModeTestHelper.WORKER_TIMEOUT);
        // transfer list 零拷贝传输 ArrayBuffer
        w.postMessage(saveMessage, [saveMessage.data as ArrayBuffer]);

        const message: WorkerMessage = await pending;
        expect(message.type).assertEqual(MessageType.SUCCESS);
        const success = message as SuccessMessage;
        expect(success.isMerge).assertFalse();
        // 非合并保存不附带合并模型快照
        expect(success.snapshot).assertUndefined();
        expect((success.version ?? '').includes('|')).assertTrue();

        // 文件已被真实写入
        const fileContent = await fileManager.read(dbPath);
        const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
        const persisted = await Kdbx.load(fileContent.content, credentials);
        const titles: string[] = KdbxModeTestHelper.collectEntryTitles(persisted);
        expect(titles.includes('worker-base-entry')).assertTrue();
        expect(titles.includes('worker-local-entry')).assertTrue();

        // 更新基线
        baseVersion = success.version ?? null;
        baseHash = success.contentHash ?? null;
      } finally {
        w.terminate();
      }
    });

    it('worker save with MERGE strategy keeps both sides', 0, async () => {
      // 他设备修改远端文件
      await KdbxModeTestHelper.writeRemoteModification(fileManager, dbPath, 'worker-remote-entry');
      // 本地同时修改
      KdbxModeTestHelper.addEntry(database, 'worker-merge-entry');
      const saveMessage = KdbxModeTestHelper.makeSaveMessage(database, dbPath, 'db-worker-mode-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.MERGE);
      saveMessage.data = await KdbxUtils.kdbxToArrayBuffer(database);

      const w: worker.ThreadWorker = KdbxModeTestHelper.createSaveWorker();
      try {
        const pending = KdbxModeTestHelper.waitWorkerResult(w, KdbxModeTestHelper.WORKER_TIMEOUT);
        w.postMessage(saveMessage, [saveMessage.data as ArrayBuffer]);

        const message: WorkerMessage = await pending;
        expect(message.type).assertEqual(MessageType.SUCCESS);
        const success = message as SuccessMessage;
        expect(success.isMerge).assertTrue();

        // 合并快照回传：isMerge 时附带 KPSN 快照，主线程免解密重解析直接还原合并模型
        expect(success.snapshot instanceof ArrayBuffer).assertTrue();
        expect(KdbxSnapshot.isSnapshot(success.snapshot)).assertTrue();
        if (success.snapshot) {
          const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'db-worker-mode-test.kdbx',
            KdbxModeTestHelper.DB_PASSWORD);
          const mergedModel: Kdbx = await KdbxUtils.arrayBufferToKdbx(success.snapshot, loadParam);
          const mergedTitles: string[] = KdbxModeTestHelper.collectEntryTitles(mergedModel);
          expect(mergedTitles.includes('worker-remote-entry')).assertTrue();
          expect(mergedTitles.includes('worker-merge-entry')).assertTrue();
        }

        // 合并结果已写入文件：双方条目都在
        const fileContent = await fileManager.read(dbPath);
        const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
        const merged = await Kdbx.load(fileContent.content, credentials);
        const titles: string[] = KdbxModeTestHelper.collectEntryTitles(merged);
        expect(titles.includes('worker-remote-entry')).assertTrue();
        expect(titles.includes('worker-merge-entry')).assertTrue();

        // 更新基线
        baseVersion = success.version ?? null;
        baseHash = success.contentHash ?? null;
      } finally {
        w.terminate();
      }
    });

    it('worker save with remote change reports conflict in AUTO strategy', 0, async () => {
      // 他设备修改远端文件
      await KdbxModeTestHelper.writeRemoteModification(fileManager, dbPath, 'worker-remote-conflict');
      // 本地同时修改
      KdbxModeTestHelper.addEntry(database, 'worker-auto-entry');
      const saveMessage = KdbxModeTestHelper.makeSaveMessage(database, dbPath, 'db-worker-mode-test.kdbx',
        baseVersion, baseHash, ConflictStrategy.AUTO);
      saveMessage.data = await KdbxUtils.kdbxToArrayBuffer(database);

      const w: worker.ThreadWorker = KdbxModeTestHelper.createSaveWorker();
      try {
        const pending = KdbxModeTestHelper.waitWorkerResult(w, KdbxModeTestHelper.WORKER_TIMEOUT);
        w.postMessage(saveMessage, [saveMessage.data as ArrayBuffer]);

        const message: WorkerMessage = await pending;
        // AUTO 策略：worker 上报冲突，本次不写入
        expect(message.type).assertEqual(MessageType.CONFLICT);
        const conflict = message as ConflictMessage;
        expect(conflict.remoteModifiedTime > 0).assertTrue();

        // 远端文件保持他设备版本
        const fileContent = await fileManager.read(dbPath);
        const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
        const remote = await Kdbx.load(fileContent.content, credentials);
        const titles: string[] = KdbxModeTestHelper.collectEntryTitles(remote);
        expect(titles.includes('worker-remote-conflict')).assertTrue();
        expect(titles.includes('worker-auto-entry')).assertFalse();
      } finally {
        w.terminate();
      }
    });
  });
}
