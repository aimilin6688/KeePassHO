import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { FTPStorage } from '../../../../../main/ets/storage/ftp/FTPStorage';
import { FTPStorageConfig, ProtocolType } from '../../../../../main/ets/storage/ftp/FTPConfig';
import { SftpError, SftpErrorCode } from '../../../../../main/ets/storage/ftp/SFTPHandler';
import { StorageError, StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { KdbxFileManager } from '../../../../../main/ets/services/kdbx/KdbxFileManager';
import { RecentFilesService } from '../../../../../main/ets/services/RecentFilesService';
import { RecentFile } from '../../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../../main/ets/storage/StorageType';
import { CacheConstants } from '../../../../../main/ets/storage/cache/CacheConstants';
import { CommonUtils } from '../../../../../main/ets/common/utils/CommonUtils';

/**
 * 注入 ApplicationContext（幂等），供 FTPStorage 临时文件与缓存目录使用。
 * getAppContext 返回应用级 Context，可满足 filesDir/cacheDir 等目录诉求。
 */
function initTestContext(): void {
  const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  CommonUtils.init(appContext as common.UIAbilityContext);
}

/**
 * 构造 SFTP 测试配置：
 * 用空串构造绕过 Sm4 加密（encryptWithPrefix 对空串短路，不触发 Asset Kit），
 * 再覆写明文字段（decryptWithPrefix 对无 SM4: 前缀串原样返回）。
 * 指向 127.0.0.1:1（连接立即被拒绝，确定性失败，不依赖真实网络）。
 */
function makeSftpConfig(port: number): FTPStorageConfig {
  const config = new FTPStorageConfig('', '', '', { protocol: ProtocolType.SFTP, port: port, timeout: 3000 });
  config.host = '127.0.0.1';
  config.username = 'user';
  config.password = 'pass';
  return config;
}

/** 断言 Promise 以指定 SftpErrorCode 拒绝；若 resolve 则断言失败 */
async function expectSftpReject<T>(promise: Promise<T>, expectedCode: SftpErrorCode): Promise<void> {
  try {
    await promise;
    expect(false).assertTrue(); // 不应执行到这里
  } catch (e) {
    expect(e instanceof SftpError).assertTrue();
    if (e instanceof SftpError) {
      expect(e.code).assertEqual(expectedCode);
    }
  }
}

/** 确保缓存目录存在（CacheStorage 写缓存路径的父目录） */
function ensureCacheDirExists(): void {
  const cacheDir = CacheConstants.getCacheDir();
  if (!fs.accessSync(cacheDir, fs.AccessModeType.EXIST)) {
    fs.mkdirSync(cacheDir, true);
  }
}

export default function SFTPStorageSemanticsTest() {
  // FTPStorage 层：L1 语义（网络错误上抛，绝不折叠为 false）
  describe('FTPStorageSftpSemanticsTest', () => {
    beforeAll(() => {
      initTestContext();
    })
    beforeEach(() => {
    })
    afterEach(() => {
    })
    afterAll(() => {
    })

    it('parseConfig defaults port to 22 for SFTP protocol', 0, () => {
      const config = new FTPStorageConfig('', '', '', { protocol: ProtocolType.SFTP });
      expect(config.port).assertEqual(22);
      expect(config.isSFTP()).assertTrue();
    });

    it('parseConfig defaults port to 21 for FTP protocol', 0, () => {
      const config = new FTPStorageConfig('', '', '', { protocol: ProtocolType.FTP });
      expect(config.port).assertEqual(21);
      expect(config.isSFTP()).assertFalse();
    });

    it('parseConfig keeps explicit port', 0, () => {
      const config = new FTPStorageConfig('', '', '', { protocol: ProtocolType.SFTP, port: 2222 });
      expect(config.port).assertEqual(2222);
    });

    it('parseConfig passthrough for FTPStorageConfig instance', 0, () => {
      const config = makeSftpConfig(1);
      const parsed = FTPStorage.parseConfig(config);
      expect(parsed).assertEqual(config);
    });

    it('parseConfig maps plain object (from JSON) with SFTP protocol and string port', 0, () => {
      // 模拟从持久化 JSON 恢复的配置：非 FTPStorageConfig 实例、port 为字符串
      const raw: string = '{"host":"","username":"","password":"","protocol":"SFTP","port":"2222"}';
      const record = JSON.parse(raw) as FTPStorageConfig;
      const parsed = FTPStorage.parseConfig(record);
      expect(parsed.isSFTP()).assertTrue();
      expect(parsed.port).assertEqual(2222);
    });

    it('supportsVersionFastPath is true for SFTP (stat-based size|mtime version)', 0, () => {
      const storage = new FTPStorage();
      storage.init(makeSftpConfig(1));
      expect(storage.supportsVersionFastPath()).assertTrue();
    });

    it('supportsVersionFastPath is false for FTP (LIST minute-level mtime)', 0, () => {
      const config = new FTPStorageConfig('', '', '', { protocol: ProtocolType.FTP, port: 21, timeout: 3000 });
      config.host = '127.0.0.1';
      config.username = 'user';
      config.password = 'pass';
      const storage = new FTPStorage();
      storage.init(config);
      expect(storage.supportsVersionFastPath()).assertFalse();
    });

    it('supportsVersionFastPath is false before init', 0, () => {
      const storage = new FTPStorage();
      expect(storage.supportsVersionFastPath()).assertFalse();
    });

    it('exists rejects (never false) when SFTP server unreachable — L1 semantics', 0, async () => {
      const storage = new FTPStorage();
      storage.init(makeSftpConfig(1));
      await expectSftpReject(storage.exists('/test.kdbx'), SftpErrorCode.NETWORK_ERROR);
    });

    it('getInfo wraps connection failure into StorageError with sftp code tag', 0, async () => {
      const storage = new FTPStorage();
      storage.init(makeSftpConfig(1));
      try {
        await storage.getInfo('/test.kdbx');
        expect(false).assertTrue();
      } catch (e) {
        expect(e instanceof StorageError).assertTrue();
        if (e instanceof StorageError) {
          expect(e.code).assertEqual(StorageErrorCodes.FILE_INFO_ERROR);
          expect(e.message.includes('[sftp:1]')).assertTrue();
        }
      }
    });

    it('listDir wraps connection failure into StorageError', 0, async () => {
      const storage = new FTPStorage();
      storage.init(makeSftpConfig(1));
      try {
        await storage.listDir('/');
        expect(false).assertTrue();
      } catch (e) {
        expect(e instanceof StorageError).assertTrue();
        if (e instanceof StorageError) {
          expect(e.code).assertEqual(StorageErrorCodes.NOT_IMPLEMENTED);
        }
      }
    });

    it('read wraps connection failure into StorageError', 0, async () => {
      const storage = new FTPStorage();
      storage.init(makeSftpConfig(1));
      try {
        await storage.read('/test.kdbx');
        expect(false).assertTrue();
      } catch (e) {
        expect(e instanceof StorageError).assertTrue();
        if (e instanceof StorageError) {
          expect(e.code).assertEqual(StorageErrorCodes.FILE_READ_ERROR);
        }
      }
    });

    it('write wraps connection failure into StorageError', 0, async () => {
      const storage = new FTPStorage();
      storage.init(makeSftpConfig(1));
      const content = new ArrayBuffer(8);
      try {
        await storage.write('/test.kdbx', content);
        expect(false).assertTrue();
      } catch (e) {
        expect(e instanceof StorageError).assertTrue();
        if (e instanceof StorageError) {
          expect(e.code).assertEqual(StorageErrorCodes.FILE_WRITE_ERROR);
        }
      }
    });
  });

  // CacheStorage 装饰器层：缓存开启（默认）时的回退语义
  describe('CacheStorageSftpSemanticsTest', () => {
    const remotePath = '/sftp_cache_semantics_test.kdbx';

    beforeAll(() => {
      initTestContext();
    })

    it('remote error with no cache copy propagates (record-preserving)', 0, async () => {
      ensureCacheDirExists();
      // 确保无缓存副本
      const cachePath = CacheConstants.getCacheFilePath(remotePath);
      try {
        await fs.unlink(cachePath);
      } catch {
        // 本来就不存在
      }
      const manager = new KdbxFileManager(StorageType.FTP, makeSftpConfig(1));
      await expectSftpReject(manager.exists(remotePath), SftpErrorCode.NETWORK_ERROR);
    });

    it('remote error with cache copy resolves true (offline support)', 0, async () => {
      ensureCacheDirExists();
      // 预置缓存副本
      const cachePath = CacheConstants.getCacheFilePath(remotePath);
      const file = await fs.open(cachePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      await fs.write(file.fd, 'cached-data');
      await fs.close(file.fd);
      try {
        const manager = new KdbxFileManager(StorageType.FTP, makeSftpConfig(1));
        const exists = await manager.exists(remotePath);
        expect(exists).assertTrue();
      } finally {
        try {
          await fs.unlink(cachePath);
        } catch {
          // 忽略清理失败
        }
      }
    });
  });

  // RecentFilesService 层：L2 传播语义（loadMostRecentFile 依赖此行为保留记录）
  describe('RecentFilesSftpSemanticsTest', () => {
    beforeAll(() => {
      initTestContext();
    })

    it('checkFileExists propagates unreachable-SFTP error — L2 semantics', 0, async () => {
      const recentFile: RecentFile = {
        filePath: '/recent_sftp_test.kdbx',
        fileName: 'recent_sftp_test.kdbx',
        storageType: StorageType.FTP,
        storageConfig: makeSftpConfig(1)
      };
      await expectSftpReject(
        RecentFilesService.getInstance().checkFileExists(recentFile),
        SftpErrorCode.NETWORK_ERROR
      );
    });
  });
}
