import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LocalFileStorage } from '../../../../main/ets/storage/local/LocalFileStorage';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { WriteOption } from '../../../../main/ets/storage';

function initTestContext(): common.Context {
  const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  CommonUtils.init(appContext as common.UIAbilityContext);
  return appContext;
}

export default function LocalStorageStreamingTest() {
  describe('LocalStorageStreamingTest', () => {
    let appContext: common.Context;
    let testDir: string;
    let storage: LocalFileStorage;

    beforeAll(() => {
      appContext = initTestContext();
      testDir = appContext.filesDir + '/local-streaming-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
      storage = new LocalFileStorage();
    });

    /**
     * readToFile 用 fs.copyFile 流式拷贝，内容一致
     */
    it('readToFile copies file content correctly', 0, async () => {
      const srcPath = testDir + '/src-read.kdbx';
      const data = new ArrayBuffer(512);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = i % 256;
      }
      const file = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data);
      await fs.close(file.fd);

      const destPath = testDir + '/dest-read.kdbx';
      const info = await storage.readToFile(srcPath, destPath);

      expect(info.size).assertEqual(512);
      const buf = await readFile(destPath);
      expect(Array.from(new Uint8Array(buf)).join(',')).assertEqual(Array.from(view).join(','));
    });

    /**
     * writeFromFile 原子写：写入后内容正确
     */
    it('writeFromFile writes content atomically', 0, async () => {
      const srcData = new ArrayBuffer(256);
      const view = new Uint8Array(srcData);
      for (let i = 0; i < view.length; i++) {
        view[i] = (i * 2) % 256;
      }
      const srcPath = testDir + '/src-write.kdbx';
      const file = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, srcData);
      await fs.close(file.fd);

      const destPath = testDir + '/dest-write.kdbx';
      const info = await storage.writeFromFile(destPath, srcPath);

      expect(info.size).assertEqual(256);
      const buf = await readFile(destPath);
      expect(Array.from(new Uint8Array(buf)).join(',')).assertEqual(Array.from(view).join(','));
    });

    /**
     * writeFromFile 条件写入：expectedVersion 匹配时成功
     */
    it('writeFromFile with matching version succeeds', 0, async () => {
      const destPath = testDir + '/cond-write.kdbx';
      const initData = new ArrayBuffer(100);
      const file = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, initData);
      await fs.close(file.fd);

      const beforeInfo = await storage.getInfo(destPath);
      const version = beforeInfo.version ?? null;
      expect(version === null).assertFalse();

      const srcData = new ArrayBuffer(200);
      const srcPath = testDir + '/cond-src.kdbx';
      const srcFile = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(srcFile.fd, srcData);
      await fs.close(srcFile.fd);

      const option: WriteOption = { expectedVersion: version };
      const info = await storage.writeFromFile(destPath, srcPath, option);
      expect(info.size).assertEqual(200);
    });

    /**
     * writeFromFile 条件写入：expectedVersion 不匹配时抛 VERSION_CONFLICT
     */
    it('writeFromFile with mismatched version throws VERSION_CONFLICT', 0, async () => {
      const destPath = testDir + '/conflict-write.kdbx';
      const initData = new ArrayBuffer(100);
      const file = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, initData);
      await fs.close(file.fd);

      const srcData = new ArrayBuffer(50);
      const srcPath = testDir + '/conflict-src.kdbx';
      const srcFile = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(srcFile.fd, srcData);
      await fs.close(srcFile.fd);

      const option: WriteOption = { expectedVersion: 'wrong-version' };
      try {
        await storage.writeFromFile(destPath, srcPath, option);
        expect(false).assertTrue();
      } catch (error) {
        expect(error.message.includes('VERSION_CONFLICT')).assertTrue();
      }
    });

    /**
     * writeFromFile 原子性：写入后无残留 .tmp 文件
     */
    it('writeFromFile leaves no temp files', 0, async () => {
      const srcData = new ArrayBuffer(128);
      const srcPath = testDir + '/cleanup-src.kdbx';
      const file = await fs.open(srcPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, srcData);
      await fs.close(file.fd);

      const destPath = testDir + '/cleanup-dest.kdbx';
      await storage.writeFromFile(destPath, srcPath);

      // 检查无 .tmp 文件残留
      const entries = fs.listFileSync(testDir);
      const tmpFiles = entries.filter((name: string) => name.includes('.tmp.'));
      expect(tmpFiles.length).assertEqual(0);
    });
  });
}

async function readFile(path: string): Promise<ArrayBuffer> {
  const file = await fs.open(path, fs.OpenMode.READ_ONLY);
  const stat = await fs.stat(file.fd);
  const buf = new ArrayBuffer(stat.size);
  await fs.read(file.fd, buf);
  await fs.close(file.fd);
  return buf;
}
