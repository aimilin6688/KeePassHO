import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { FTPStorage } from '../../../../../main/ets/storage/ftp/FTPStorage';
import { FTPStorageConfig, ProtocolType } from '../../../../../main/ets/storage/ftp/FTPConfig';
import { StorageError, StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { CommonUtils } from '../../../../../main/ets/common/utils/CommonUtils';
import { FileInfo } from '../../../../../main/ets/storage/IFileStorage';
import { TestFixtures } from '../TestFixtures';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'SFTPStorageRealFileTest';

/**
 * SFTP 真实存储操作测试。
 *
 * 依赖本地 podman sftp-e2e 容器（搭建步骤见 docs/ftp/sftp-server.md），
 * 设备侧通过 rport 反向隧道访问：hdc rport tcp:2223 tcp:2222。
 * 所有用例使用 rawfile 中的真实 KDBX 数据库文件做读写，不使用 mock 数据。
 */
const SFTP_HOST = '127.0.0.1';
const SFTP_PORT = 2223;
const SFTP_USER = 'e2e';
const SFTP_PASS = 'e2epass';

/**
 * 空串构造绕过 Sm4 加密（encryptWithPrefix 对空串短路，不触发 Asset Kit），
 * 再覆写明文字段（decryptWithPrefix 对无 SM4: 前缀串原样返回）。
 */
function makeRealSftpConfig(): FTPStorageConfig {
  const config = new FTPStorageConfig('', '', '', { protocol: ProtocolType.SFTP, port: SFTP_PORT, timeout: 30000 });
  config.host = SFTP_HOST;
  config.username = SFTP_USER;
  config.password = SFTP_PASS;
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

export default function SFTPStorageRealFileTest() {
  describe('SFTPStorageRealFileTest', () => {
    let storage: FTPStorage;
    let fixture: ArrayBuffer;
    // atmoz/sftp chroot：用户根目录即 /home/e2e，data 子目录对 e2e 用户可写
    const remotePath: string = '/data/sftp-e2e-unit-' + Date.now() + '.kdbx';

    beforeAll(async () => {
      // 注入 ApplicationContext，供 FTPStorage 临时文件目录使用
      const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      CommonUtils.init(appContext as common.UIAbilityContext);

      fixture = await TestFixtures.loadUnitTestKdbx();
      storage = new FTPStorage();
      storage.init(makeRealSftpConfig());
      hilog.info(DOMAIN, TAG, 'setup done, remotePath=%{public}s, fixtureSize=%{public}d',
        remotePath, fixture.byteLength);
    });

    it('upload real kdbx fixture and read back byte-identical', 0, async () => {
      // 上传真实 KDBX 数据库文件
      await storage.write(remotePath, fixture);

      // 存在性
      const exists: boolean = await storage.exists(remotePath);
      expect(exists).assertTrue();

      // 读回内容一致（大小 + KDBX 魔数）
      const readBack: ArrayBuffer = await storage.read(remotePath);
      expect(readBack.byteLength).assertEqual(fixture.byteLength);
      expect(TestFixtures.assertKdbxMagic(readBack)).assertTrue();
    });

    it('getInfo returns exact size and size-mtime version', 0, async () => {
      const info: FileInfo = await storage.getInfo(remotePath);

      expect(info.size).assertEqual(fixture.byteLength);
      // 版本语义：size|mtime 复合串（见 docs/多设备并发编辑冲突解决方案设计-版本检测与条件写入.md）
      const version: string = info.version ?? '';
      expect(version.includes('|')).assertTrue();
    });

    it('conditional write with current version succeeds', 0, async () => {
      // 取当前版本
      const version: string = (await storage.getInfo(remotePath)).version ?? '';

      // 基于当前版本的条件写入（追加 1 字节）必须成功
      await storage.write(remotePath, appendBytes(fixture, 1), { expectedVersion: version });

      // 写入成功后远端为新内容，size/mtime 版本发生变化
      const info2: FileInfo = await storage.getInfo(remotePath);
      expect(info2.size).assertEqual(fixture.byteLength + 1);
      expect(info2.version !== version).assertTrue();
    });

    it('conditional write with stale version throws VERSION_CONFLICT', 0, async () => {
      // 记录当前版本
      const staleVersion: string = (await storage.getInfo(remotePath)).version ?? '';

      // 其他设备先写入新版本（追加 2 字节，size/mtime 变化）
      await storage.write(remotePath, appendBytes(fixture, 2));

      // 基于陈旧版本的写入必须以版本冲突失败，不得覆盖远端新版本
      try {
        await storage.write(remotePath, fixture, { expectedVersion: staleVersion });
        expect(false).assertTrue(); // 不应执行到这里
      } catch (error) {
        expect(error instanceof StorageError).assertTrue();
        if (error instanceof StorageError) {
          expect(error.code).assertEqual(StorageErrorCodes.VERSION_CONFLICT);
        }
      }

      // 远端内容仍为新版本（大小 +2），未被陈旧写入覆盖
      const info: FileInfo = await storage.getInfo(remotePath);
      expect(info.size).assertEqual(fixture.byteLength + 2);
    });
  });
}
