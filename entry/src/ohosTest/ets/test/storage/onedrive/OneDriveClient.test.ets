import { describe, expect, it } from '@ohos/hypium';
import { OneDriveClient, OneDriveClientOptions, HttpResponse, OneDrivePathType } from '../../../../../main/ets/storage/onedrive/OneDriveClient';
import { OneDriveStorageConfig } from '../../../../../main/ets/storage/onedrive/OneDriveConfig';
import { OneDriveStorage } from '../../../../../main/ets/storage/onedrive/OneDriveStorage';
import { StorageConfig } from '../../../../../main/ets/storage/StorageConfig';
import { StorageError, StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { StorageType } from '../../../../../main/ets/storage/StorageType';

/**
 * 非 OneDriveStorageConfig 实例的普通配置对象：
 * 携带真实配置的 SM4 密文字段，用于触发 parseConfig 的重建分支
 */
class PlainOneDriveConfig implements StorageConfig {
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

export default function OneDriveClientTest() {
  // 离线契约测试（始终注册，不依赖真实 Microsoft Graph API）：
  // 覆盖 OneDriveClient 纯解析逻辑、未初始化守卫、生命周期与 OneDriveStorage 存储契约
  describe('OneDriveClientContract', () => {
    it('bare constructor leaves network methods guarded', 0, async () => {
      const client = new OneDriveClient();
      let rejected = false;
      let messageMatches = false;
      try {
        await client.valid();
      } catch (error) {
        rejected = true;
        messageMatches = (error as Error).message.includes('not initialized');
      }
      expect(rejected).assertTrue();
      expect(messageMatches).assertTrue();
    });

    it('close() restores the axios guard after updateOptions', 0, async () => {
      const client = new OneDriveClient();
      client.updateOptions({ apiBaseUrl: 'https://example.invalid', accessToken: 't', timeout: 2000 });
      client.close();
      let rejected = false;
      try {
        await client.valid();
      } catch (error) {
        rejected = (error as Error).message.includes('not initialized');
      }
      expect(rejected).assertTrue();
    });

    it('connection() rebuilds axios instance so valid() reaches transport layer', 0, async () => {
      // 127.0.0.1:1 连接立即被拒，离线可靠：axios 请求失败 → convertAxiosError 返回失败响应
      const options: OneDriveClientOptions = { apiBaseUrl: 'http://127.0.0.1:1', accessToken: 't', timeout: 2000 };
      const client = new OneDriveClient(options);
      client.close();
      client.connection();
      const resp: HttpResponse = await client.valid();
      expect(resp instanceof HttpResponse).assertTrue();
      expect(resp.success).assertFalse();
    });

    it('updateAccessToken is a no-throw no-op on uninitialized and initialized clients', 0, () => {
      const bare = new OneDriveClient();
      bare.updateAccessToken('x');
      const inited = new OneDriveClient({ apiBaseUrl: 'https://example.invalid', accessToken: 't' });
      inited.updateAccessToken('y');
      inited.close();
      expect(true).assertTrue();
    });

    it('extractOptionalStringFromObject returns value only for string entries', 0, () => {
      const client = new OneDriveClient();
      const obj: Record<string, Object> = {
        'str': 'v',
        'num': 42
      };
      expect(client.extractOptionalStringFromObject(obj, 'str')).assertEqual('v');
      expect(client.extractOptionalStringFromObject(obj, 'missing')).assertEqual('');
      expect(client.extractOptionalStringFromObject(obj, 'num')).assertEqual('');
    });

    it('parseResource maps full file payload', 0, () => {
      const client = new OneDriveClient();
      const fileFacet: Record<string, Object> = { 'mimeType': 'application/octet-stream' };
      const parentRef: Record<string, Object> = { 'path': '/drive/root:' };
      const data: Record<string, Object> = {
        'id': 'r1',
        'name': 'db.kdbx',
        'size': 42,
        'lastModifiedDateTime': '2026-01-01T00:00:00Z',
        'eTag': 'etag-1',
        'file': fileFacet,
        'parentReference': parentRef,
        '@microsoft.graph.downloadUrl': 'https://dl.example.com/r1'
      };
      const resource = client.parseResource(data);
      expect(resource.id).assertEqual('r1');
      expect(resource.name).assertEqual('db.kdbx');
      expect(resource.type).assertEqual('file');
      expect(resource.size).assertEqual(42);
      expect(resource.lastModified).assertEqual('2026-01-01T00:00:00Z');
      expect(resource.eTag).assertEqual('etag-1');
      expect(resource.path).assertEqual('/db.kdbx');
      expect(resource.downloadUrl).assertEqual('https://dl.example.com/r1');
      expect(resource.childrenCount).assertEqual(0);
      expect(resource.mimeType).assertEqual('application/octet-stream');
    });

    it('parseResource maps folder payload with childrenCount and no mimeType', 0, () => {
      const client = new OneDriveClient();
      const folderFacet: Record<string, Object> = { 'childCount': 3 };
      const data: Record<string, Object> = {
        'id': 'f1',
        'name': 'docs',
        'folder': folderFacet,
        'lastModifiedDateTime': '2026-01-02T00:00:00Z'
      };
      const resource = client.parseResource(data);
      expect(resource.type).assertEqual('folder');
      expect(resource.childrenCount).assertEqual(3);
      expect(resource.size).assertEqual(0);
      expect(resource.mimeType).assertUndefined();
      expect(resource.eTag).assertUndefined();
      // 无 parentReference 时回退到 name 作为路径
      expect(resource.path).assertEqual('docs');
    });

    it('parseResource keeps missing eTag undefined but missing downloadUrl empty', 0, () => {
      const client = new OneDriveClient();
      const resource = client.parseResource({
        'id': 'a', 'name': 'b', 'size': 1
      } as Record<string, Object>);
      expect(resource.eTag).assertUndefined();
      expect(resource.downloadUrl).assertEqual('');
    });

    it('parseResource empty payload yields defaults without throwing', 0, () => {
      const client = new OneDriveClient();
      const resource = client.parseResource({} as Record<string, Object>);
      expect(resource.id).assertEqual('');
      expect(resource.name).assertEqual('');
      expect(resource.type).assertEqual('file');
      expect(resource.size).assertEqual(0);
      expect(resource.path).assertEqual('');
      expect(resource.lastModified).assertEqual('');
      expect(resource.childrenCount).assertEqual(0);
    });

    it('parseResource coerces non-number size to 0', 0, () => {
      const client = new OneDriveClient();
      const resource = client.parseResource({
        'id': 'a', 'name': 'b', 'size': '42'
      } as Record<string, Object>);
      expect(resource.size).assertEqual(0);
    });

    it('parseResourceList maps value array', 0, () => {
      const client = new OneDriveClient();
      const itemA: Record<string, Object> = { 'id': 'a', 'name': 'x' };
      const itemB: Record<string, Object> = { 'id': 'b', 'name': 'y' };
      const items: Array<Record<string, Object>> = [itemA, itemB];
      const data: Record<string, Object> = {
        'value': items
      };
      const list = client.parseResourceList(data);
      expect(list.length).assertEqual(2);
      expect(list[0].id).assertEqual('a');
      expect(list[1].name).assertEqual('y');
    });

    it('parseResourceList returns empty array for missing/non-array value', 0, () => {
      const client = new OneDriveClient();
      expect(client.parseResourceList({} as Record<string, Object>).length).assertEqual(0);
      expect(client.parseResourceList({ 'value': 'x' } as Record<string, Object>).length).assertEqual(0);
      expect(client.parseResourceList({ 'value': [] } as Record<string, Object>).length).assertEqual(0);
    });

    it('OneDrivePathType enum matches Graph API path kinds', 0, () => {
      expect(OneDrivePathType.INFO).assertEqual('info');
      expect(OneDrivePathType.CHILDREN).assertEqual('children');
      expect(OneDrivePathType.CONTENT).assertEqual('content');
      expect(OneDrivePathType.UPLOAD).assertEqual('upload');
      expect(OneDrivePathType.CREATE_UPLOAD_SESSION).assertEqual('createUploadSession');
    });

    it('HttpResponse constructor maps all fields with optional body', 0, () => {
      const body = new ArrayBuffer(4);
      const resp = new HttpResponse(true, 200, 'ok', { 'X': 'Y' }, body);
      expect(resp.success).assertTrue();
      expect(resp.statusCode).assertEqual(200);
      expect(resp.message).assertEqual('ok');
      expect(resp.headers['X']).assertEqual('Y');
      expect(resp.body === body).assertTrue();
      const noBody = new HttpResponse(false, 500, 'e', {});
      expect(noBody.success).assertFalse();
      expect(noBody.statusCode).assertEqual(500);
      expect(noBody.body).assertUndefined();
    });

    it('refreshToken rejects before network when OAuth2 config not set', 0, async () => {
      const client = new OneDriveClient({ apiBaseUrl: 'https://example.invalid', accessToken: 't' });
      let rejected = false;
      let messageMatches = false;
      try {
        await client.refreshToken('rt');
      } catch (error) {
        rejected = true;
        messageMatches = (error as Error).message.includes('OAuth2 config not set');
      }
      expect(rejected).assertTrue();
      expect(messageMatches).assertTrue();
    });

    it('uninitialized client rejects network methods with guards', 0, async () => {
      const client = new OneDriveClient();
      const buffer = new ArrayBuffer(4);
      const axiosGuardCases: Array<() => Promise<HttpResponse>> = [
        (): Promise<HttpResponse> => client.valid(),
        (): Promise<HttpResponse> => client.getInfo('a.txt'),
        (): Promise<HttpResponse> => client.list('root'),
        (): Promise<HttpResponse> => client.get('a.txt')
      ];
      for (const run of axiosGuardCases) {
        let rejected = false;
        let messageMatches = false;
        try {
          await run();
        } catch (error) {
          rejected = true;
          messageMatches = (error as Error).message.includes('Axios instance not initialized');
        }
        expect(rejected).assertTrue();
        expect(messageMatches).assertTrue();
      }
      // upload 的守卫检查 config 而非 axios 实例
      let uploadRejected = false;
      let uploadMessageMatches = false;
      try {
        await client.upload('a.txt', buffer);
      } catch (error) {
        uploadRejected = true;
        uploadMessageMatches = (error as Error).message.includes('OneDriveClient not initialized');
      }
      expect(uploadRejected).assertTrue();
      expect(uploadMessageMatches).assertTrue();
    });
  });

  describe('OneDriveStorageContract', () => {
    it('getPageConfig exposes OneDrive page contract', 0, () => {
      const storage: OneDriveStorage = new OneDriveStorage();
      const pageConfig = storage.getPageConfig();
      expect(pageConfig.pageUrl).assertEqual('storage/onedrive/OneDrivePage');
      expect(pageConfig.storageType).assertEqual(StorageType.ONEDRIVE);
      expect(pageConfig.icon).not().assertUndefined();
      expect(pageConfig.selectDesc).not().assertUndefined();
      expect(pageConfig.saveDesc).not().assertUndefined();
      expect(pageConfig.childDb).not().assertUndefined();
      const title = pageConfig.title as string;
      expect(title).assertEqual('OneDrive');
    });

    it('supportsVersionFastPath opts in (eTag-based fingerprint)', 0, () => {
      const storage: OneDriveStorage = new OneDriveStorage();
      expect(storage.supportsVersionFastPath()).assertTrue();
    });

    it('getConfig is undefined before init', 0, () => {
      const storage: OneDriveStorage = new OneDriveStorage();
      expect(storage.getConfig()).assertUndefined();
    });

    it('init keeps OneDriveStorageConfig instance identity (parseConfig passthrough)', 0, () => {
      const storage: OneDriveStorage = new OneDriveStorage();
      const config: OneDriveStorageConfig = new OneDriveStorageConfig('at', 'rt', 123456);
      storage.init(config);
      expect(storage.getConfig() === config).assertTrue();
    });

    it('init rebuilds config from plain object and round-trips encrypted tokens', 0, () => {
      const original: OneDriveStorageConfig =
        new OneDriveStorageConfig('plain-at', 'plain-rt', 123456,
          { timeout: 8888, tokenType: 'Bearer', scope: 'Files.ReadWrite' });
      const plain: PlainOneDriveConfig =
        new PlainOneDriveConfig(original.accessToken, original.refreshToken, 123456,
          8888, 'Bearer', 'Files.ReadWrite');
      const storage: OneDriveStorage = new OneDriveStorage();
      storage.init(plain);
      const parsed = storage.getConfig();
      expect(parsed).not().assertUndefined();
      // 重建分支：返回新 OneDriveStorageConfig 实例而非原对象
      expect(parsed === plain).assertFalse();
      expect(parsed instanceof OneDriveStorageConfig).assertTrue();
      // encryptWithPrefix 幂等：密文字段再次加密不改变解密结果
      expect(parsed!.getAccessTokenText()).assertEqual('plain-at');
      expect(parsed!.getRefreshTokenText()).assertEqual('plain-rt');
      expect(parsed!.expiresAt).assertEqual(123456);
      expect(parsed!.timeout).assertEqual(8888);
      expect(parsed!.tokenType).assertEqual('Bearer');
      expect(parsed!.scope).assertEqual('Files.ReadWrite');
    });

    it('updateConfig replaces config and re-initializes', 0, () => {
      const storage: OneDriveStorage = new OneDriveStorage();
      const first: OneDriveStorageConfig = new OneDriveStorageConfig('at1', 'rt1', 111);
      const second: OneDriveStorageConfig = new OneDriveStorageConfig('at2', 'rt2', 222);
      storage.init(first);
      storage.updateConfig(second);
      expect(storage.getConfig() === second).assertTrue();
      expect(storage.getConfig()!.getAccessTokenText()).assertEqual('at2');
    });

    it('uninitialized storage rejects operations with CLIENT_UNDEFINED', 0, async () => {
      const storage: OneDriveStorage = new OneDriveStorage();
      const buffer = new ArrayBuffer(4);
      const cases: Array<() => Promise<void>> = [
        async (): Promise<void> => { await storage.read('a.kdbx'); },
        async (): Promise<void> => { await storage.write('a.kdbx', buffer); },
        async (): Promise<void> => { await storage.writeFromFile('a.kdbx', '/nonexistent/src.bin'); },
        async (): Promise<void> => { await storage.readToFile('a.kdbx', '/nonexistent/dst.bin'); },
        async (): Promise<void> => { await storage.getInfoOrNull('a.kdbx'); },
        async (): Promise<void> => { await storage.listDir('root'); }
      ];
      for (const run of cases) {
        let rejected = false;
        let codeMatches = false;
        try {
          await run();
        } catch (error) {
          const storageError = error as StorageError;
          rejected = error instanceof StorageError;
          codeMatches = storageError.code === StorageErrorCodes.CLIENT_UNDEFINED;
        }
        expect(rejected).assertTrue();
        expect(codeMatches).assertTrue();
      }
    });
  });
}
