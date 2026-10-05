import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { DatabaseLoadGuard } from '../../../../main/ets/services/kdbx/DatabaseLoadGuard';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { StorageType } from '../../../../main/ets/storage';

function initTestContext(): common.Context {
  const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  CommonUtils.init(appContext as common.UIAbilityContext);
  return appContext;
}

export default function DatabaseLoadGuardTest() {
  describe('DatabaseLoadGuard', () => {
    let appContext: common.Context;
    let testDir: string;

    beforeAll(() => {
      appContext = initTestContext();
      testDir = appContext.filesDir + '/guard-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
    });

    /**
     * CP1 文件大小守卫：小文件放行
     */
    it('CP1 small file passes', 0, async () => {
      const filePath = testDir + '/small.kdbx';
      const buf = new ArrayBuffer(1024);
      const file = await fs.open(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, buf);
      await fs.close(file.fd);

      const result = await DatabaseLoadGuard.checkBeforeRead(StorageType.LOCAL, undefined, filePath);
      expect(result).assertNull();
    });

    /**
     * CP1 默认上限 512MB 放行正常库（preferences 为 null 时走默认值 512MB）
     */
    it('CP1 default 512MB limit passes normal db', 0, async () => {
      const filePath = testDir + '/normal.kdbx';
      const buf = new ArrayBuffer(4096);
      const file = await fs.open(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, buf);
      await fs.close(file.fd);

      const result = await DatabaseLoadGuard.checkBeforeRead(StorageType.LOCAL, undefined, filePath);
      expect(result).assertNull();
    });

    /**
     * getInfo 失败（文件不存在）时 fail-open 放行
     */
    it('checkBeforeRead fail-open when getInfo fails', 0, async () => {
      const result = await DatabaseLoadGuard.checkBeforeRead(StorageType.LOCAL, undefined,
        testDir + '/nonexistent.kdbx');
      expect(result).assertNull();
    });

    /**
     * CP2' getMaxDecompressedBytes 返回正值且缓存
     */
    it('getMaxDecompressedBytes returns positive value and caches', 0, async () => {
      const v1 = await DatabaseLoadGuard.getMaxDecompressedBytes();
      expect(v1).assertLarger(0);
      const v2 = await DatabaseLoadGuard.getMaxDecompressedBytes();
      expect(v2).assertEqual(v1);
    });

    /**
     * CP2' 上限公式：appMem × 0.55 / 1.3（在合理范围）
     */
    it('getMaxDecompressedBytes within expected range', 0, async () => {
      const v = await DatabaseLoadGuard.getMaxDecompressedBytes();
      // 至少 50MB（即使最小设备 appMem 256MB → 256*0.55/1.3 ≈ 108MB）
      expect(v).assertLargerOrEqual(50 * 1024 * 1024);
      // 不超过 2GB（即使大设备 2048MB → 2048*0.55/1.3 ≈ 866MB）
      expect(v).assertLessOrEqual(2 * 1024 * 1024 * 1024);
    });
  });
}
