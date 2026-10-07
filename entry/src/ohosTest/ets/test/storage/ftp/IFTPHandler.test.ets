import { describe, expect, it } from '@ohos/hypium';
import { FileItemInfo, IFTPHandler } from '../../../../../main/ets/storage/ftp/IFTPHandler';

/**
 * IFTPHandler.ets 是纯接口（含 FileItemInfo 结构）。
 * 此测试手搓一个 StubFTPHandler 实现接口，验证接口契约可被实现并正确工作，
 * 作为 FTPHandler / SFTPHandler 的替身基线（不引入 hamock）。
 */
class StubFTPHandler implements IFTPHandler {
  private connected: boolean = false;
  public lastDownloadRemote: string = '';
  public lastDownloadLocal: string = '';
  public lastUploadLocal: string = '';
  public lastUploadRemote: string = '';

  connect(): Promise<void> {
    this.connected = true;
    return Promise.resolve();
  }

  close(): Promise<void> {
    this.connected = false;
    return Promise.resolve();
  }

  downloadFrom(remotePath: string, localPath: string): Promise<void> {
    if (!this.connected) {
      return Promise.reject(new Error('not connected'));
    }
    this.lastDownloadRemote = remotePath;
    this.lastDownloadLocal = localPath;
    return Promise.resolve();
  }

  uploadTo(localPath: string, remotePath: string): Promise<void> {
    if (!this.connected) {
      return Promise.reject(new Error('not connected'));
    }
    this.lastUploadLocal = localPath;
    this.lastUploadRemote = remotePath;
    return Promise.resolve();
  }

  exists(path: string): Promise<boolean> {
    if (!this.connected) {
      return Promise.reject(new Error('not connected'));
    }
    return Promise.resolve(path === '/exists.kdbx');
  }

  getFileInfo(path: string): Promise<FileItemInfo> {
    if (!this.connected) {
      return Promise.reject(new Error('not connected'));
    }
    const info: FileItemInfo = {
      name: path,
      size: 1024,
      isDirectory: false,
      modifiedTime: 1700000000000
    };
    return Promise.resolve(info);
  }

  listDir(path: string): Promise<Array<FileItemInfo>> {
    if (!this.connected) {
      return Promise.reject(new Error('not connected'));
    }
    const a: FileItemInfo = { name: 'a.kdbx', size: 1, isDirectory: false, modifiedTime: 1 };
    const b: FileItemInfo = { name: 'sub', size: 0, isDirectory: true, modifiedTime: 2 };
    return Promise.resolve(path === '/empty' ? [] : [a, b]);
  }
}

class FileItemInfoImpl implements FileItemInfo {
  name: string = '';
  size: number = 0;
  isDirectory: boolean = false;
  modifiedTime: number = 0;
}

export default function IFTPHandlerTest() {
  describe('IFTPHandlerTest', () => {

    describe('FileItemInfo', () => {
      it('should round-trip all fields for a file entry', 0, () => {
        const info: FileItemInfoImpl = new FileItemInfoImpl();
        info.name = 'db.kdbx';
        info.size = 4096;
        info.isDirectory = false;
        info.modifiedTime = 1700000000000;
        expect(info.name).assertEqual('db.kdbx');
        expect(info.size).assertEqual(4096);
        expect(info.isDirectory).assertFalse();
        expect(info.modifiedTime).assertEqual(1700000000000);
      });

      it('should round-trip all fields for a directory entry', 0, () => {
        const info: FileItemInfoImpl = new FileItemInfoImpl();
        info.name = 'backups';
        info.size = 0;
        info.isDirectory = true;
        info.modifiedTime = 0;
        expect(info.isDirectory).assertTrue();
        expect(info.size).assertEqual(0);
      });
    });

    describe('StubFTPHandler_contract', () => {
      it('should implement IFTPHandler', 0, () => {
        const handler: IFTPHandler = new StubFTPHandler();
        expect(handler).not().assertUndefined();
        expect(typeof handler.connect).assertEqual('function');
        expect(typeof handler.close).assertEqual('function');
        expect(typeof handler.downloadFrom).assertEqual('function');
        expect(typeof handler.uploadTo).assertEqual('function');
        expect(typeof handler.exists).assertEqual('function');
        expect(typeof handler.getFileInfo).assertEqual('function');
        expect(typeof handler.listDir).assertEqual('function');
      });

      it('connect/close should toggle connection state', 0, async () => {
        const handler: StubFTPHandler = new StubFTPHandler();
        await handler.connect();
        await handler.close();
        // disconnect after close: downloadFrom rejects
        try {
          await handler.downloadFrom('/r', '/l');
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertEqual('not connected');
        }
      });

      it('downloadFrom should record paths when connected', 0, async () => {
        const handler: StubFTPHandler = new StubFTPHandler();
        await handler.connect();
        await handler.downloadFrom('/remote.kdbx', '/local.kdbx');
        expect(handler.lastDownloadRemote).assertEqual('/remote.kdbx');
        expect(handler.lastDownloadLocal).assertEqual('/local.kdbx');
        await handler.close();
      });

      it('uploadTo should record paths when connected', 0, async () => {
        const handler: StubFTPHandler = new StubFTPHandler();
        await handler.connect();
        await handler.uploadTo('/local.kdbx', '/remote.kdbx');
        expect(handler.lastUploadLocal).assertEqual('/local.kdbx');
        expect(handler.lastUploadRemote).assertEqual('/remote.kdbx');
        await handler.close();
      });

      it('exists should return true only for /exists.kdbx', 0, async () => {
        const handler: StubFTPHandler = new StubFTPHandler();
        await handler.connect();
        expect(await handler.exists('/exists.kdbx')).assertTrue();
        expect(await handler.exists('/missing.kdbx')).assertFalse();
        await handler.close();
      });

      it('getFileInfo should return a populated FileItemInfo', 0, async () => {
        const handler: StubFTPHandler = new StubFTPHandler();
        await handler.connect();
        const info = await handler.getFileInfo('/a.kdbx');
        expect(info.name).assertEqual('/a.kdbx');
        expect(info.size).assertEqual(1024);
        expect(info.isDirectory).assertFalse();
        expect(info.modifiedTime).assertEqual(1700000000000);
        await handler.close();
      });

      it('listDir should return entries for non-empty path', 0, async () => {
        const handler: StubFTPHandler = new StubFTPHandler();
        await handler.connect();
        const items = await handler.listDir('/dir');
        expect(items.length).assertEqual(2);
        expect(items[0].name).assertEqual('a.kdbx');
        expect(items[1].isDirectory).assertTrue();
        await handler.close();
      });

      it('listDir should return empty array for /empty', 0, async () => {
        const handler: StubFTPHandler = new StubFTPHandler();
        await handler.connect();
        const items = await handler.listDir('/empty');
        expect(items.length).assertEqual(0);
        await handler.close();
      });

      it('all methods should reject when not connected', 0, async () => {
        const handler: StubFTPHandler = new StubFTPHandler();
        const ops: Array<() => Promise<void>> = [
          async (): Promise<void> => { await handler.downloadFrom('/r', '/l'); },
          async (): Promise<void> => { await handler.uploadTo('/l', '/r'); },
          async (): Promise<void> => { await handler.exists('/x'); },
          async (): Promise<void> => { await handler.getFileInfo('/x'); },
          async (): Promise<void> => { await handler.listDir('/x'); }
        ];
        for (let i = 0; i < ops.length; i++) {
          try {
            await ops[i]();
            expect(false).assertTrue();
          } catch (e) {
            expect((e as Error).message).assertEqual('not connected');
          }
        }
      });
    });
  });
}
