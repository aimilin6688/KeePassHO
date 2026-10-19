import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, contextConstant } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CrashLogService } from '../../../../main/ets/services/CrashLogService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { TestContextHelper } from '../TestContextHelper';

/**
 * 既有崩溃日志快照（名称 + 内容），测试结束恢复，避免误删主应用真实崩溃日志。
 */
interface CrashFileSnapshot {
  name: string;
  content: string;
}

function listCrashLogNames(dir: string): string[] {
  const names: string[] = [];
  try {
    const all = fs.listFileSync(dir);
    for (let i = 0; i < all.length; i++) {
      if (all[i].startsWith('crash_') && all[i].endsWith('.log')) {
        names.push(all[i]);
      }
    }
  } catch (e) {
  }
  return names;
}

function readTextIfExists(path: string): string | null {
  try {
    return fs.readTextSync(path);
  } catch (e) {
    return null;
  }
}

function writeTextFile(path: string, content: string): void {
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(file.fd, content);
  fs.closeSync(file);
}

/**
 * 按服务同款规则推导崩溃日志目录（EL1 filesDir/crash_logs，创建失败回退默认上下文）。
 */
function deriveLogDir(context: common.Context): string {
  try {
    const el1 = context.createAreaModeContext(contextConstant.AreaMode.EL1);
    return el1.filesDir + '/crash_logs';
  } catch (e) {
    return context.filesDir + '/crash_logs';
  }
}

let crashSnapshot: CrashFileSnapshot[] = [];

function takeCrashSnapshot(dir: string): void {
  crashSnapshot = [];
  const names = listCrashLogNames(dir);
  for (let i = 0; i < names.length; i++) {
    const content = readTextIfExists(`${dir}/${names[i]}`);
    if (content !== null) {
      const item: CrashFileSnapshot = { name: names[i], content: content };
      crashSnapshot.push(item);
    }
  }
}

function restoreCrashSnapshot(dir: string): void {
  const names = listCrashLogNames(dir);
  for (let i = 0; i < names.length; i++) {
    if (names[i].startsWith('crash_9000')) {
      try {
        fs.unlinkSync(`${dir}/${names[i]}`);
      } catch (e) {
      }
    }
  }
  for (let i = 0; i < crashSnapshot.length; i++) {
    writeTextFile(`${dir}/${crashSnapshot[i].name}`, crashSnapshot[i].content);
  }
}

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
      // 快照既有真实崩溃日志：本 describe 的 clearCrashLog 用例会清空目录，afterAll 恢复
      takeCrashSnapshot(deriveLogDir(appContext as common.Context));
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
      CrashLogService.getInstance().unsubscribeCrashEvent();
      restoreCrashSnapshot(deriveLogDir(appContext as common.Context));
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

  /**
   * 崩溃日志文件生命周期：发现/倒序列表/最新路径/读取/删除/清空，非崩溃文件忽略。
   * 测试文件名使用 crash_9000... 前缀（大于任何真实 13 位毫秒时间戳），保证"最新"判定确定性；
   * 既有真实崩溃日志先快照、后恢复。
   */
  describe('CrashLogServiceFiles', () => {
    let logDir: string;

    beforeAll(async () => {
      const context = await TestContextHelper.getUIAbilityContext();
      await CrashLogService.getInstance().init(context);
      logDir = deriveLogDir(context);
      takeCrashSnapshot(logDir);
    });

    afterAll(() => {
      // 清理测试产物（crash_9000 前缀），恢复快照的真实崩溃日志
      restoreCrashSnapshot(logDir);
      CrashLogService.getInstance().unsubscribeCrashEvent();
    });

    it('getCrashLogFiles ignores non-crash files', 0, async () => {
      writeTextFile(`${logDir}/notes.txt`, 'note');
      writeTextFile(`${logDir}/crash_wrong.txt`, 'wrong');
      const files = await CrashLogService.getInstance().getCrashLogFiles();
      expect(files.indexOf('notes.txt')).assertEqual(-1);
      expect(files.indexOf('crash_wrong.txt')).assertEqual(-1);
    });

    it('crash log is discovered, listed and readable', 0, async () => {
      writeTextFile(`${logDir}/crash_90000000000001.log`, 'crash-body-1');
      expect(await CrashLogService.getInstance().hasCrashLog()).assertTrue();
      const files = await CrashLogService.getInstance().getCrashLogFiles();
      expect(files.indexOf('crash_90000000000001.log') >= 0).assertTrue();
      const latest = await CrashLogService.getInstance().getLatestCrashLogPath();
      expect(latest).assertEqual(`${logDir}/crash_90000000000001.log`);
      const text = await CrashLogService.getInstance().readCrashLog(`${logDir}/crash_90000000000001.log`);
      expect(text).assertEqual('crash-body-1');
    });

    it('latest crash log is the newest by name ordering', 0, async () => {
      writeTextFile(`${logDir}/crash_90000000000002.log`, 'crash-body-2');
      const files = await CrashLogService.getInstance().getCrashLogFiles();
      expect(files[0]).assertEqual('crash_90000000000002.log');
      const latest = await CrashLogService.getInstance().getLatestCrashLogPath();
      expect(latest).assertEqual(`${logDir}/crash_90000000000002.log`);
    });

    it('deleteCrashLog removes an existing log and reports true', 0, async () => {
      const ok = await CrashLogService.getInstance().deleteCrashLog('crash_90000000000001.log');
      expect(ok).assertTrue();
      const files = await CrashLogService.getInstance().getCrashLogFiles();
      expect(files.indexOf('crash_90000000000001.log')).assertEqual(-1);
    });

    it('deleteCrashLog reports false for a missing log', 0, async () => {
      const ok = await CrashLogService.getInstance().deleteCrashLog('crash_nonexistent.log');
      expect(ok).assertFalse();
    });

    it('clearCrashLog removes all crash logs and reports true', 0, async () => {
      writeTextFile(`${logDir}/crash_90000000000003.log`, 'crash-body-3');
      const ok = await CrashLogService.getInstance().clearCrashLog();
      expect(ok).assertTrue();
      const files = await CrashLogService.getInstance().getCrashLogFiles();
      expect(files.length).assertEqual(0);
      expect(await CrashLogService.getInstance().hasCrashLog()).assertFalse();
      const latest = await CrashLogService.getInstance().getLatestCrashLogPath();
      expect(latest).assertNull();
    });
  });
}
