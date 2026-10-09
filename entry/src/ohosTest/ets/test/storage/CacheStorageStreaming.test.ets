import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CacheStorage } from '../../../../main/ets/storage/cache/CacheStorage';
import { LocalFileStorage } from '../../../../main/ets/storage/local/LocalFileStorage';
import { CacheConstants } from '../../../../main/ets/storage/cache/CacheConstants';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { FileTransfer } from '../../../../main/ets/storage/FileTransfer';
import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig, StorageType, WriteOption } from '../../../../main/ets/storage';

function initTestContext(): common.Context {
  const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  CommonUtils.init(appContext as common.UIAbilityContext);
  return appContext;
}

/**
 * 进度透传桩存储：write() 模拟两段上传进度（50% → 100%）后完成
 */
class ProgressStubStorage implements IFileStorage {
  writeCalls = 0;
  lastWritePath = '';

  getPageConfig(): PageConfig {
    return {} as PageConfig;
  }
  init(config: StorageConfig): void {}
  async read(path: string): Promise<ArrayBuffer> { return new ArrayBuffer(0); }
  async write(path: string, content: ArrayBuffer, option?: WriteOption,
    onProgress?: (transferredBytes: number, totalBytes: number) => void): Promise<void> {
    this.writeCalls++;
    this.lastWritePath = path;
    if (onProgress) {
      onProgress(5, 10);
      onProgress(10, 10);
    }
  }
  async exists(path: string): Promise<boolean> { return true; }
  async getInfo(path: string): Promise<FileInfo> {
    return {
      name: 'stub.bin',
      size: 10,
      modifiedTime: Date.now(),
      path: path,
      type: FileType.FILE,
      childrenCount: 0,
      version: 'stub-version'
    } as FileInfo;
  }
  async getInfoOrNull(path: string): Promise<FileInfo | null> { return this.getInfo(path); }
  async listDir(path: string): Promise<FileInfo[]> { return []; }
  async readToFile(path: string, destPath: string): Promise<FileInfo> {
    return FileTransfer.readToFileDefault(this, path, destPath);
  }
  async writeFromFile(path: string, srcPath: string, option?: WriteOption): Promise<FileInfo> {
    return FileTransfer.writeFromFileDefault(this, path, srcPath, option);
  }
}

/**
 * CacheStorage 流式委托测试
 * 用 LocalFileStorage 作为底层存储（非 LOCAL 被 CacheStorage 装饰）
 * 直接构造 CacheStorage(localStorage) 测试 readToFile/writeFromFile 委托逻辑
 */
export default function CacheStorageStreamingTest() {
  describe('CacheStorageStreamingTest', () => {
    let appContext: common.Context;
    let testDir: string;
    let localFileStorage: LocalFileStorage;
    let cacheStorage: CacheStorage;

    beforeAll(() => {
      appContext = initTestContext();
      testDir = appContext.filesDir + '/cache-streaming-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
      localFileStorage = new LocalFileStorage();
      // 直接构造 CacheStorage 包装 LocalFileStorage
      cacheStorage = new CacheStorage(localFileStorage);
      // 确保缓存策略为默认（主线程无 Worker 快照）
      CacheConstants.setWorkerCachePolicy(true, false, false);
    });

    /**
     * readToFile 委托底层流式下载
     */
    it('readToFile delegates to underlying storage', 0, async () => {
      const srcPath = testDir + '/src-cache-read.kdbx';
      const data = new ArrayBuffer(512);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = i % 256;
      }
      const file = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data);
      await fs.close(file.fd);

      const destPath = testDir + '/dest-cache-read.kdbx';
      const info = await cacheStorage.readToFile(srcPath, destPath);

      expect(info.size).assertEqual(512);
      const buf = await readFile(destPath);
      expect(Array.from(new Uint8Array(buf)).join(',')).assertEqual(Array.from(view).join(','));
    });

    /**
     * writeFromFile 委托底层流式上传 + 刷新缓存
     */
    it('writeFromFile delegates and refreshes cache', 0, async () => {
      const srcData = new ArrayBuffer(256);
      const view = new Uint8Array(srcData);
      for (let i = 0; i < view.length; i++) {
        view[i] = (i * 2) % 256;
      }
      const srcPath = testDir + '/src-cache-write.kdbx';
      const file = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, srcData);
      await fs.close(file.fd);

      const destPath = testDir + '/dest-cache-write.kdbx';
      const info = await cacheStorage.writeFromFile(destPath, srcPath);

      expect(info.size).assertEqual(256);
      // 验证远端写入
      const buf = await readFile(destPath);
      expect(Array.from(new Uint8Array(buf)).join(',')).assertEqual(Array.from(view).join(','));
    });

    /**
     * writeFromFile only-cache 模式抛 READ_ONLY
     */
    it('writeFromFile only-cache mode throws READ_ONLY', 0, async () => {
      CacheConstants.setWorkerCachePolicy(true, true, false);
      try {
        const srcPath = testDir + '/readonly-src.kdbx';
        const data = new ArrayBuffer(32);
        const file = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        await fs.write(file.fd, data);
        await fs.close(file.fd);

        const destPath = testDir + '/readonly-dest.kdbx';
        try {
          await cacheStorage.writeFromFile(destPath, srcPath);
          expect(false).assertTrue();
        } catch (error) {
          // KdbxError READ_ONLY
          expect(error.message.includes('READ_ONLY')).assertTrue();
        }
      } finally {
        CacheConstants.setWorkerCachePolicy(true, false, false);
      }
    });

    /**
     * readToFile only-cache 模式从缓存复制
     */
    it('readToFile only-cache mode reads from cache', 0, async () => {
      // 先写一个文件到远端 + 缓存
      const remotePath = testDir + '/cache-only-remote.kdbx';
      const data = new ArrayBuffer(128);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = i;
      }
      const file = await fs.open(remotePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data);
      await fs.close(file.fd);

      // 先用正常模式 readToFile 触发缓存写入（CacheStorage 默认模式不自动缓存 readToFile，
      // 需要手动写缓存文件）
      const cachePath = CacheConstants.getCacheFilePath(remotePath);
      const cacheDir = CacheConstants.getCacheDir();
      if (!fs.accessSync(cacheDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(cacheDir, true);
      }
      const cacheFile = await fs.open(cachePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(cacheFile.fd, data);
      await fs.close(cacheFile.fd);

      // 切换到 only-cache 模式
      CacheConstants.setWorkerCachePolicy(true, true, false);
      try {
        const destPath = testDir + '/cache-only-dest.kdbx';
        const info = await cacheStorage.readToFile(remotePath, destPath);
        expect(info.size).assertEqual(128);
        const buf = await readFile(destPath);
        expect(Array.from(new Uint8Array(buf)).join(',')).assertEqual(Array.from(view).join(','));
      } finally {
        CacheConstants.setWorkerCachePolicy(true, false, false);
      }
    });

    /**
     * write 将上传进度回调透传给底层存储（正常模式：缓存异步写 + 远端推送）
     */
    it('write forwards onProgress to decorated storage', 0, async () => {
      const stub = new ProgressStubStorage();
      const stubCache = new CacheStorage(stub);
      const remotePath = testDir + '/progress-passthrough.kdbx';
      const data = new ArrayBuffer(10);

      const transferredList: number[] = [];
      const totalList: number[] = [];
      await stubCache.write(remotePath, data, undefined,
        (transferredBytes: number, totalBytes: number): void => {
          transferredList.push(transferredBytes);
          totalList.push(totalBytes);
        });

      // 底层 write 调用一次，进度事件两段完整透传
      expect(stub.writeCalls).assertEqual(1);
      expect(stub.lastWritePath).assertEqual(remotePath);
      expect(transferredList.length).assertEqual(2);
      expect(transferredList[0]).assertEqual(5);
      expect(transferredList[1]).assertEqual(10);
      expect(totalList[0]).assertEqual(10);
      expect(totalList[1]).assertEqual(10);
    });
  });
}

async function readFile(path: string): Promise<ArrayBuffer> {
  const file = await fs.open(path, fs.OpenMode.READ_ONLY);
  const stat = await fs.stat(file.fd);
  const buf = new ArrayBuffer(stat.size);
  await fs.read(file.fd, buf);
  await fs.close(file.fd);
  return buf;
}
