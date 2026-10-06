import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { TempFileSweeper } from '../../../../main/ets/services/kdbx/TempFileSweeper';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

/**
 * S7-b 临时文件清扫：管道前缀识别、sweep/sweepSync 清残留且不动其他文件
 */
export default function TempFileSweeperTest() {
  describe('TempFileSweeper', () => {
    let cacheDir: string;

    beforeAll(() => {
      const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      cacheDir = CommonUtils.getCacheDir();
      if (!fs.accessSync(cacheDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(cacheDir, true);
      }
    });

    /**
     * 管道临时文件前缀识别
     */
    it('isPipelineTemp matches pipeline temp names only', 0, () => {
      expect(TempFileSweeper.isPipelineTemp('load_t0_123.tmp')).assertTrue();
      expect(TempFileSweeper.isPipelineTemp('load_t1_123.tmp')).assertTrue();
      expect(TempFileSweeper.isPipelineTemp('load_t2_123.tmp')).assertTrue();
      expect(TempFileSweeper.isPipelineTemp('save_remote_123.tmp')).assertTrue();
      // S6 保存管道临时文件前缀
      expect(TempFileSweeper.isPipelineTemp('save_x1_123.tmp')).assertTrue();
      expect(TempFileSweeper.isPipelineTemp('save_x2_123.tmp')).assertTrue();
      expect(TempFileSweeper.isPipelineTemp('save_x3_123.tmp')).assertTrue();
      // 非管道文件不匹配
      expect(TempFileSweeper.isPipelineTemp('keepme.tmp')).assertFalse();
      expect(TempFileSweeper.isPipelineTemp('other.txt')).assertFalse();
      expect(TempFileSweeper.isPipelineTemp('load_t0_123.bin')).assertFalse();
      expect(TempFileSweeper.isPipelineTemp('load_t9_123.tmp')).assertFalse();
      expect(TempFileSweeper.isPipelineTemp('')).assertFalse();
    });

    /**
     * sweep 清掉全部管道残留且保留无关文件
     */
    it('sweep removes pipeline leftovers and keeps others', 0, async () => {
      const ts = Date.now();
      const leftovers: string[] = [
        'load_t0_' + ts + '.tmp',
        'load_t1_' + ts + '.tmp',
        'load_t2_' + ts + '.tmp',
        'save_remote_' + ts + '.tmp',
        'save_x1_' + ts + '.tmp',
        'save_x2_' + ts + '.tmp',
        'save_x3_' + ts + '.tmp'
      ];
      const keep: string[] = ['keepme-' + ts + '.tmp', 'keepme-' + ts + '.txt'];
      for (const name of leftovers.concat(keep)) {
        const file = fs.openSync(cacheDir + '/' + name,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, 'x');
        fs.closeSync(file);
      }
      const removed = await TempFileSweeper.sweep();
      // 管道文件全部被清
      for (const name of leftovers) {
        expect(fs.accessSync(cacheDir + '/' + name, fs.AccessModeType.EXIST)).assertFalse();
      }
      // 至少清掉了本次创建的 7 个
      expect(removed >= leftovers.length).assertTrue();
      // 无关文件保留
      for (const name of keep) {
        expect(fs.accessSync(cacheDir + '/' + name, fs.AccessModeType.EXIST)).assertTrue();
        fs.unlinkSync(cacheDir + '/' + name);
      }
    });

    /**
     * sweepSync 行为一致（onDestroy 同步路径）
     */
    it('sweepSync removes pipeline leftovers and keeps others', 0, () => {
      const ts = Date.now();
      const leftovers: string[] = [
        'load_t0_' + ts + '.tmp',
        'load_t1_' + ts + '.tmp',
        'save_remote_' + ts + '.tmp'
      ];
      const keep: string[] = ['keepme-' + ts + '.tmp'];
      for (const name of leftovers.concat(keep)) {
        const file = fs.openSync(cacheDir + '/' + name,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, 'x');
        fs.closeSync(file);
      }
      const removed = TempFileSweeper.sweepSync();
      for (const name of leftovers) {
        expect(fs.accessSync(cacheDir + '/' + name, fs.AccessModeType.EXIST)).assertFalse();
      }
      expect(removed >= leftovers.length).assertTrue();
      expect(fs.accessSync(cacheDir + '/' + keep[0], fs.AccessModeType.EXIST)).assertTrue();
      fs.unlinkSync(cacheDir + '/' + keep[0]);
    });

    /**
     * 空目录/无残留时安全返回 0
     */
    it('sweep on clean dir returns 0', 0, async () => {
      const removed = await TempFileSweeper.sweep();
      expect(removed).assertEqual(0);
    });
  });
}
