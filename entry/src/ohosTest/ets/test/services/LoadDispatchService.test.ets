import { beforeAll, afterAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Kdbx } from 'kdbxweb';
import KdbxLoadService, { KdbxLoadServiceCallback } from '../../../../main/ets/services/kdbx/KdbxLoadService';
import { LoadDispatchCache } from '../../../../main/ets/services/kdbx/LoadDispatchCache';
import { LoadDispatchService } from '../../../../main/ets/services/kdbx/LoadDispatchService';
import { DatabaseLoadGuard } from '../../../../main/ets/services/kdbx/DatabaseLoadGuard';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { LocalFileStorage } from '../../../../main/ets/storage/local/LocalFileStorage';
import { FileStorageFactory } from '../../../../main/ets/storage/FileStorageFactory';
import { IFileStorage, FileInfo, FileInfoImpl, FileType, WriteOption } from '../../../../main/ets/storage/IFileStorage';
import { StorageConfig } from '../../../../main/ets/storage/StorageConfig';
import { StorageType } from '../../../../main/ets/storage/StorageType';
import { Constants } from '../../../../main/ets/common/constants/Constants';
import { MessageType, SuccessMessage, LoadMessage } from '../../../../main/ets/workers/WorkerParam';
import { SessionFileService } from '../../../../main/ets/services/kdbx/SessionFileService';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

const TEST_TIMEOUT_MS: number = 30000;

function withTimeout<T>(pending: Promise<T>, timeoutMs: number): Promise<T> {
  return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void) => {
    const timer = setTimeout(() => {
      reject(new Error('test timeout'));
    }, timeoutMs);
    pending.then((value: T) => {
      clearTimeout(timer);
      resolve(value);
    }, (error: Error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

/**
 * 谎报大小的 LOCAL 存储：除 getInfoOrNull 返回固定大值外全部委托真实 LocalFileStorage，
 * 验证"调度层探测结果驱动路由"而无需真实构造 4MB+ 数据库
 */
class BigSizeStubStorage implements IFileStorage {
  private real: LocalFileStorage = new LocalFileStorage();
  public fakeSize: number = 5 * 1024 * 1024;

  getPageConfig() {
    return this.real.getPageConfig();
  }

  init(config: StorageConfig): void {
    this.real.init(config);
  }

  read(path: string): Promise<ArrayBuffer> {
    return this.real.read(path);
  }

  readToFile(path: string, destPath: string): Promise<FileInfo> {
    return this.real.readToFile(path, destPath);
  }

  write(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void> {
    return this.real.write(path, content, option);
  }

  writeFromFile(path: string, srcPath: string, option?: WriteOption): Promise<FileInfo> {
    return this.real.writeFromFile(path, srcPath, option);
  }

  exists(path: string): Promise<boolean> {
    return this.real.exists(path);
  }

  getInfo(path: string): Promise<FileInfo> {
    return this.real.getInfo(path);
  }

  getInfoOrNull(path: string): Promise<FileInfo | null> {
    const info: FileInfo = new FileInfoImpl();
    info.name = 'fake-big.kdbx';
    info.size = this.fakeSize;
    info.modifiedTime = 1;
    info.path = path;
    info.type = FileType.FILE;
    info.version = null;
    return Promise.resolve(info);
  }

  listDir(path: string): Promise<FileInfo[]> {
    return this.real.listDir(path);
  }
}

/**
 * getInfo 返回超大文件的 LOCAL 存储：验证守卫 precheckSize 短路 getInfo（CP1 路径）
 */
class HugeInfoStorage extends BigSizeStubStorage {
  public static readonly HUGE_SIZE: number = 600 * 1024 * 1024;

  getInfo(path: string): Promise<FileInfo> {
    const info: FileInfo = new FileInfoImpl();
    info.name = 'huge.kdbx';
    info.size = HugeInfoStorage.HUGE_SIZE;
    info.modifiedTime = 1;
    info.path = path;
    info.type = FileType.FILE;
    info.version = null;
    return Promise.resolve(info);
  }
}

/**
 * 分级加载调度单元测试：
 * - resolveSize 解析链（缓存优先 / 本地探测 / 未知）
 * - dispatch：小库主线程直开（Kdbx 实例引用传递 + fileSize 回填）
 * - dispatch：大库（探测值 > 阈值）走 Worker（M0 会话文件路径回传）
 * - dispatch：未知大小保守走 Worker（错误自然透出）
 * - 守卫 precheckSize 跳过 getInfo（CP1 复用已知值）
 */
export default function LoadDispatchServiceTest() {
  describe('LoadDispatchServiceTest', () => {
    let appContext: common.Context;
    let testDir: string;
    let smallDbPath: string;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      testDir = appContext.filesDir + '/load-dispatch-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
      // 真实加密小库（远小于 4MB 阈值）
      const database = await KdbxModeTestHelper.createDatabase('DispatchDb', 'dispatch-entry');
      smallDbPath = testDir + '/dispatch-small.kdbx';
      const fileManager = new KdbxFileManager(StorageType.LOCAL);
      await fileManager.write(smallDbPath, await database.save());
      expect(Constants.SIZE_DISPATCH_LOAD).assertTrue();
      expect(Constants.SYNC_LOAD_MAX_BYTES).assertEqual(4 * 1024 * 1024);
    });

    afterAll(() => {
      KdbxLoadService.stopWorker();
      LoadDispatchCache.clear();
      try {
        fs.unlinkSync(smallDbPath);
        fs.rmdirSync(testDir);
      } catch {
        // ignore
      }
    });

    // -------- resolveSize 解析链 --------

    it('resolveSize prefers cache without probing', 0, async () => {
      LoadDispatchCache.clear();
      const path = testDir + '/cache-priority.kdbx';
      LoadDispatchCache.put(path, 100);
      // 文件不存在：若走探测会失败，命中缓存则直接返回
      const size = await LoadDispatchService.resolveSize(path, StorageType.LOCAL, {});
      expect(size).assertEqual(100);
      LoadDispatchCache.clear();
    });

    it('resolveSize probes LOCAL file and populates cache', 0, async () => {
      LoadDispatchCache.clear();
      const size = await LoadDispatchService.resolveSize(smallDbPath, StorageType.LOCAL, {});
      expect(size !== undefined && size > 0).assertTrue();
      expect(LoadDispatchCache.get(smallDbPath)).assertEqual(size);
      LoadDispatchCache.clear();
    });

    it('resolveSize returns undefined for missing file', 0, async () => {
      LoadDispatchCache.clear();
      const size = await LoadDispatchService.resolveSize(testDir + '/dispatch-missing.kdbx',
        StorageType.LOCAL, {});
      expect(size).assertUndefined();
    });

    // -------- dispatch 路由 --------

    it('dispatch loads small database on main thread (direct Kdbx instance)', 0, async () => {
      LoadDispatchCache.clear();
      KdbxLoadService.stopWorker();
      const loadParam = KdbxModeTestHelper.makeLoadParam(smallDbPath, 'dispatch-small.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);
      const message: SuccessMessage = await withTimeout(new Promise<SuccessMessage>(
        (resolve: (value: SuccessMessage) => void, reject: (reason: Error) => void) => {
          const callback: KdbxLoadServiceCallback = {
            onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
            onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
          };
          KdbxLoadService.loadDatabase(loadParam, callback);
        }), TEST_TIMEOUT_MS);
      // 主线程直开：data 为 Kdbx 实例（零协议税），m0Path 未设置
      expect(message.type).assertEqual(MessageType.SUCCESS);
      expect(message.data instanceof Kdbx).assertTrue();
      expect(message.m0Path).assertUndefined();
      // fileSize 随消息回传并回填调度缓存
      expect(message.fileSize !== undefined && message.fileSize > 0).assertTrue();
      expect(LoadDispatchCache.get(smallDbPath)).assertEqual(message.fileSize);
    });

    it('dispatch routes big-size database to worker (M0 path)', 0, async () => {
      LoadDispatchCache.clear();
      KdbxLoadService.stopWorker();
      const factory = FileStorageFactory.getInstance();
      const original = factory.getStorageMap().get(StorageType.LOCAL);
      factory.registerStorage(StorageType.LOCAL, new BigSizeStubStorage());
      try {
        const loadParam = KdbxModeTestHelper.makeLoadParam(smallDbPath, 'dispatch-small.kdbx',
          KdbxModeTestHelper.DB_PASSWORD);
        const message: SuccessMessage = await withTimeout(new Promise<SuccessMessage>(
          (resolve: (value: SuccessMessage) => void, reject: (reason: Error) => void) => {
            const callback: KdbxLoadServiceCallback = {
              onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
              onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
            };
            KdbxLoadService.loadDatabase(loadParam, callback);
          }), TEST_TIMEOUT_MS);
        // Worker 路径：M0 会话文件路径回传，data 为空缓冲；precheckSize 已随任务透传守卫
        expect(message.type).assertEqual(MessageType.SUCCESS);
        expect(message.m0Path !== undefined && message.m0Path.length > 0).assertTrue();
        if (message.m0Path) {
          SessionFileService.removeFile(message.m0Path);
        }
      } finally {
        if (original) {
          factory.registerStorage(StorageType.LOCAL, original);
        } else {
          factory.removeStorage(StorageType.LOCAL);
        }
      }
    });

    it('dispatch falls back to worker when size unknown (error surfaced)', 0, async () => {
      LoadDispatchCache.clear();
      KdbxLoadService.stopWorker();
      const loadParam = KdbxModeTestHelper.makeLoadParam(testDir + '/dispatch-missing.kdbx',
        'dispatch-missing.kdbx', KdbxModeTestHelper.DB_PASSWORD);
      const outcome: string = await withTimeout(new Promise<string>((resolve: (value: string) => void) => {
        const callback: KdbxLoadServiceCallback = {
          onSuccessMessage: (msg: SuccessMessage) => { resolve('success'); },
          onErrorMessage: (msg: LoadMessage) => { resolve('error:' + String(msg.message)); }
        };
        KdbxLoadService.loadDatabase(loadParam, callback);
      }), TEST_TIMEOUT_MS);
      // 未知大小保守走 Worker：真实读取流程报错
      expect(outcome.startsWith('error')).assertTrue();
    });

    // -------- 守卫 precheckSize 去重 --------

    it('guard reuses precheckSize and skips getInfo (CP1 path)', 0, async () => {
      const factory = FileStorageFactory.getInstance();
      const original = factory.getStorageMap().get(StorageType.LOCAL);
      const hugeStorage = new HugeInfoStorage();
      factory.registerStorage(StorageType.LOCAL, hugeStorage);
      try {
        const manager = new KdbxFileManager(StorageType.LOCAL);
        // 不传 precheckSize：getInfo 返回 600MB → CP1 拒绝
        const withoutPrecheck = await DatabaseLoadGuard.checkBeforeRead(manager, smallDbPath);
        expect(withoutPrecheck.rejectReason).assertEqual('database_too_large');
        // 传 precheckSize（调度层已知值）：跳过 getInfo → CP1 以已知值放行
        const withPrecheck = await DatabaseLoadGuard.checkBeforeRead(manager, smallDbPath, 1024);
        expect(withPrecheck.rejectReason).assertNull();
      } finally {
        if (original) {
          factory.registerStorage(StorageType.LOCAL, original);
        } else {
          factory.removeStorage(StorageType.LOCAL);
        }
      }
    });
  });
}
