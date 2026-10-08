import { afterAll, afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Kdbx, KdbxSnapshot } from 'kdbxweb';
import KdbxLoadService from '../../../../main/ets/services/kdbx/KdbxLoadService';
import KdbxSaveService from '../../../../main/ets/services/kdbx/KdbxSaveService';
import { FileService } from '../../../../main/ets/services/FileService';
import { SessionFileService } from '../../../../main/ets/services/kdbx/SessionFileService';
import { CacheConstants } from '../../../../main/ets/storage/cache/CacheConstants';
import { Constants } from '../../../../main/ets/common/constants/Constants';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { DatabaseWorkerFactory } from '../../../../main/ets/workers/DatabaseWorkerFactory';
import { LoadDatabase } from '../../../../main/ets/workers/DatabaseLoadWorkerParam';
import { ConflictStrategy, SaveDatabaseMessage } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { StorageType } from '../../../../main/ets/storage';
import { ConflictMessage, LoadMessage, MessageType, SuccessMessage, WorkerMessage } from '../../../../main/ets/workers/WorkerParam';
import { KdbxModeTestHelper } from './KdbxModeTestHelper';

const TEST_TIMEOUT_MS: number = 60000;
// terminate → onexit 回调的等待余量：冷启动（首个测试进程）下 isolate 退出事件更慢，取 1s
const WORKER_EXIT_WAIT_MS: number = 1000;

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_resolve, reject) =>
      setTimeout(() => reject(new Error('Test timed out after ' + timeoutMs + 'ms')), timeoutMs)
    )
  ]);
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
}

/**
 * Worker 常驻池化（性能优化 #3）单元测试。
 *
 * 协议层覆盖：
 * - attachCachePolicy 三字段正确写入任务消息
 * - forceRefresh 一次性语义：attach 消费一次后主线程标志复位
 * - 未经 attach 的旧格式消息三字段保持 undefined（兼容测试直连构造）
 * - LoadDatabase 策略字段经 JSON 序列化往返保留（加载通道线格式兼容）
 * - SaveDatabaseMessage 策略字段写入且不污染 dbFileParam JSON 载荷
 * - 池化加载忙拒绝：在途加载期间的新请求立即回 worker_busy（防双击两次导航）
 *
 * 生命周期覆盖：
 * - 常驻复用：连续两次加载不 stopWorker，第二次走复用分支成功
 * - 壳任务串行：同一常驻 Worker 连投两条 LOAD，taskChain 串行执行且结果不串
 * - 异常自愈：在途终止（onexit）释放忙标志，下次操作懒重建成功
 * - 保存池化：在途终止保存 Worker 后，onexit 兜底释放互斥锁，后续保存不永久排队
 * - 软件恢复数据流：会话密钥换发（clearAllSync）+ 池重置后，
 *   新 Worker 注入新密钥，M0 包裹/解包裹一致（不重置则旧 Worker 持旧密钥必失败）
 */
export default function WorkerPoolPolicyTest() {
  describe('WorkerPoolPolicyTest', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let dbPath: string;
    let dbPath2: string;
    let database: Kdbx;
    let fileHashA: string;
    let fileHashB: string;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      dbPath = appContext.filesDir + '/worker-pool-policy-test.kdbx';
      dbPath2 = appContext.filesDir + '/worker-pool-policy-test-2.kdbx';

      database = await KdbxModeTestHelper.createDatabase('WorkerPoolPolicyDb', 'pool-policy-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      fileHashA = await KdbxModeTestHelper.sha256Hex(initialContent);

      // 第二个数据库：内容不同，供壳串行用例验证两条任务结果不串
      const database2 = await KdbxModeTestHelper.createDatabase('WorkerPoolPolicyDb2', 'pool-policy-entry-b');
      const initialContent2: ArrayBuffer = await database2.save();
      await fileManager.write(dbPath2, initialContent2);
      fileHashB = await KdbxModeTestHelper.sha256Hex(initialContent2);

      // 重置 AppStorage 策略，保证用例间互不粘连
      CacheConstants.setOnlyCache(false);
      CacheConstants.clearForceRefresh();
      // 本套件专测 Worker 路径：分级调度下强制两个测试库走 Worker（种入超阈值大小）；
      // 每个用例后重播种——加载成功的真实大小回填会覆盖种入值，导致后续用例误走主线程
      KdbxModeTestHelper.forceWorkerDispatch(dbPath);
      KdbxModeTestHelper.forceWorkerDispatch(dbPath2);
    });

    afterEach(() => {
      KdbxModeTestHelper.forceWorkerDispatch(dbPath);
      KdbxModeTestHelper.forceWorkerDispatch(dbPath2);
    });

    afterAll(() => {
      KdbxLoadService.stopWorker();
      KdbxSaveService.stopWorker();
      try { fs.unlinkSync(dbPath); } catch { /* ignore */ }
      try { fs.unlinkSync(dbPath2); } catch { /* ignore */ }
    });

    it('attachCachePolicy writes three boolean policy fields', 0, () => {
      const msg: LoadDatabase = KdbxModeTestHelper.makeLoadParam(dbPath, 'a.kdbx', 'p');
      DatabaseWorkerFactory.attachCachePolicy(msg);
      expect(typeof msg.enableLocalCache).assertEqual('boolean');
      expect(msg.onlyUseCache).assertFalse();
      expect(msg.forceRefresh).assertFalse();
    });

    it('attachCachePolicy consumes forceRefresh exactly once', 0, () => {
      CacheConstants.setForceRefresh(true);
      expect(CacheConstants.getForceRefresh()).assertTrue();

      const first: LoadDatabase = KdbxModeTestHelper.makeLoadParam(dbPath, 'b.kdbx', 'p');
      DatabaseWorkerFactory.attachCachePolicy(first);
      // 任务消息携带一次性标志
      expect(first.forceRefresh).assertTrue();
      // 主线程标志已就地消费复位
      expect(CacheConstants.getForceRefresh()).assertFalse();

      const second: LoadDatabase = KdbxModeTestHelper.makeLoadParam(dbPath, 'c.kdbx', 'p');
      DatabaseWorkerFactory.attachCachePolicy(second);
      expect(second.forceRefresh).assertFalse();
    });

    it('messages without attachCachePolicy keep policy fields undefined (legacy compat)', 0, () => {
      const msg: LoadDatabase = KdbxModeTestHelper.makeLoadParam(dbPath, 'd.kdbx', 'p');
      expect(msg.enableLocalCache).assertUndefined();
      expect(msg.onlyUseCache).assertUndefined();
      expect(msg.forceRefresh).assertUndefined();
    });

    it('LoadDatabase policy fields survive JSON roundtrip (load channel)', 0, () => {
      const msg: LoadDatabase = KdbxModeTestHelper.makeLoadParam(dbPath, 'e.kdbx', 'p');
      DatabaseWorkerFactory.attachCachePolicy(msg);
      // 加载通道为 JSON 字符串消息：序列化往返后策略字段必须保留
      const parsed: LoadDatabase = JSON.parse(JSON.stringify(msg)) as LoadDatabase;
      expect(parsed.enableLocalCache).assertEqual(msg.enableLocalCache);
      expect(parsed.onlyUseCache).assertEqual(msg.onlyUseCache);
      expect(parsed.forceRefresh).assertEqual(msg.forceRefresh);
    });

    it('LoadDatabase without policy fields stays legacy in JSON', 0, () => {
      const msg: LoadDatabase = KdbxModeTestHelper.makeLoadParam(dbPath, 'f.kdbx', 'p');
      const parsed: LoadDatabase = JSON.parse(JSON.stringify(msg)) as LoadDatabase;
      expect(parsed.enableLocalCache).assertUndefined();
      expect(parsed.onlyUseCache).assertUndefined();
      expect(parsed.forceRefresh).assertUndefined();
    });

    it('SaveDatabaseMessage accepts policy fields without touching dbFileParam payload', 0, () => {
      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, dbPath, 'g.kdbx', null, null);
      const saveMessage = new SaveDatabaseMessage(database, dbFileParam, ConflictStrategy.AUTO);
      DatabaseWorkerFactory.attachCachePolicy(saveMessage);

      expect(typeof saveMessage.enableLocalCache).assertEqual('boolean');
      expect(typeof saveMessage.onlyUseCache).assertEqual('boolean');
      expect(typeof saveMessage.forceRefresh).assertEqual('boolean');
      // 策略字段为消息顶层字段，不进 dbFileParam JSON 载荷
      expect(saveMessage.dbFileParam.indexOf('enableLocalCache')).assertEqual(-1);
      expect(saveMessage.dbFileParam.indexOf('onlyUseCache')).assertEqual(-1);
      expect(saveMessage.dbFileParam.indexOf('forceRefresh')).assertEqual(-1);
    });

    it('pooled load rejects concurrent request with worker_busy', 0, async () => {
      // 开关断言：本用例依赖常驻池化语义
      expect(Constants.POOL_DATABASE_WORKER).assertTrue();

      KdbxLoadService.stopWorker();
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'worker-pool-policy-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);

      // 第一次：进入在途状态（busy = true）
      KdbxLoadService.loadDatabase(loadParam, {
        onSuccessMessage: (msg: SuccessMessage) => { },
        onErrorMessage: (msg: LoadMessage) => { }
      });

      // 第二次：同步紧随，忙释放依赖 Worker 回消息（不可能在当前宏任务内完成），
      // 必命中忙拒绝；旧行为（kill 重来）下则会 terminate 后重新加载
      const secondResult: string = await withTimeout(new Promise<string>((resolve) => {
        KdbxLoadService.loadDatabase(loadParam, {
          onSuccessMessage: (msg: SuccessMessage) => { resolve('success'); },
          onErrorMessage: (msg: LoadMessage) => { resolve(String(msg.message)); }
        });
      }), TEST_TIMEOUT_MS);

      expect(secondResult).assertEqual('worker_busy');

      // 终止在途加载，onexit 兜底释放忙标志，不影响后续用例
      KdbxLoadService.stopWorker();
    });

    it('pooled load reuses persistent worker across operations', 0, async () => {
      KdbxLoadService.stopWorker();
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'worker-pool-policy-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);

      // 第一次：懒创建常驻 Worker
      const first = await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
        KdbxLoadService.loadDatabase(loadParam, {
          onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
          onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
        });
      }), TEST_TIMEOUT_MS);
      expect(first.type).assertEqual(MessageType.SUCCESS);

      // 第二次：不 stopWorker，必须走复用分支（旧行为每操作 terminate 重建，
      // 从未覆盖该路径；复用失败会在 postMessage/回包上暴露）。
      // 重播种：首次加载的真实大小回填会覆盖种入值
      KdbxModeTestHelper.forceWorkerDispatch(dbPath);
      const second = await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
        KdbxLoadService.loadDatabase(loadParam, {
          onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
          onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
        });
      }), TEST_TIMEOUT_MS);
      expect(second.type).assertEqual(MessageType.SUCCESS);
      expect(second.contentHash).assertEqual(fileHashA);

      KdbxLoadService.stopWorker();
    });

    it('worker shell executes queued load tasks serially via taskChain', 0, async () => {
      // 直连工厂创建常驻 Worker（绕过服务层），连投两条任务消息验证壳内串行
      const w: worker.ThreadWorker = KdbxModeTestHelper.createLoadWorker();
      try {
        const results: WorkerMessage[] = [];
        const pending = withTimeout(new Promise<WorkerMessage[]>((resolve, reject) => {
          w.onmessage = (event: MessageEvents) => {
            const message = event.data as WorkerMessage;
            if (message.type === MessageType.SUCCESS || message.type === MessageType.CONFLICT
              || message.type === MessageType.ERROR) {
              results.push(message);
              if (results.length === 2) {
                resolve(results);
              }
            }
          };
          w.onAllErrors = (error: ErrorEvent) => {
            reject(new Error(error.message));
          };
        }), KdbxModeTestHelper.WORKER_TIMEOUT);

        const loadA = KdbxModeTestHelper.makeLoadParam(dbPath, 'worker-pool-policy-test.kdbx',
          KdbxModeTestHelper.DB_PASSWORD);
        const loadB = KdbxModeTestHelper.makeLoadParam(dbPath2, 'worker-pool-policy-test-2.kdbx',
          KdbxModeTestHelper.DB_PASSWORD);
        // 两条任务消息先后投递同一常驻 isolate（不新建 Worker），
        // 消息为旧格式（无策略字段），同时回归 legacy 兼容路径
        w.postMessage(JSON.stringify(loadA));
        w.postMessage(JSON.stringify(loadB));

        const messages = await pending;
        expect(messages[0].type).assertEqual(MessageType.SUCCESS);
        expect(messages[1].type).assertEqual(MessageType.SUCCESS);

        // 两条结果各自对应请求文件（内容哈希不串、不丢、不重）
        const hashes: string[] = [];
        for (const message of messages) {
          const success = message as SuccessMessage;
          hashes.push(success.contentHash ?? '');
        }
        const expected: string[] = [fileHashA, fileHashB];
        hashes.sort();
        expected.sort();
        expect(hashes.length).assertEqual(2);
        expect(hashes[0]).assertEqual(expected[0]);
        expect(hashes[1]).assertEqual(expected[1]);
      } finally {
        w.terminate();
      }
    });

    it('pooled load self-heals after in-flight worker termination', 0, async () => {
      KdbxLoadService.stopWorker();
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'worker-pool-policy-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);

      // 第一次：发起后即在途（busy = true，Worker 已创建并投递任务）
      KdbxLoadService.loadDatabase(loadParam, {
        onSuccessMessage: (msg: SuccessMessage) => { },
        onErrorMessage: (msg: LoadMessage) => { }
      });
      // 模拟常驻 Worker 异常退出/应用恢复重置：terminate 触发 onexit
      // （置空引用 + 释放忙标志），在途回调不再有响应
      await sleep(100);
      KdbxLoadService.stopWorker();
      await sleep(WORKER_EXIT_WAIT_MS);

      // 下一次操作：忙标志已由 onexit 释放，懒重建 Worker 并成功（自愈路径）
      const result = await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
        KdbxLoadService.loadDatabase(loadParam, {
          onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
          onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
        });
      }), TEST_TIMEOUT_MS);
      expect(result.type).assertEqual(MessageType.SUCCESS);

      KdbxLoadService.stopWorker();
    });

    it('pooled save releases lock after worker termination and next save succeeds', 0, async () => {
      // 构造真实保存场景：内存库与磁盘基线一致（无冲突，条件写入成功）
      const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, dbPath,
        'worker-pool-policy-test.kdbx', null, fileHashA);
      FileService.setDbFileParam(dbFileParam);
      KdbxSaveService.stopWorker();

      // 保存#1：发起后即在途（进入互斥链 + Worker 执行）
      KdbxSaveService.saveDatabase({
        onSuccess: (msg: SuccessMessage) => { },
        onConflict: (msg: ConflictMessage) => { },
        onError: (err: string) => { }
      });
      await sleep(300);
      // 模拟应用恢复重置：终止在途保存 Worker，onexit 兜底释放互斥锁
      KdbxSaveService.stopWorker();
      await sleep(WORKER_EXIT_WAIT_MS);

      // 保存#2：若互斥锁未释放将永久排队（超时失败），正常应重建 Worker 并保存成功
      const secondResult: boolean = await withTimeout(new Promise<boolean>((resolve) => {
        KdbxSaveService.saveDatabase({
          onSuccess: (msg: SuccessMessage) => { resolve(true); },
          onConflict: (msg: ConflictMessage) => { resolve(true); },
          onError: (err: string) => { resolve(false); }
        });
      }), TEST_TIMEOUT_MS);

      expect(secondResult).assertTrue();

      KdbxSaveService.stopWorker();
    });

    it('app recovery flow: session key rotation with pool reset keeps load working', 0, async () => {
      KdbxLoadService.stopWorker();
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'worker-pool-policy-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);

      // 第一次加载：常驻 Worker 经 INIT 注入会话密钥 K1，M0 包裹/解包裹一致
      const first = await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
        KdbxLoadService.loadDatabase(loadParam, {
          onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
          onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
        });
      }), TEST_TIMEOUT_MS);
      expect(first.type).assertEqual(MessageType.SUCCESS);

      // 主线程解包裹（K1）：模型可还原
      const m0PathFirst: string | undefined = first.m0Path;
      expect(typeof m0PathFirst === 'string' && m0PathFirst.length > 0).assertTrue();
      if (m0PathFirst) {
        const snapshotFirst: ArrayBuffer = await SessionFileService.unwrapFromFile(m0PathFirst);
        expect(KdbxSnapshot.isSnapshot(snapshotFirst)).assertTrue();
        SessionFileService.removeFile(m0PathFirst);
      }

      // 模拟 onDestroy：全清会话目录并作废主线程会话密钥（下次取用时换发 K2）
      SessionFileService.clearAllSync();
      // 模拟 onCreate 软件恢复重置：终止常驻 Worker（其持有的 K1 快照已作废，
      // 不重置则旧 Worker 以 K1 包裹 M0、主线程以 K2 解包裹，GCM 校验必失败）
      KdbxLoadService.stopWorker();

      // 恢复后首次加载：懒重建 Worker 注入新密钥 K2，M0 包裹/解包裹恢复一致。
      // 重播种：首次加载的真实大小回填会覆盖种入值
      KdbxModeTestHelper.forceWorkerDispatch(dbPath);
      const second = await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
        KdbxLoadService.loadDatabase(loadParam, {
          onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
          onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
        });
      }), TEST_TIMEOUT_MS);
      expect(second.type).assertEqual(MessageType.SUCCESS);

      const m0PathSecond: string | undefined = second.m0Path;
      expect(typeof m0PathSecond === 'string' && m0PathSecond.length > 0).assertTrue();
      if (m0PathSecond) {
        const snapshotSecond: ArrayBuffer = await SessionFileService.unwrapFromFile(m0PathSecond);
        expect(KdbxSnapshot.isSnapshot(snapshotSecond)).assertTrue();
        const restored: Kdbx = await KdbxUtils.arrayBufferToKdbx(snapshotSecond, loadParam);
        const titles: string[] = KdbxModeTestHelper.collectEntryTitles(restored);
        expect(titles.includes('pool-policy-entry')).assertTrue();
        SessionFileService.removeFile(m0PathSecond);
      }

      KdbxLoadService.stopWorker();
    });
  });
}
