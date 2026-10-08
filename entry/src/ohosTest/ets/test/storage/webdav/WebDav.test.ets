import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { WebDavClient, ResultInfo } from '../../../../../main/ets/common/utils/WebDavClient';
import { WebDAVStorage, WebDAVError } from '../../../../../main/ets/storage/webdav/WebDAVStorage';
import { WebDAVStorageConfig } from '../../../../../main/ets/storage/webdav/WebDAVConfig';
import { StorageError, StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { FileInfo } from '../../../../../main/ets/storage/IFileStorage';
import { TestFixtures } from '../TestFixtures';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';

const DOMAIN = 0x0000;
const TAG = 'WebDavTest';

/**
 * 本地 podman WebDAV 服务（搭建步骤见 docs/webdav/webdav-server.md）。
 * 设备侧通过 rport 反向隧道访问宿主机 8800 端口，地址固定为 127.0.0.1:8800。
 * 所有用例使用 rawfile 中的真实 KDBX 数据库文件做读写，不使用 mock 数据。
 */
const WEBDAV_URL = 'http://127.0.0.1:8800/';
const WEBDAV_USER = 'e2e';
const WEBDAV_PASS = 'e2etest123';

function makeWebDavClient(): WebDavClient {
  const client = new WebDavClient({ url: WEBDAV_URL, username: WEBDAV_USER, password: WEBDAV_PASS });
  client.connection();
  return client;
}

/**
 * 空串构造绕过 Sm4 加密（encryptWithPrefix 对空串短路，不触发 Asset Kit），
 * 再覆写明文字段（decryptWithPrefix 对无 SM4: 前缀串原样返回）。
 */
function makeStorageConfig(): WebDAVStorageConfig {
  const config = new WebDAVStorageConfig(WEBDAV_URL, '', '');
  config.username = WEBDAV_USER;
  config.password = WEBDAV_PASS;
  return config;
}

/** 基于夹具生成追加 n 个字节的修改版内容 */
function appendBytes(source: ArrayBuffer, extra: number): ArrayBuffer {
  const modified: ArrayBuffer = new ArrayBuffer(source.byteLength + extra);
  const view = new Uint8Array(modified);
  view.set(new Uint8Array(source), 0);
  for (let i = 0; i < extra; i++) {
    view[source.byteLength + i] = 0x0a;
  }
  return modified;
}

/** 写本地源文件（供 writeFromFile 流式上传用） */
async function writeLocalFile(path: string, data: ArrayBuffer): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    await fs.write(file.fd, data);
    await fs.fsync(file.fd);
  } finally {
    await fs.close(file.fd);
  }
}

/** 运行时获取测试临时文件路径（appContext.filesDir，沙箱路径随进程变化） */
function makeLocalTmpPath(prefix: string): string {
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir
    + '/' + prefix + Date.now() + '.tmp';
}

export default function WebDavTest() {
  describe('WebDavTest', () => {
    let client: WebDavClient;
    const createdPaths: string[] = [];

    beforeAll(() => {
      client = makeWebDavClient();
    });

    afterAll(async () => {
      // 清理本套件创建的远端文件（尽力而为）
      for (const path of createdPaths) {
        try {
          await client.delete(path);
        } catch {
          // 忽略清理失败
        }
      }
      client.close();
    });

    // ==================== WebDavClient 层 ====================

    it('valid should succeed against local webdav server', 0, async () => {
      const response: ResultInfo = await client.valid();

      expect(response).not().assertUndefined();
      expect(response.success).assertTrue();
      // request() 将 2xx（Apache PROPFIND 返回 207）归一化为 200
      expect(response.statusCode).assertEqual(200);
    });

    it('list should return root collection entries', 0, async () => {
      const response: ResultInfo = await client.list('/');

      expect(response.success).assertTrue();
      expect(response.statusCode).assertEqual(200);
      expect(response.data).not().assertUndefined();
      // Depth:1 的 PROPFIND 至少返回根集合自身
      expect(response.data!.length).assertLarger(0);
      hilog.info(DOMAIN, TAG, 'root list contains %{public}d entries', response.data!.length);
    });

    it('exists should return true for root', 0, async () => {
      const exists: boolean = await client.exists('/');
      expect(exists).assertTrue();
    });

    it('exists should return false for non-existent path', 0, async () => {
      const exists: boolean = await client.exists('/non-existent-' + Date.now() + '.kdbx');
      expect(exists).assertFalse();
    });

    it('mkDir and delete should manage remote directory', 0, async () => {
      const dirPath: string = '/e2e-dir-' + Date.now();

      const createResult: ResultInfo = await client.mkDir(dirPath);
      expect(createResult.success).assertTrue();

      const exists: boolean = await client.exists(dirPath);
      expect(exists).assertTrue();

      const deleteResult: ResultInfo = await client.delete(dirPath);
      expect(deleteResult.success).assertTrue();
    });

    // ==================== WebDAVStorage 层（IFileStorage 契约） ====================

    it('storage should write read and get info of real kdbx file', 0, async () => {
      const storage = new WebDAVStorage();
      storage.init(makeStorageConfig());
      const fixture: ArrayBuffer = await TestFixtures.loadUnitTestKdbx();
      const path: string = '/e2e-unit-' + Date.now() + '.kdbx';
      createdPaths.push(path);

      // 写入真实 KDBX 内容
      await storage.write(path, fixture);

      // 存在性
      const exists: boolean = await storage.exists(path);
      expect(exists).assertTrue();

      // 读回内容一致（大小 + KDBX 魔数）
      const readBack: ArrayBuffer = await storage.read(path);
      expect(readBack.byteLength).assertEqual(fixture.byteLength);
      expect(TestFixtures.assertKdbxMagic(readBack)).assertTrue();

      // 文件信息与版本（etag|lastModified 复合串）
      const info: FileInfo = await storage.getInfo(path);
      expect(info.size).assertEqual(fixture.byteLength);
      expect(info.version !== null).assertTrue();
    });

    it('storage conditional write with current version succeeds', 0, async () => {
      const storage = new WebDAVStorage();
      storage.init(makeStorageConfig());
      const fixture: ArrayBuffer = await TestFixtures.loadUnitTestKdbx();
      const path: string = '/e2e-cond-ok-' + Date.now() + '.kdbx';
      createdPaths.push(path);

      // 第一版写入并取得当前版本
      await storage.write(path, fixture);
      const version: string = (await storage.getInfo(path)).version ?? '';

      // 基于当前版本的条件写入（追加 1 字节）必须成功
      const modified: ArrayBuffer = appendBytes(fixture, 1);
      await storage.write(path, modified, { expectedVersion: version });

      // 写入成功后远端为新内容，版本发生变化
      const info2: FileInfo = await storage.getInfo(path);
      expect(info2.size).assertEqual(fixture.byteLength + 1);
      expect(info2.version !== version).assertTrue();
    });

    it('storage conditional write with stale version throws VERSION_CONFLICT', 0, async () => {
      const storage = new WebDAVStorage();
      storage.init(makeStorageConfig());
      const fixture: ArrayBuffer = await TestFixtures.loadUnitTestKdbx();
      const path: string = '/e2e-cond-conflict-' + Date.now() + '.kdbx';
      createdPaths.push(path);

      // 第一版写入并记录版本
      await storage.write(path, fixture);
      const staleVersion: string = (await storage.getInfo(path)).version ?? '';

      // 其他设备先写入新版本（追加 2 字节，etag/last-modified 变化）
      await storage.write(path, appendBytes(fixture, 2));

      // 基于陈旧版本的写入必须以版本冲突失败，不得覆盖远端新版本
      try {
        await storage.write(path, fixture, { expectedVersion: staleVersion });
        expect(false).assertTrue(); // 不应执行到这里
      } catch (error) {
        expect(error instanceof StorageError).assertTrue();
        if (error instanceof StorageError) {
          expect(error.code).assertEqual(StorageErrorCodes.VERSION_CONFLICT);
        }
      }

      // 远端内容仍为新版本（大小 +2），未被陈旧写入覆盖
      const info: FileInfo = await storage.getInfo(path);
      expect(info.size).assertEqual(fixture.byteLength + 2);
    });

    it('storage writeFromFile streams local file to remote', 0, async () => {
      const storage = new WebDAVStorage();
      storage.init(makeStorageConfig());
      const fixture: ArrayBuffer = await TestFixtures.loadUnitTestKdbx();
      const path: string = '/e2e-wff-' + Date.now() + '.kdbx';
      createdPaths.push(path);

      // 写本地源文件
      const srcPath: string = makeLocalTmpPath('wff-');
      await writeLocalFile(srcPath, fixture);
      try {
        // 流式上传（rcp Request + UploadFromFile）
        const info: FileInfo = await storage.writeFromFile(path, srcPath);

        expect(info).not().assertUndefined();
        expect(info.size).assertEqual(fixture.byteLength);

        // 读回远端内容逐字节校验
        const remote: ArrayBuffer = await storage.read(path);
        expect(remote.byteLength).assertEqual(fixture.byteLength);
        expect(TestFixtures.assertKdbxMagic(remote)).assertTrue();
        const a = new Uint8Array(remote);
        const b = new Uint8Array(fixture);
        let mismatch = false;
        for (let i = 0; i < b.length; i++) {
          if (a[i] !== b[i]) {
            mismatch = true;
            break;
          }
        }
        expect(mismatch).assertFalse();
      } finally {
        try { fs.unlinkSync(srcPath); } catch { /* ignore */ }
      }
    });

    it('storage writeFromFile with stale version throws VERSION_CONFLICT', 0, async () => {
      const storage = new WebDAVStorage();
      storage.init(makeStorageConfig());
      const fixture: ArrayBuffer = await TestFixtures.loadUnitTestKdbx();
      const path: string = '/e2e-wff-conflict-' + Date.now() + '.kdbx';
      createdPaths.push(path);

      const srcPath: string = makeLocalTmpPath('wff-conflict-');
      await writeLocalFile(srcPath, fixture);
      try {
        // 第一版写入并记录版本
        await storage.write(path, fixture);
        const staleVersion: string = (await storage.getInfo(path)).version ?? '';

        // 其他设备先写入新版本
        await storage.write(path, appendBytes(fixture, 2));

        // 基于陈旧版本的流式写入必须以版本冲突失败
        try {
          await storage.writeFromFile(path, srcPath, { expectedVersion: staleVersion });
          expect(false).assertTrue(); // 不应执行到这里
        } catch (error) {
          expect(error instanceof StorageError).assertTrue();
          if (error instanceof StorageError) {
            expect(error.code).assertEqual(StorageErrorCodes.VERSION_CONFLICT);
          }
        }

        // 远端内容未被覆盖
        const info: FileInfo = await storage.getInfo(path);
        expect(info.size).assertEqual(fixture.byteLength + 2);
      } finally {
        try { fs.unlinkSync(srcPath); } catch { /* ignore */ }
      }
    });

    it('storage getInfo rejects for non-existent file', 0, async () => {
      const storage = new WebDAVStorage();
      storage.init(makeStorageConfig());

      try {
        await storage.getInfo('/non-existent-' + Date.now() + '.kdbx');
        expect(false).assertTrue(); // 不应执行到这里
      } catch (error) {
        expect(error instanceof WebDAVError).assertTrue();
        if (error instanceof WebDAVError) {
          expect(error.code).assertEqual(404);
        }
      }
    });
  });
}
