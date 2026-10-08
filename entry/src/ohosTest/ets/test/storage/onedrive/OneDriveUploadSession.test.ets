import { afterEach, beforeEach, describe, expect, it } from '@ohos/hypium';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import axios from '@ohos/axios';
import { ByteUtils } from 'kdbxweb';
import { OneDriveClient, OneDriveClientOptions } from '../../../../../main/ets/storage/onedrive/OneDriveClient';
import { OneDriveStorage } from '../../../../../main/ets/storage/onedrive/OneDriveStorage';
import { OneDriveStorageConfig } from '../../../../../main/ets/storage/onedrive/OneDriveConfig';
import { StorageError, StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { FileInfo } from '../../../../../main/ets/storage/IFileStorage';

const DOMAIN = 0x0000;
const TAG = 'OneDriveUploadSessionTest';

/**
 * OneDrive 测试公共配置
 * OneDrive 为真实云服务（Microsoft Graph），无法本地自建；
 * 未配置有效令牌时真实 API 用例整体不注册（诚实跳过，对齐 Huawei/PCloud 门控约定，见 docs/storage-regression-test.md）
 */
class OneDriveTestConfig {
  static readonly API_BASE_URL: string = 'https://graph.microsoft.com/v1.0';

  /**
   * 测试用访问令牌（OAuth2 授权流程获取）
   * 为空时真实 API 用例不注册
   */
  static readonly ACCESS_TOKEN: string = '';

  static readonly TIMEOUT: number = 30000;

  /**
   * 测试文件目录（真实上传的文件保留在该目录，便于人工核查后清理）
   */
  static readonly TEST_FOLDER: string = 'keepassho-e2e';

  static isRealApiEnabled(): boolean {
    return OneDriveTestConfig.ACCESS_TOKEN.length > 0;
  }
}

/**
 * 模式字节（确定性，供写入与读回比对）
 */
function expectedPatternByte(index: number): number {
  return (index * 31 + 7) % 256;
}

/**
 * 生成本地模式文件（分块写入约束测试内存）
 */
function writePatternFileSync(path: string, size: number): void {
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  const chunkSize = 1024 * 1024;
  const chunk = new ArrayBuffer(chunkSize);
  const view = new Uint8Array(chunk);
  let offset = 0;
  while (offset < size) {
    const len = Math.min(chunkSize, size - offset);
    for (let i = 0; i < len; i++) {
      view[i] = expectedPatternByte(offset + i);
    }
    fs.writeSync(file.fd, len === chunkSize ? chunk : chunk.slice(0, len), { offset: offset });
    offset += len;
  }
  fs.closeSync(file);
}

/**
 * 校验缓冲区是否与模式内容逐字节一致
 */
function isPatternBuffer(data: ArrayBuffer, expectedSize: number): boolean {
  if (data.byteLength !== expectedSize) {
    return false;
  }
  const view = new Uint8Array(data);
  for (let i = 0; i < view.length; i++) {
    if (view[i] !== expectedPatternByte(i)) {
      return false;
    }
  }
  return true;
}

export default function OneDriveUploadSessionTest() {
  /**
   * 常驻单元测试（无网络依赖）：未初始化拒绝语义
   */
  describe('OneDriveUploadSession', () => {
    it('uploadFromFile fails fast when client not initialized', 0, async () => {
      const client = new OneDriveClient();
      const cacheDir = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir;
      const srcPath = cacheDir + '/onedrive-session-' + Date.now() + '.tmp';
      writePatternFileSync(srcPath, 1024);
      try {
        // 小文件路径：upload() 内部检查 axiosInstance 未初始化即抛出
        const result = await client.uploadFromFile('test.kdbx', srcPath);
        expect(result.success).assertFalse();
        expect(result.message.includes('not initialized')).assertTrue();
      } finally {
        try {
          fs.unlinkSync(srcPath);
        } catch {
          // ignore
        }
      }
    });

    it('storage writeFromFile rejects with CLIENT_UNDEFINED before init', 0, async () => {
      const storage = new OneDriveStorage();
      try {
        await storage.writeFromFile('test.kdbx', '/nonexistent/path');
        expect(true).assertFalse(); // 不应执行到这里
      } catch (error) {
        const storageError = error as StorageError;
        expect(storageError.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
      }
    });

    it('storage write rejects with CLIENT_UNDEFINED before init', 0, async () => {
      const storage = new OneDriveStorage();
      try {
        await storage.write('test.kdbx', new ArrayBuffer(16));
        expect(true).assertFalse(); // 不应执行到这里
      } catch (error) {
        const storageError = error as StorageError;
        expect(storageError.code).assertEqual(StorageErrorCodes.CLIENT_UNDEFINED);
      }
    });

    it('parseResource extracts eTag for version baseline', 0, () => {
      const client = new OneDriveClient();
      const data: Record<string, Object> = {
        'id': 'item-123',
        'name': 'test.kdbx',
        'size': 1024,
        'lastModifiedDateTime': '2026-10-08T00:00:00Z',
        'eTag': '"{item-123}, 1"',
        'file': {}
      };
      const resource = client.parseResource(data);
      expect(resource.type).assertEqual('file');
      expect(resource.eTag).assertEqual('"{item-123}, 1"');
    });

    it('parseResource leaves eTag undefined when Graph omits it', 0, () => {
      const client = new OneDriveClient();
      const data: Record<string, Object> = {
        'id': 'folder-1',
        'name': 'docs',
        'lastModifiedDateTime': '2026-10-08T00:00:00Z',
        'folder': { 'childCount': 3 }
      };
      const resource = client.parseResource(data);
      expect(resource.type).assertEqual('folder');
      expect(resource.eTag).assertUndefined();
    });
  });

  // 真实 Graph API 用例：未配置令牌时整体不注册（诚实跳过，见 OneDriveTestConfig.isRealApiEnabled）
  if (OneDriveTestConfig.isRealApiEnabled()) {
    describe('OneDriveUploadSession_RealApi', () => {
      let client: OneDriveClient;

      beforeEach(() => {
        const options: OneDriveClientOptions = {
          apiBaseUrl: OneDriveTestConfig.API_BASE_URL,
          accessToken: OneDriveTestConfig.ACCESS_TOKEN,
          timeout: OneDriveTestConfig.TIMEOUT
        };
        client = new OneDriveClient(options);
      });

      afterEach(() => {
        if (client) {
          client.close();
        }
      });

      it('createUploadSession returns uploadUrl then cancels', 0, async () => {
        const path = OneDriveTestConfig.TEST_FOLDER + '/session-create-' + Date.now() + '.dat';
        const result = await client.createUploadSession(path);
        expect(result.success).assertTrue();

        const sessionJson =
          JSON.parse(ByteUtils.bytesToString(result.body ?? new ArrayBuffer(0))) as Record<string, Object>;
        const uploadUrl = sessionJson['uploadUrl'];
        expect(typeof uploadUrl === 'string').assertTrue();
        if (typeof uploadUrl === 'string') {
          expect(uploadUrl.length > 0).assertTrue();
          hilog.info(DOMAIN, TAG, 'uploadUrl obtained, canceling session');
          // 取消会话，释放服务端会话资源（uploadUrl 预授权，DELETE 无需令牌）
          await axios.delete(uploadUrl);
        }
      });

      it('uploadFromFile round-trips small file via simple put', 0, async () => {
        const path = OneDriveTestConfig.TEST_FOLDER + '/small-' + Date.now() + '.dat';
        const cacheDir = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir;
        const srcPath = cacheDir + '/onedrive-small-' + Date.now() + '.tmp';
        writePatternFileSync(srcPath, 1024);
        try {
          const result = await client.uploadFromFile(path, srcPath);
          expect(result.success).assertTrue();

          const download = await client.get(path);
          expect(download.success).assertTrue();
          expect(isPatternBuffer(download.body ?? new ArrayBuffer(0), 1024)).assertTrue();
          hilog.info(DOMAIN, TAG, 'Small file round-trip verified: %{public}s', path);
        } finally {
          try {
            fs.unlinkSync(srcPath);
          } catch {
            // ignore
          }
        }
      });

      it('uploadFromFile round-trips large file via upload session', 0, async () => {
        const path = OneDriveTestConfig.TEST_FOLDER + '/session-' + Date.now() + '.dat';
        const size = 5 * 1024 * 1024; // > 4MB 阈值 → upload session（5MiB 单分片）
        const cacheDir = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir;
        const srcPath = cacheDir + '/onedrive-large-' + Date.now() + '.tmp';
        writePatternFileSync(srcPath, size);
        try {
          const result = await client.uploadFromFile(path, srcPath);
          expect(result.success).assertTrue();

          const download = await client.get(path);
          expect(download.success).assertTrue();
          expect(isPatternBuffer(download.body ?? new ArrayBuffer(0), size)).assertTrue();
          hilog.info(DOMAIN, TAG, 'Upload session round-trip verified: %{public}s, size=%{public}d', path, size);
        } finally {
          try {
            fs.unlinkSync(srcPath);
          } catch {
            // ignore
          }
        }
      });
    });

    // 存储层版本基线与条件写入（FileInfo.version = eTag|lastModified 复合串）
    describe('OneDriveConditionalWrite_RealApi', () => {
      it('getInfo returns version and write honors expectedVersion', 0, async () => {
        const config = new OneDriveStorageConfig(OneDriveTestConfig.ACCESS_TOKEN, '',
          Date.now() + 3600 * 1000);
        const storage = new OneDriveStorage(config);
        const path = OneDriveTestConfig.TEST_FOLDER + '/cond-' + Date.now() + '.dat';
        const content = new ArrayBuffer(16);

        // 创建文件
        await storage.write(path, content);

        // getInfo 透出 version 基线（eTag 复合串）
        const info: FileInfo = await storage.getInfo(path);
        expect(info.version).not().assertNull();

        // 匹配版本 → 写前复核通过，写入成功
        await storage.write(path, content, { expectedVersion: info.version });

        // 陈旧版本 → 写前复核拒绝
        let caughtCode: number = -1;
        try {
          await storage.write(path, content, { expectedVersion: 'stale-version' });
        } catch (error) {
          caughtCode = (error as StorageError).code;
        }
        expect(caughtCode).assertEqual(StorageErrorCodes.VERSION_CONFLICT);
      });

      it('writeFromFile honors expectedVersion', 0, async () => {
        const config = new OneDriveStorageConfig(OneDriveTestConfig.ACCESS_TOKEN, '',
          Date.now() + 3600 * 1000);
        const storage = new OneDriveStorage(config);
        const path = OneDriveTestConfig.TEST_FOLDER + '/cond-f-' + Date.now() + '.dat';
        const cacheDir = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir;
        const srcPath = cacheDir + '/onedrive-cond-' + Date.now() + '.tmp';
        writePatternFileSync(srcPath, 1024);
        try {
          // 创建远端文件并取得版本基线
          await storage.write(path, new ArrayBuffer(16));
          const info: FileInfo = await storage.getInfo(path);
          expect(info.version).not().assertNull();

          // 匹配版本 → 流式写入成功且返回新版本
          const written: FileInfo = await storage.writeFromFile(path, srcPath, { expectedVersion: info.version });
          expect(written.version).not().assertNull();

          // 陈旧版本 → 写前复核拒绝
          let caughtCode: number = -1;
          try {
            await storage.writeFromFile(path, srcPath, { expectedVersion: 'stale-version' });
          } catch (error) {
            caughtCode = (error as StorageError).code;
          }
          expect(caughtCode).assertEqual(StorageErrorCodes.VERSION_CONFLICT);
        } finally {
          try {
            fs.unlinkSync(srcPath);
          } catch {
            // ignore
          }
        }
      });
    });
  }
}
