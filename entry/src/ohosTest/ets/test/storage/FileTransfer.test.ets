import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { FileTransfer } from '../../../../main/ets/storage/FileTransfer';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { FileInfo, FileType, IFileStorage, StorageConfig, PageConfig, WriteOption } from '../../../../main/ets/storage';

function initTestContext(): common.Context {
  const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  CommonUtils.init(appContext as common.UIAbilityContext);
  return appContext;
}

/**
 * 用于测试的 IFileStorage 桩：记录 read/write/getInfo 调用，验证默认实现委托链
 */
class StubStorage implements IFileStorage {
  readCalls = 0;
  writeCalls = 0;
  getInfoCalls = 0;
  private data: ArrayBuffer;

  constructor(data: ArrayBuffer) {
    this.data = data;
  }

  getPageConfig(): PageConfig {
    return {} as PageConfig;
  }
  init(config: StorageConfig): void {}
  async read(path: string): Promise<ArrayBuffer> {
    this.readCalls++;
    return this.data;
  }
  async write(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void> {
    this.writeCalls++;
    this.data = content;
  }
  async exists(path: string): Promise<boolean> { return true; }
  async getInfo(path: string): Promise<FileInfo> {
    this.getInfoCalls++;
    return {
      name: 'stub.bin',
      size: this.data.byteLength,
      modifiedTime: Date.now(),
      path: path,
      type: FileType.FILE,
      childrenCount: 0,
      version: 'stub-version'
    } as FileInfo;
  }
  async listDir(path: string): Promise<FileInfo[]> { return []; }
  async readToFile(path: string, destPath: string): Promise<FileInfo> {
    return FileTransfer.readToFileDefault(this, path, destPath);
  }
  async writeFromFile(path: string, srcPath: string, option?: WriteOption): Promise<FileInfo> {
    return FileTransfer.writeFromFileDefault(this, path, srcPath, option);
  }
}

export default function FileTransferTest() {
  describe('FileTransferTest', () => {
    let testDir: string;

    beforeAll(() => {
      const appContext = initTestContext();
      testDir = appContext.filesDir + '/filetransfer-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
    });

    /**
     * writeBufferToFile 写入内容正确
     */
    it('writeBufferToFile writes content correctly', 0, async () => {
      const data = new ArrayBuffer(128);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = i;
      }
      const destPath = testDir + '/writebuf.bin';
      await FileTransfer.writeBufferToFile(data, destPath);

      const file = await fs.open(destPath, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      expect(stat.size).assertEqual(128);
      const buf = new ArrayBuffer(128);
      await fs.read(file.fd, buf);
      await fs.close(file.fd);
      expect(Array.from(new Uint8Array(buf)).join(',')).assertEqual(Array.from(view).join(','));
    });

    /**
     * readFileToBuffer 读取内容正确
     */
    it('readFileToBuffer reads content correctly', 0, async () => {
      const data = new ArrayBuffer(256);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = (i * 3) % 256;
      }
      const srcPath = testDir + '/readbuf.bin';
      const file = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data);
      await fs.close(file.fd);

      const buf = await FileTransfer.readFileToBuffer(srcPath);
      expect(buf.byteLength).assertEqual(256);
      expect(Array.from(new Uint8Array(buf)).join(',')).assertEqual(Array.from(view).join(','));
    });

    /**
     * readToFileDefault 调用 read() + getInfo()，落盘内容正确
     */
    it('readToFileDefault calls read and getInfo, writes file', 0, async () => {
      const data = new ArrayBuffer(64);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = i;
      }
      const stub = new StubStorage(data);
      const destPath = testDir + '/default-read.bin';
      const info = await FileTransfer.readToFileDefault(stub, 'remote.bin', destPath);

      expect(stub.readCalls).assertEqual(1);
      expect(stub.getInfoCalls).assertEqual(1);
      expect(info.size).assertEqual(64);

      const buf = await FileTransfer.readFileToBuffer(destPath);
      expect(Array.from(new Uint8Array(buf)).join(',')).assertEqual(Array.from(view).join(','));
    });

    /**
     * writeFromFileDefault 调用 write() + getInfo()，读源文件正确
     */
    it('writeFromFileDefault reads src and calls write', 0, async () => {
      const data = new ArrayBuffer(32);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = i;
      }
      const srcPath = testDir + '/default-write-src.bin';
      const file = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data);
      await fs.close(file.fd);

      const stub = new StubStorage(new ArrayBuffer(0));
      const info = await FileTransfer.writeFromFileDefault(stub, 'remote.bin', srcPath);

      expect(stub.writeCalls).assertEqual(1);
      expect(stub.getInfoCalls).assertEqual(1);
      expect(info.size).assertEqual(32);
    });

    /**
     * fileInfoFromLocal 从本地 stat 构造 FileInfo
     */
    it('fileInfoFromLocal builds FileInfo from stat', 0, async () => {
      const data = new ArrayBuffer(100);
      const localPath = testDir + '/fileinfo.bin';
      const file = await fs.open(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data);
      await fs.close(file.fd);

      const info = await FileTransfer.fileInfoFromLocal(localPath, 'original/path.bin');
      expect(info.size).assertEqual(100);
      expect(info.path).assertEqual('original/path.bin');
      expect(info.version!.includes('100')).assertTrue();
    });
  });
}
