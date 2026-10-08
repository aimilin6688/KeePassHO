import { afterAll, afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { ErrorEvent } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import KdbxLoadService, { KdbxLoadServiceCallback } from '../../../../main/ets/services/kdbx/KdbxLoadService';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { StorageType } from '../../../../main/ets/storage';
import { LoadDatabase } from '../../../../main/ets/workers/DatabaseLoadWorkerParam';
import { LoadMessage, MessageType, SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

const TEST_TIMEOUT_MS: number = 60000;

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_resolve, reject) =>
      setTimeout(() => reject(new Error('Test timed out after ' + timeoutMs + 'ms')), timeoutMs)
    )
  ]);
}

/**
 * KdbxLoadService 单元测试。
 *
 * Constants.ASYNC_LOAD_DATABASE = true → asyncLoadDatabase 路径：
 * 真实 ThreadWorker 消息链路（DatabaseLoadWorker 壳已由 KdbxModeTestHelper 副作用 import 编入测试 abc）。
 * 覆盖：
 * - stopWorker 无 Worker 时为空操作
 * - loadDatabase 成功加载（验证 data / contentHash / modifiedTime）
 * - loadDatabase 错误密码上报 ERROR
 * - loadDatabase 不存在文件上报 ERROR
 * - loadDatabase 进度消息 onLoadMessage 回调
 * - loadDatabase onexit 回调
 */
export default function KdbxLoadServiceTest() {
  describe('KdbxLoadServiceTest', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let dbPath: string;
    let database: Kdbx;
    let baseHash: string;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      dbPath = appContext.filesDir + '/kdbx-load-service-test.kdbx';

      database = await KdbxModeTestHelper.createDatabase('LoadServiceDb', 'load-base-entry');
      const initialContent: ArrayBuffer = await database.save();
      await fileManager.write(dbPath, initialContent);
      baseHash = await KdbxModeTestHelper.sha256Hex(initialContent);
      // 本套件专测 Worker 路径：分级调度下强制 dbPath 走 Worker（种入超阈值大小）；
      // 每个用例后重播种——加载成功的真实大小回填会覆盖种入值，导致后续用例误走主线程
      KdbxModeTestHelper.forceWorkerDispatch(dbPath);
    });

    afterEach(() => {
      KdbxModeTestHelper.forceWorkerDispatch(dbPath);
    });

    afterAll(() => {
      KdbxLoadService.stopWorker();
      try { fs.unlinkSync(dbPath); } catch { /* ignore */ }
    });

    it('stopWorker is a no-op when no worker exists', 0, () => {
      let threw = false;
      try {
        KdbxLoadService.stopWorker();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('loadDatabase succeeds with valid credentials', 0, async () => {
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'kdbx-load-service-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);

      const message: SuccessMessage = await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
        KdbxLoadService.loadDatabase(loadParam, {
          onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
          onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
        });
      }), TEST_TIMEOUT_MS);

      expect(message.type).assertEqual(MessageType.SUCCESS);
      expect(message.modifiedTime > 0).assertTrue();
      expect(message.contentHash).assertEqual(baseHash);
      expect(message.version !== null).assertTrue();

      KdbxLoadService.stopWorker();
    });

    it('loadDatabase with wrong password reports error', 0, async () => {
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'kdbx-load-service-test.kdbx',
        'wrong-password');

      let errorCaught: Error | null = null;
      try {
        await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
          KdbxLoadService.loadDatabase(loadParam, {
            onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
            onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
          });
        }), TEST_TIMEOUT_MS);
      } catch (error) {
        errorCaught = error as Error;
      }
      expect(errorCaught !== null).assertTrue();
      expect(errorCaught!.message.length > 0).assertTrue();

      KdbxLoadService.stopWorker();
    });

    it('loadDatabase with non-existent file reports error', 0, async () => {
      const loadParam = KdbxModeTestHelper.makeLoadParam(
        appContext.filesDir + '/load-not-exists.kdbx',
        'not-exists.kdbx',
        KdbxModeTestHelper.DB_PASSWORD
      );

      let errorCaught: Error | null = null;
      try {
        await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
          KdbxLoadService.loadDatabase(loadParam, {
            onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
            onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
          });
        }), TEST_TIMEOUT_MS);
      } catch (error) {
        errorCaught = error as Error;
      }
      expect(errorCaught !== null).assertTrue();

      KdbxLoadService.stopWorker();
    });

    it('loadDatabase invokes onLoadMessage callback', 0, async () => {
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'kdbx-load-service-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);

      let messageReceived = false;
      const message: SuccessMessage = await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
        KdbxLoadService.loadDatabase(loadParam, {
          onLoadMessage: (msg: LoadMessage) => { messageReceived = true; },
          onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
          onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
        });
      }), TEST_TIMEOUT_MS);

      expect(message.type).assertEqual(MessageType.SUCCESS);
      expect(messageReceived).assertTrue();

      KdbxLoadService.stopWorker();
    });

    it('loadDatabase invokes onexit callback when worker terminates', 0, async () => {
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'kdbx-load-service-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);

      let exitCode: number | null = null;
      await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
        KdbxLoadService.loadDatabase(loadParam, {
          onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
          onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); },
          onexit: (code: number) => { exitCode = code; }
        });
      }), TEST_TIMEOUT_MS);

      KdbxLoadService.stopWorker();
      // stopWorker triggers onexit; give a brief moment for the callback
      await new Promise<void>(resolve => setTimeout(resolve, 200));
      expect(exitCode !== null).assertTrue();
    });

    it('loadDatabase without callback does not throw', 0, async () => {
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'kdbx-load-service-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);

      let threw = false;
      try {
        KdbxLoadService.loadDatabase(loadParam);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();

      // Give worker time to process then stop
      await new Promise<void>(resolve => setTimeout(resolve, 3000));
      KdbxLoadService.stopWorker();
    });

    it('stopWorker terminates an active worker', 0, async () => {
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'kdbx-load-service-test.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);

      // Start a load (don't wait for completion)
      KdbxLoadService.loadDatabase(loadParam, {
        onSuccessMessage: (msg: SuccessMessage) => { },
        onErrorMessage: (msg: LoadMessage) => { }
      });

      // Give worker time to start
      await new Promise<void>(resolve => setTimeout(resolve, 1000));

      // Stop the worker
      let threw = false;
      try {
        KdbxLoadService.stopWorker();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('KdbxLoadServiceCallback interface accepts all optional methods', 0, () => {
      const cb: KdbxLoadServiceCallback = {
        onexit: (e: number) => {},
        onAllErrors: (err: ErrorEvent) => {},
        onLoadMessage: (message: LoadMessage) => {},
        onSuccessMessage: (message: SuccessMessage) => {},
        onErrorMessage: (message: LoadMessage) => {}
      };
      expect(typeof cb.onSuccessMessage === 'function').assertTrue();
      expect(typeof cb.onErrorMessage === 'function').assertTrue();
      expect(typeof cb.onLoadMessage === 'function').assertTrue();
      expect(typeof cb.onexit === 'function').assertTrue();
      expect(typeof cb.onAllErrors === 'function').assertTrue();
    });

    it('KdbxLoadServiceCallback interface accepts empty object', 0, () => {
      const cb: KdbxLoadServiceCallback = {};
      expect(cb.onSuccessMessage).assertUndefined();
      expect(cb.onErrorMessage).assertUndefined();
      expect(cb.onLoadMessage).assertUndefined();
      expect(cb.onexit).assertUndefined();
      expect(cb.onAllErrors).assertUndefined();
    });
  });
}
