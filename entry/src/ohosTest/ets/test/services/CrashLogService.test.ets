import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CrashLogService } from '../../../../main/ets/services/CrashLogService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

export default function CrashLogServiceTest() {
  describe('CrashLogService', () => {
    let appContext: common.Context;
    let testDir: string;

    beforeAll(async () => {
      appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      testDir = (appContext as common.Context).cacheDir + '/crash_test_dir';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
      CrashLogService.getInstance().unsubscribeCrashEvent();
    });

    it('getInstance returns the singleton instance', 0, () => {
      const a = CrashLogService.getInstance();
      const b = CrashLogService.getInstance();
      expect(a === b).assertTrue();
    });

    it('hasCrashLog returns false before init (no log dir configured)', 0, async () => {
      const v = await CrashLogService.getInstance().hasCrashLog();
      expect(v).assertFalse();
    });

    it('getCrashLogFiles returns empty array before init', 0, async () => {
      const files = await CrashLogService.getInstance().getCrashLogFiles();
      expect(files.length).assertEqual(0);
    });

    it('getLatestCrashLogPath returns null before init', 0, async () => {
      const p = await CrashLogService.getInstance().getLatestCrashLogPath();
      expect(p).assertNull();
    });

    it('clearCrashLog returns false before init', 0, async () => {
      const v = await CrashLogService.getInstance().clearCrashLog();
      expect(v).assertFalse();
    });

    it('deleteCrashLog returns false before init', 0, async () => {
      const v = await CrashLogService.getInstance().deleteCrashLog('whatever.log');
      expect(v).assertFalse();
    });

    it('readCrashLog returns empty string for a non-existent path', 0, async () => {
      const v = await CrashLogService.getInstance().readCrashLog(testDir + '/no_such_file.log');
      expect(v).assertEqual('');
    });

    it('unsubscribeCrashEvent is a no-op before subscribing (no throw)', 0, () => {
      let threw = false;
      try {
        CrashLogService.getInstance().unsubscribeCrashEvent();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('readCrashLog reads back a real file content', 0, async () => {
      const filePath = testDir + '/readable.log';
      const file = fs.openSync(filePath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, 'crash-body');
      fs.closeSync(file);
      try {
        const text = await CrashLogService.getInstance().readCrashLog(filePath);
        expect(text).assertEqual('crash-body');
      } finally {
        fs.unlinkSync(filePath);
      }
    });

    it('init initializes service and unsubscribes cleanly', 0, async () => {
      let threw = false;
      try {
        await CrashLogService.getInstance().init(appContext as common.UIAbilityContext);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      CrashLogService.getInstance().unsubscribeCrashEvent();
      expect(true).assertTrue();
    });

    it('after init, getCrashLogFiles returns empty on clean dir', 0, async () => {
      await CrashLogService.getInstance().init(appContext as common.UIAbilityContext);
      try {
        const files = await CrashLogService.getInstance().getCrashLogFiles();
        expect(files.length).assertEqual(0);
        const latest = await CrashLogService.getInstance().getLatestCrashLogPath();
        expect(latest).assertNull();
      } finally {
        CrashLogService.getInstance().unsubscribeCrashEvent();
      }
    });

    it('clearCrashLog returns true after init on empty dir', 0, async () => {
      await CrashLogService.getInstance().init(appContext as common.UIAbilityContext);
      try {
        const v = await CrashLogService.getInstance().clearCrashLog();
        expect(v).assertTrue();
      } finally {
        CrashLogService.getInstance().unsubscribeCrashEvent();
      }
    });
  });
}
