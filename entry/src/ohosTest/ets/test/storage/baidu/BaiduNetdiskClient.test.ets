import { describe, expect, it } from '@ohos/hypium';
import { BaiduNetdiskClient, BaiduUploadIdExpiredError } from '../../../../../main/ets/storage/baidu/BaiduNetdiskClient';
import { BaiduNetdiskConstants, BaiduFileMeta } from '../../../../../main/ets/storage/baidu/BaiduNetdiskTypes';
import { BaiduNetdiskStorage } from '../../../../../main/ets/storage/baidu/BaiduNetdiskStorage';
import { BaiduNetdiskStorageConfig } from '../../../../../main/ets/storage/baidu/BaiduNetdiskConfig';
import { StorageConfig } from '../../../../../main/ets/storage/StorageConfig';
import { StorageType } from '../../../../../main/ets/storage/StorageType';
import { StorageError, StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';

/**
 * 百度网盘客户端/存储离线单元测试（全部顶层 describe，支持 IDE 单套件运行）：
 * - 路径静态方法（normalizePath/lastSegment/toRemotePath/toLogicalPath）与应用目录映射往返
 * - resolveFileInfo 应用目录合成元信息分支（零网络）
 * - BaiduUploadIdExpiredError 契约
 * - Storage 契约：parseConfig 实例透传/plain 重建、未初始化守卫、PageConfig/版本快速路径
 * 云 API（getUinfo/listDir/download 等）需真实网络，不在本套件覆盖。
 */

/** plain 配置载体：模拟 Worker JSON 通道中的非类实例对象 */
class PlainBaiduConfig implements StorageConfig {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  timeout?: number;
  tokenType?: string;
  scope?: string;

  constructor(accessToken: string, refreshToken: string, expiresAt: number,
    timeout?: number, tokenType?: string, scope?: string) {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    this.expiresAt = expiresAt;
    this.timeout = timeout;
    this.tokenType = tokenType;
    this.scope = scope;
  }
}

export default function BaiduNetdiskClientTest() {
  describe('normalizePath', () => {
    it('empty and whitespace-only input map to root', 0, () => {
      expect(BaiduNetdiskClient.normalizePath('')).assertEqual('/');
      expect(BaiduNetdiskClient.normalizePath('   ')).assertEqual('/');
      expect(BaiduNetdiskClient.normalizePath('/')).assertEqual('/');
    });

    it('prepends leading slash and trims surrounding whitespace', 0, () => {
      expect(BaiduNetdiskClient.normalizePath('path')).assertEqual('/path');
      expect(BaiduNetdiskClient.normalizePath('  /x  ')).assertEqual('/x');
    });

    it('strips trailing slashes while keeping root', 0, () => {
      expect(BaiduNetdiskClient.normalizePath('/p/')).assertEqual('/p');
      expect(BaiduNetdiskClient.normalizePath('/a///')).assertEqual('/a');
      expect(BaiduNetdiskClient.normalizePath('///')).assertEqual('/');
    });

    it('does not collapse internal double slashes and preserves unicode', 0, () => {
      expect(BaiduNetdiskClient.normalizePath('/a//b')).assertEqual('/a//b');
      expect(BaiduNetdiskClient.normalizePath('文件.kdbx')).assertEqual('/文件.kdbx');
    });
  });

  describe('lastSegment', () => {
    it('root and empty input return empty string', 0, () => {
      expect(BaiduNetdiskClient.lastSegment('')).assertEqual('');
      expect(BaiduNetdiskClient.lastSegment('/')).assertEqual('');
    });

    it('returns file name for plain and nested paths', 0, () => {
      expect(BaiduNetdiskClient.lastSegment('b.txt')).assertEqual('b.txt');
      expect(BaiduNetdiskClient.lastSegment('/a/b.txt')).assertEqual('b.txt');
      expect(BaiduNetdiskClient.lastSegment('/a/b/')).assertEqual('b');
      expect(BaiduNetdiskClient.lastSegment('/密码库/工作.kdbx')).assertEqual('工作.kdbx');
    });
  });

  describe('toRemotePath', () => {
    it('logical root and empty input map to app dir', 0, () => {
      expect(BaiduNetdiskClient.toRemotePath('/')).assertEqual(BaiduNetdiskConstants.APP_DIR);
      expect(BaiduNetdiskClient.toRemotePath('')).assertEqual(BaiduNetdiskConstants.APP_DIR);
    });

    it('prepends app dir for logical paths', 0, () => {
      expect(BaiduNetdiskClient.toRemotePath('/db.kdbx'))
        .assertEqual('/apps/KeePassHO/db.kdbx');
      expect(BaiduNetdiskClient.toRemotePath('db.kdbx'))
        .assertEqual('/apps/KeePassHO/db.kdbx');
    });

    it('keeps paths already under app dir unchanged', 0, () => {
      expect(BaiduNetdiskClient.toRemotePath('/apps/KeePassHO'))
        .assertEqual('/apps/KeePassHO');
      expect(BaiduNetdiskClient.toRemotePath('/apps/KeePassHO/x.kdbx'))
        .assertEqual('/apps/KeePassHO/x.kdbx');
    });
  });

  describe('toLogicalPath', () => {
    it('app dir maps to logical root', 0, () => {
      expect(BaiduNetdiskClient.toLogicalPath('/apps/KeePassHO')).assertEqual('/');
    });

    it('strips app dir prefix', 0, () => {
      expect(BaiduNetdiskClient.toLogicalPath('/apps/KeePassHO/db.kdbx')).assertEqual('/db.kdbx');
      expect(BaiduNetdiskClient.toLogicalPath('/apps/KeePassHO/sub/db.kdbx')).assertEqual('/sub/db.kdbx');
    });

    it('returns foreign paths unchanged', 0, () => {
      expect(BaiduNetdiskClient.toLogicalPath('/other/db.kdbx')).assertEqual('/other/db.kdbx');
      expect(BaiduNetdiskClient.toLogicalPath('/apps/KeePassHOX')).assertEqual('/apps/KeePassHOX');
    });
  });

  describe('PathRoundTrip', () => {
    it('toLogicalPath(toRemotePath(p)) equals normalizePath(p)', 0, () => {
      const cases: string[] = ['/', '/db.kdbx', '/密码库/工作.kdbx', 'folder1/folder2/test.kdbx'];
      for (const p of cases) {
        const roundTrip: string = BaiduNetdiskClient.toLogicalPath(BaiduNetdiskClient.toRemotePath(p));
        expect(roundTrip).assertEqual(BaiduNetdiskClient.normalizePath(p));
      }
    });
  });

  describe('ResolveFileInfoAppDirOffline', () => {
    it('synthesizes app dir meta for logical root without network', 0, async () => {
      const client = new BaiduNetdiskClient('tok', (): Promise<string> => Promise.resolve('tok'));
      const meta: BaiduFileMeta | null = await client.resolveFileInfo('/');
      expect(meta !== null).assertTrue();
      expect(meta!.fsId).assertEqual(0);
      expect(meta!.path).assertEqual('/apps/KeePassHO');
      expect(meta!.serverFilename).assertEqual('KeePassHO');
      expect(meta!.isdir).assertEqual(1);
      expect(meta!.size).assertEqual(0);
      expect(meta!.md5).assertEqual('');
      expect(meta!.dlink).assertEqual('');
    });

    it('synthesizes same meta for explicit app dir forms', 0, async () => {
      const client = new BaiduNetdiskClient('tok', (): Promise<string> => Promise.resolve('tok'));
      const explicit: BaiduFileMeta | null = await client.resolveFileInfo('/apps/KeePassHO');
      const trailing: BaiduFileMeta | null = await client.resolveFileInfo('/apps/KeePassHO/');
      expect(explicit !== null && trailing !== null).assertTrue();
      expect(explicit!.path).assertEqual(trailing!.path);
      expect(explicit!.serverFilename).assertEqual(trailing!.serverFilename);
    });
  });

  describe('BaiduUploadIdExpiredError', () => {
    it('carries name, errno and formatted message', 0, () => {
      const err = new BaiduUploadIdExpiredError(31363, 'task not found');
      expect(err instanceof Error).assertTrue();
      expect(err.name).assertEqual('BaiduUploadIdExpiredError');
      expect(err.errno).assertEqual(31363);
      expect(err.message).assertEqual('uploadid expired (errno=31363): task not found');
    });
  });

  describe('ClientLifecycle', () => {
    it('constructor and updateAccessToken are offline no-throw', 0, () => {
      const client = new BaiduNetdiskClient('tok', (): Promise<string> => Promise.resolve('new'));
      client.updateAccessToken('tok2');
      expect(true).assertTrue();
    });
  });

  describe('BaiduNetdiskStorageContract', () => {
    it('getConfig is undefined before init', 0, () => {
      const storage = new BaiduNetdiskStorage();
      expect(storage.getConfig()).assertUndefined();
    });

    it('parseConfig passes BaiduNetdiskStorageConfig instance through (identity)', 0, () => {
      const cfg = new BaiduNetdiskStorageConfig('acc', 'ref', 12345);
      const storage = new BaiduNetdiskStorage(cfg);
      expect(storage.getConfig() === cfg).assertTrue();
    });

    it('parseConfig rebuilds plain config object and keeps SM4 ciphertext semantics', 0, () => {
      const source = new BaiduNetdiskStorageConfig('plain-acc', 'plain-ref', 98765,
        { timeout: 45000, tokenType: 'Bearer', scope: 'basic' });
      const plain = new PlainBaiduConfig(source.accessToken, source.refreshToken, source.expiresAt,
        source.timeout, source.tokenType, source.scope);
      const storage = new BaiduNetdiskStorage();
      storage.init(plain);
      const got = storage.getConfig();
      expect(got !== undefined).assertTrue();
      expect(got instanceof BaiduNetdiskStorageConfig).assertTrue();
      expect(got !== plain).assertTrue();
      expect(got!.getAccessTokenText()).assertEqual('plain-acc');
      expect(got!.getRefreshTokenText()).assertEqual('plain-ref');
      expect(got!.expiresAt).assertEqual(98765);
      expect(got!.timeout).assertEqual(45000);
      expect(got!.tokenType).assertEqual('Bearer');
      expect(got!.scope).assertEqual('basic');
    });

    it('updateConfig keeps instance identity', 0, () => {
      const storage = new BaiduNetdiskStorage();
      const cfg = new BaiduNetdiskStorageConfig('a2', 'r2', 111);
      storage.updateConfig(cfg);
      expect(storage.getConfig() === cfg).assertTrue();
    });

    it('getPageConfig maps to BAIDU_NETDISK page', 0, () => {
      const storage = new BaiduNetdiskStorage();
      const pageConfig = storage.getPageConfig();
      expect(pageConfig.pageUrl).assertEqual('storage/baidu/BaiduNetdiskPage');
      expect(pageConfig.storageType).assertEqual(StorageType.BAIDU_NETDISK);
    });

    it('supportsVersionFastPath is true', 0, () => {
      expect(new BaiduNetdiskStorage().supportsVersionFastPath()).assertTrue();
    });

    it('uninitialized storage rejects operations with CLIENT_UNDEFINED', 0, async () => {
      const storage = new BaiduNetdiskStorage();
      const buffer = new ArrayBuffer(4);
      const cases: Array<() => Promise<void>> = [
        async (): Promise<void> => { await storage.read('/x.kdbx'); },
        async (): Promise<void> => { await storage.write('/x.kdbx', buffer); },
        async (): Promise<void> => { await storage.listDir('/'); },
        async (): Promise<void> => { await storage.getInfoOrNull('/x.kdbx'); },
        async (): Promise<void> => { await storage.getUserInfo(); },
        async (): Promise<void> => { await storage.getQuota(); }
      ];
      for (const run of cases) {
        let rejected = false;
        let codeMatches = false;
        try {
          await run();
        } catch (error) {
          rejected = true;
          codeMatches = error instanceof StorageError
            && (error as StorageError).code === StorageErrorCodes.CLIENT_UNDEFINED;
        }
        expect(rejected).assertTrue();
        expect(codeMatches).assertTrue();
      }
    });
  });
}
