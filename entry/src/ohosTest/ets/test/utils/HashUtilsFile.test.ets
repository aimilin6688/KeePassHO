import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { HashUtils } from '../../../../main/ets/common/utils/HashUtils';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

function initTestContext(): common.Context {
  const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  CommonUtils.init(appContext as common.UIAbilityContext);
  return appContext;
}

export default function HashUtilsFileTest() {
  describe('HashUtilsFileTest', () => {
    let testDir: string;

    beforeAll(() => {
      const appContext = initTestContext();
      testDir = appContext.filesDir + '/hash-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
    });

    /**
     * sha256HexFile 与 sha256Hex 结果一致（小文件）
     */
    it('sha256HexFile matches sha256Hex for small file', 0, async () => {
      const data = new ArrayBuffer(256);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = i % 256;
      }
      const filePath = testDir + '/small.bin';
      const file = await fs.open(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data);
      await fs.close(file.fd);

      const bufferHash = HashUtils.sha256Hex(data);
      const fileHash = await HashUtils.sha256HexFile(filePath);
      expect(fileHash).assertEqual(bufferHash);
    });

    /**
     * sha256HexFile 分块正确（5MB 文件，跨 4MB 块边界）
     */
    it('sha256HexFile matches for 5MB file crossing chunk boundary', 0, async () => {
      const size = 5 * 1024 * 1024;
      const data = new ArrayBuffer(size);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = (i * 7 + 13) % 256;
      }
      const filePath = testDir + '/large.bin';
      const file = await fs.open(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data);
      await fs.close(file.fd);

      const bufferHash = HashUtils.sha256Hex(data);
      const fileHash = await HashUtils.sha256HexFile(filePath);
      expect(fileHash).assertEqual(bufferHash);
    });

    /**
     * sha256HexFile 空文件
     */
    it('sha256HexFile handles empty file', 0, async () => {
      const filePath = testDir + '/empty.bin';
      const file = await fs.open(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.close(file.fd);

      const emptyBuf = new ArrayBuffer(0);
      const bufferHash = HashUtils.sha256Hex(emptyBuf);
      const fileHash = await HashUtils.sha256HexFile(filePath);
      expect(fileHash).assertEqual(bufferHash);
    });

    /**
     * sha256HexFile 不存在的文件抛错
     */
    it('sha256HexFile throws for nonexistent file', 0, async () => {
      try {
        await HashUtils.sha256HexFile(testDir + '/nonexistent.bin');
        expect(false).assertTrue();
      } catch (error) {
        expect(error instanceof Error).assertTrue();
      }
    });

    /**
     * sha256HexFile 确定性：同一文件多次哈希结果相同
     */
    it('sha256HexFile deterministic across calls', 0, async () => {
      const data = new ArrayBuffer(1024);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = i;
      }
      const filePath = testDir + '/det.bin';
      const file = await fs.open(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data);
      await fs.close(file.fd);

      const h1 = await HashUtils.sha256HexFile(filePath);
      const h2 = await HashUtils.sha256HexFile(filePath);
      expect(h1).assertEqual(h2);
    });
  });
}
