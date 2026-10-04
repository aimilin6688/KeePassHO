import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import {
  SFTPConfig,
  SFTPHandler,
  SftpError,
  SftpErrorCode,
  parseSftpErrorCode
} from '../../../../../main/ets/storage/ftp/SFTPHandler';

function makeConfig(): SFTPConfig {
  return {
    host: '127.0.0.1',
    port: 1,
    username: 'user',
    password: 'pass'
  };
}

/** 不可达端口（连接立即被拒绝，确定性失败，不依赖真实网络） */
function makeUnreachableConfig(): SFTPConfig {
  return {
    host: '127.0.0.1',
    port: 1,
    username: 'user',
    password: 'pass',
    timeout: 3000
  };
}

function getCacheDir(): string {
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir;
}

/** 断言 Promise 以指定 SftpErrorCode 拒绝；若 resolve 则断言失败 */
async function expectRejectWithCode<T>(promise: Promise<T>, expectedCode: SftpErrorCode): Promise<void> {
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

export default function SFTPHandlerTest() {
  describe('SFTPHandlerTest', () => {
    beforeAll(() => {
    })
    beforeEach(() => {
    })
    afterEach(() => {
    })
    afterAll(() => {
    })

    it('parseSftpErrorCode parses all coded messages', 0, () => {
      expect(parseSftpErrorCode('[sftp:0] unknown error'))
        .assertEqual(SftpErrorCode.UNKNOWN);
      expect(parseSftpErrorCode('[sftp:1] Connection refused (os error 111)'))
        .assertEqual(SftpErrorCode.NETWORK_ERROR);
      expect(parseSftpErrorCode('[sftp:2] request timeout'))
        .assertEqual(SftpErrorCode.TIMEOUT);
      expect(parseSftpErrorCode('[sftp:3] auth failed'))
        .assertEqual(SftpErrorCode.AUTH_FAILED);
      expect(parseSftpErrorCode('[sftp:4] handshake failed'))
        .assertEqual(SftpErrorCode.HANDSHAKE_FAILED);
      expect(parseSftpErrorCode('[sftp:5] channel error'))
        .assertEqual(SftpErrorCode.CHANNEL_ERROR);
      expect(parseSftpErrorCode('[sftp:6] sftp protocol error'))
        .assertEqual(SftpErrorCode.SFTP_ERROR);
      expect(parseSftpErrorCode('[sftp:7] no such file'))
        .assertEqual(SftpErrorCode.NO_SUCH_FILE);
      expect(parseSftpErrorCode('[sftp:8] disposed'))
        .assertEqual(SftpErrorCode.DISPOSED);
      expect(parseSftpErrorCode('[sftp:9] not connected'))
        .assertEqual(SftpErrorCode.NOT_CONNECTED);
      expect(parseSftpErrorCode('[sftp:10] bad handle'))
        .assertEqual(SftpErrorCode.BAD_HANDLE);
    });

    it('parseSftpErrorCode keeps code within wrapped context', 0, () => {
      const code = parseSftpErrorCode('Failed to download /a.kdbx: [sftp:2] request timeout');
      expect(code).assertEqual(SftpErrorCode.TIMEOUT);
    });

    it('parseSftpErrorCode returns UNKNOWN for non-coded message', 0, () => {
      expect(parseSftpErrorCode('some plain error')).assertEqual(SftpErrorCode.UNKNOWN);
      expect(parseSftpErrorCode('')).assertEqual(SftpErrorCode.UNKNOWN);
      expect(parseSftpErrorCode('no sftp tag: timeout')).assertEqual(SftpErrorCode.UNKNOWN);
    });

    it('parseSftpErrorCode returns UNKNOWN for out-of-range code', 0, () => {
      expect(parseSftpErrorCode('[sftp:99] future code')).assertEqual(SftpErrorCode.UNKNOWN);
      expect(parseSftpErrorCode('[sftp:-1] negative code')).assertEqual(SftpErrorCode.UNKNOWN);
      expect(parseSftpErrorCode('[sftp:abc] non-numeric code')).assertEqual(SftpErrorCode.UNKNOWN);
    });

    it('SftpError carries code and name', 0, () => {
      const err = new SftpError(SftpErrorCode.NO_SUCH_FILE, 'no such file');
      expect(err.name).assertEqual('SftpError');
      expect(err.code).assertEqual(SftpErrorCode.NO_SUCH_FILE);
      expect(err.message).assertEqual('no such file');
      expect(err instanceof Error).assertTrue();

      const timeoutErr = new SftpError(SftpErrorCode.TIMEOUT, 'request timeout');
      expect(timeoutErr.code).assertEqual(SftpErrorCode.TIMEOUT);
      const disposedErr = new SftpError(SftpErrorCode.DISPOSED, 'disposed');
      expect(disposedErr.code).assertEqual(SftpErrorCode.DISPOSED);
    });

    it('isClosed is true before connect', 0, () => {
      const handler = new SFTPHandler(makeConfig());
      expect(handler.isClosed()).assertTrue();
    });

    it('exists rejects with NOT_CONNECTED when never connected', 0, async () => {
      const handler = new SFTPHandler(makeConfig());
      await expectRejectWithCode(handler.exists('/some/path'), SftpErrorCode.NOT_CONNECTED);
    });

    it('exists keeps raw not-connected message through wrapError', 0, async () => {
      const handler = new SFTPHandler(makeConfig());
      try {
        await handler.exists('/some/path');
        expect(false).assertTrue();
      } catch (e) {
        expect(e instanceof SftpError).assertTrue();
        if (e instanceof SftpError) {
          expect(e.message.includes('not connected')).assertTrue();
        }
      }
    });

    it('listDir rejects with NOT_CONNECTED when never connected', 0, async () => {
      const handler = new SFTPHandler(makeConfig());
      await expectRejectWithCode(handler.listDir('/'), SftpErrorCode.NOT_CONNECTED);
    });

    it('listDir rejects with NOT_CONNECTED for empty path', 0, async () => {
      const handler = new SFTPHandler(makeConfig());
      await expectRejectWithCode(handler.listDir(''), SftpErrorCode.NOT_CONNECTED);
    });

    it('downloadFrom rejects with NOT_CONNECTED when never connected', 0, async () => {
      const handler = new SFTPHandler(makeConfig());
      const localPath = getCacheDir() + '/sftp_download_never_connected.tmp';
      await expectRejectWithCode(handler.downloadFrom('/remote.kdbx', localPath), SftpErrorCode.NOT_CONNECTED);
    });

    it('uploadTo rejects when local file does not exist', 0, async () => {
      const handler = new SFTPHandler(makeConfig());
      const localPath = getCacheDir() + '/sftp_nonexistent_' + Date.now() + '.kdbx';
      try {
        await handler.uploadTo(localPath, '/remote.kdbx');
        expect(false).assertTrue();
      } catch (e) {
        // 本地文件打开失败发生在连接检查之前，不是 NOT_CONNECTED
        expect(e instanceof SftpError).assertFalse();
      }
    });

    it('uploadTo rejects with NOT_CONNECTED when local file exists but not connected', 0, async () => {
      const tempPath = getCacheDir() + '/sftp_upload_test_' + Date.now() + '.tmp';
      const file = await fs.open(tempPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      await fs.write(file.fd, 'test-data');
      await fs.close(file.fd);
      try {
        const handler = new SFTPHandler(makeConfig());
        await expectRejectWithCode(handler.uploadTo(tempPath, '/remote.kdbx'), SftpErrorCode.NOT_CONNECTED);
      } finally {
        try {
          await fs.unlink(tempPath);
        } catch {
          // 忽略清理失败
        }
      }
    });

    it('getFileInfo returns root info for slash path', 0, async () => {
      const handler = new SFTPHandler(makeConfig());
      const info = await handler.getFileInfo('/');
      expect(info.name).assertEqual('/');
      expect(info.isDirectory).assertTrue();
      expect(info.size).assertEqual(0);
      expect(info.modifiedTime).assertEqual(0);
    });

    it('getFileInfo returns root info for empty path', 0, async () => {
      const handler = new SFTPHandler(makeConfig());
      const info = await handler.getFileInfo('');
      expect(info.name).assertEqual('/');
      expect(info.isDirectory).assertTrue();
    });

    it('getFileInfo rejects with NOT_CONNECTED for non-root path', 0, async () => {
      const handler = new SFTPHandler(makeConfig());
      await expectRejectWithCode(handler.getFileInfo('/a.kdbx'), SftpErrorCode.NOT_CONNECTED);
    });

    it('close is idempotent when never connected', 0, async () => {
      const handler = new SFTPHandler(makeConfig());
      await handler.close();
      await handler.close();
      expect(handler.isClosed()).assertTrue();
    });
  });

  // 原生 .so 真实路径：模块加载 + tokio + TCP 连接被拒绝（loopback:1，确定性）
  describe('SFTPHandlerConnectTest', () => {
    it('connect to unreachable port rejects with NETWORK_ERROR', 0, async () => {
      const handler = new SFTPHandler(makeUnreachableConfig());
      try {
        await handler.connect();
        expect(false).assertTrue();
      } catch (e) {
        expect(e instanceof SftpError).assertTrue();
        if (e instanceof SftpError) {
          expect(e.code).assertEqual(SftpErrorCode.NETWORK_ERROR);
          expect(e.message.includes('[sftp:1]')).assertTrue();
        }
      }
    });

    it('isClosed stays true after failed connect', 0, async () => {
      const handler = new SFTPHandler(makeUnreachableConfig());
      try {
        await handler.connect();
      } catch {
        // 预期失败
      }
      expect(handler.isClosed()).assertTrue();
    });

    it('close resolves after failed connect', 0, async () => {
      const handler = new SFTPHandler(makeUnreachableConfig());
      try {
        await handler.connect();
      } catch {
        // 预期失败
      }
      await handler.close();
      expect(handler.isClosed()).assertTrue();
    });

    it('consecutive connect failures both reject with NETWORK_ERROR', 0, async () => {
      const handler = new SFTPHandler(makeUnreachableConfig());
      await expectRejectWithCode(handler.connect(), SftpErrorCode.NETWORK_ERROR);
      await expectRejectWithCode(handler.connect(), SftpErrorCode.NETWORK_ERROR);
    });

    it('connect with keepaliveSec config rejects with NETWORK_ERROR', 0, async () => {
      const config: SFTPConfig = {
        host: '127.0.0.1',
        port: 1,
        username: 'user',
        password: 'pass',
        timeout: 3000,
        keepaliveSec: 5
      };
      const handler = new SFTPHandler(config);
      await expectRejectWithCode(handler.connect(), SftpErrorCode.NETWORK_ERROR);
    });
  });
}
