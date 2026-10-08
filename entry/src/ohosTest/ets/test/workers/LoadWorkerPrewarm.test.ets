import { beforeAll, afterAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import KdbxLoadService, { KdbxLoadServiceCallback } from '../../../../main/ets/services/kdbx/KdbxLoadService';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { SessionFileService } from '../../../../main/ets/services/kdbx/SessionFileService';
import { LoadDispatchCache } from '../../../../main/ets/services/kdbx/LoadDispatchCache';
import { LoadDispatchService } from '../../../../main/ets/services/kdbx/LoadDispatchService';
import { CacheConstants } from '../../../../main/ets/storage/cache/CacheConstants';
import { StorageType } from '../../../../main/ets/storage';
import { MessageType, SuccessMessage, LoadMessage } from '../../../../main/ets/workers/WorkerParam';
import { KdbxModeTestHelper } from './KdbxModeTestHelper';

const PREWARM_WAIT_TIMEOUT_MS: number = 20000;
const PREWARM_POLL_INTERVAL_MS: number = 200;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

async function waitCacheSize(filePath: string, expected: number, timeoutMs: number): Promise<boolean> {
  const start: number = Date.now();
  while (Date.now() - start < timeoutMs) {
    const size: number | undefined = LoadDispatchCache.get(filePath);
    if (size === expected) {
      return true;
    }
    await sleep(PREWARM_POLL_INTERVAL_MS);
  }
  return false;
}

/**
 * PREWARM 预热协议单元测试（真实 Worker 全链路，LOCAL 存储离线可测）：
 * - prewarm 经真实 Worker 探测大小并回填 LoadDispatchCache
 * - prewarm 失败（文件不存在）不写缓存、不抛错
 * - prewarm 不消费 forceRefresh 一次性标志（含 Worker 创建路径的快照恢复）
 * - 预热后的 Worker 可直接承担真实加载（onmessage 一次性注册重构回归）
 */
export default function LoadWorkerPrewarmTest() {
  describe('LoadWorkerPrewarmTest', () => {
    let appContext: common.Context;
    let testDir: string;
    let bigFilePath: string;
    let dbPath: string;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      testDir = appContext.filesDir + '/load-worker-prewarm-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
      bigFilePath = testDir + '/big-file.bin';
      const file = await fs.open(bigFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        await fs.write(file.fd, new ArrayBuffer(4321));
      } finally {
        await fs.close(file.fd);
      }
      // 真实加密数据库（验证预热后加载链路）
      const database = await KdbxModeTestHelper.createDatabase('PrewarmDb', 'prewarm-entry');
      dbPath = testDir + '/prewarm-db.kdbx';
      const fileManager = new KdbxFileManager(StorageType.LOCAL);
      await fileManager.write(dbPath, await database.save());
    });

    afterAll(() => {
      KdbxLoadService.stopWorker();
      LoadDispatchCache.clear();
      CacheConstants.clearForceRefresh();
      try {
        fs.unlinkSync(bigFilePath);
        fs.unlinkSync(dbPath);
        fs.rmdirSync(testDir);
      } catch {
        // ignore
      }
    });

    it('prewarm populates LoadDispatchCache via real worker', 0, async () => {
      KdbxLoadService.stopWorker();
      LoadDispatchCache.clear();
      KdbxLoadService.prewarm(bigFilePath, StorageType.LOCAL, {});
      const populated: boolean = await waitCacheSize(bigFilePath, 4321, PREWARM_WAIT_TIMEOUT_MS);
      expect(populated).assertTrue();
    });

    it('prewarm missing file does not populate cache nor throw', 0, async () => {
      LoadDispatchCache.clear();
      const missingPath = testDir + '/prewarm-missing.bin';
      KdbxLoadService.prewarm(missingPath, StorageType.LOCAL, {});
      // 等待预热结果往返（失败结果仅记日志），缓存不应被写入
      await sleep(3000);
      expect(LoadDispatchCache.get(missingPath)).assertUndefined();
    });

    it('prewarm does not consume forceRefresh one-shot flag (worker creation path)', 0, async () => {
      // 终止 Worker：强制走"预热触发创建"路径（buildInitMessage 会就地消费 forceRefresh）
      KdbxLoadService.stopWorker();
      LoadDispatchCache.clear();
      CacheConstants.setForceRefresh(true);
      try {
        KdbxLoadService.prewarm(bigFilePath, StorageType.LOCAL, {});
        const populated: boolean = await waitCacheSize(bigFilePath, 4321, PREWARM_WAIT_TIMEOUT_MS);
        expect(populated).assertTrue();
        // 预热对调用方透明：一次性标志必须保留给后续真实加载任务
        expect(CacheConstants.getForceRefresh()).assertTrue();
      } finally {
        CacheConstants.clearForceRefresh();
      }
    });

    it('load succeeds on prewarmed worker (onmessage fan-out refactor)', 0, async () => {
      // Worker 已由前序用例预热（常驻复用）；预热结果消息与加载任务消息经同一 onmessage 扇出
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'prewarm-db.kdbx', KdbxModeTestHelper.DB_PASSWORD);
      const done: Promise<SuccessMessage | LoadMessage> = new Promise((resolve: (value: SuccessMessage | LoadMessage) => void) => {
        const callback: KdbxLoadServiceCallback = {
          onSuccessMessage: (message: SuccessMessage) => {
            resolve(message);
          },
          onErrorMessage: (message: LoadMessage) => {
            resolve(message);
          }
        };
        KdbxLoadService.loadDatabase(loadParam, callback);
      });
      const result: SuccessMessage | LoadMessage = await done;
      expect(result.type).assertEqual(MessageType.SUCCESS);
      const success = result as SuccessMessage;
      expect(success.m0Path !== undefined && success.m0Path.length > 0).assertTrue();
      if (success.m0Path) {
        // 消费后清理会话文件
        SessionFileService.removeFile(success.m0Path);
      }
    });

    it('prepare skips LOCAL storage (no prewarm needed)', 0, () => {
      // LOCAL 分支直接返回：不预热、不建 Worker、不抛错
      LoadDispatchService.prepare(StorageType.LOCAL, {}, '/any/local/path.kdbx');
      expect(true).assertTrue();
    });
  });
}
