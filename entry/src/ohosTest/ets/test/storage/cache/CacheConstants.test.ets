import { afterAll, afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { CacheConstants } from '../../../../../main/ets/storage/cache/CacheConstants';
import { CommonUtils } from '../../../../../main/ets/common/utils/CommonUtils';

export default function CacheConstantsTest() {
  describe('CacheConstantsTest', () => {

    beforeAll(() => {
      const appContext: common.Context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      // 与其它测试一致：主线程默认快照（cache 启用 / 非 only-cache / 不强制刷新）
      CacheConstants.setWorkerCachePolicy(true, false, false);
    });

    afterEach(() => {
      // 恢复默认快照，避免污染后续测试
      CacheConstants.setWorkerCachePolicy(true, false, false);
    });

    afterAll(() => {
      CacheConstants.setWorkerCachePolicy(true, false, false);
    });

    describe('ConstantsInit', () => {
      it('CACHE_DIR_NAME should be cache', 0, () => {
        expect(CacheConstants.CACHE_DIR_NAME).assertEqual('cache');
      });

      it('CACHE_FILE_SUFFIX should be .cache', 0, () => {
        expect(CacheConstants.CACHE_FILE_SUFFIX).assertEqual('.cache');
      });

      it('ONLY_CACHE_KEY should be only_use_cache', 0, () => {
        expect(CacheConstants.ONLY_CACHE_KEY).assertEqual('only_use_cache');
      });

      it('FORCE_REFRESH_KEY should be force_refresh', 0, () => {
        expect(CacheConstants.FORCE_REFRESH_KEY).assertEqual('force_refresh');
      });

      it('constants should be readonly string primitives', 0, () => {
        expect(typeof CacheConstants.CACHE_DIR_NAME).assertEqual('string');
        expect(typeof CacheConstants.CACHE_FILE_SUFFIX).assertEqual('string');
        expect(typeof CacheConstants.ONLY_CACHE_KEY).assertEqual('string');
        expect(typeof CacheConstants.FORCE_REFRESH_KEY).assertEqual('string');
      });
    });

    describe('getCacheDir', () => {
      it('should return a path ending with /cache', 0, () => {
        const dir: string = CacheConstants.getCacheDir();
        expect(dir.length > 0).assertTrue();
        expect(dir.endsWith('/cache')).assertTrue();
      });

      it('should return the same value across calls', 0, () => {
        const a: string = CacheConstants.getCacheDir();
        const b: string = CacheConstants.getCacheDir();
        expect(a).assertEqual(b);
      });

      it('should contain the cache dir name', 0, () => {
        expect(CacheConstants.getCacheDir()).assertContain('cache');
      });
    });

    describe('getCacheFilePath', () => {
      it('should end with the .cache suffix', 0, () => {
        const p: string = CacheConstants.getCacheFilePath('/remote/db.kdbx');
        expect(p.endsWith(CacheConstants.CACHE_FILE_SUFFIX)).assertTrue();
      });

      it('should live under the cache dir', 0, () => {
        const p: string = CacheConstants.getCacheFilePath('/remote/db.kdbx');
        expect(p).assertContain('/cache/');
      });

      it('should be deterministic for the same input', 0, () => {
        const a: string = CacheConstants.getCacheFilePath('/keepass/db.kdbx');
        const b: string = CacheConstants.getCacheFilePath('/keepass/db.kdbx');
        expect(a).assertEqual(b);
      });

      it('should differ for clearly different inputs', 0, () => {
        const a: string = CacheConstants.getCacheFilePath('/keepass/a.kdbx');
        const b: string = CacheConstants.getCacheFilePath('/keepass/b.kdbx');
        expect(a !== b).assertTrue();
      });

      it('should differ from the raw input path', 0, () => {
        const raw: string = '/keepass/db.kdbx';
        const p: string = CacheConstants.getCacheFilePath(raw);
        expect(p !== raw).assertTrue();
      });

      it('should produce a hex filename + .cache suffix', 0, () => {
        const p: string = CacheConstants.getCacheFilePath('/x.kdbx');
        const fileName: string = p.substring(p.lastIndexOf('/') + 1);
        // 文件名 = hex(hash) + '.cache'
        expect(fileName.endsWith('.cache')).assertTrue();
        const hexPart: string = fileName.substring(0, fileName.length - CacheConstants.CACHE_FILE_SUFFIX.length);
        expect(hexPart.length > 0).assertTrue();
        expect(/^[0-9a-f]+$/.test(hexPart)).assertTrue();
      });

      it('should handle empty string input without throwing', 0, () => {
        const p: string = CacheConstants.getCacheFilePath('');
        expect(p.endsWith('.cache')).assertTrue();
      });

      it('should handle unicode input without throwing', 0, () => {
        const p: string = CacheConstants.getCacheFilePath('/数据库/密码库.kdbx');
        expect(p.endsWith('.cache')).assertTrue();
      });
    });

    describe('cacheExists_deleteCache_non_existent', () => {
      it('cacheExists should return false for a never-cached path', 0, async () => {
        const exists: boolean = await CacheConstants.cacheExists('/never-cached-' + Date.now() + '.kdbx');
        expect(exists).assertFalse();
      });

      it('deleteCache should resolve without throwing for non-existent path', 0, async () => {
        await CacheConstants.deleteCache('/never-cached-' + Date.now() + '.kdbx');
        // 不抛出即通过
        expect(true).assertTrue();
      });

      it('cacheExists should return a boolean', 0, async () => {
        const exists: boolean = await CacheConstants.cacheExists('/any-path.kdbx');
        expect(typeof exists).assertEqual('boolean');
      });
    });

    describe('setters_do_not_throw', () => {
      it('setOnlyCache(true) should not throw', 0, () => {
        CacheConstants.setOnlyCache(true);
        expect(true).assertTrue();
      });

      it('setOnlyCache(false) should not throw', 0, () => {
        CacheConstants.setOnlyCache(false);
        expect(true).assertTrue();
      });

      it('setForceRefresh(true) should not throw', 0, () => {
        CacheConstants.setForceRefresh(true);
        expect(true).assertTrue();
      });

      it('setForceRefresh(false) should not throw', 0, () => {
        CacheConstants.setForceRefresh(false);
        expect(true).assertTrue();
      });

      it('clearForceRefresh should not throw', 0, () => {
        CacheConstants.clearForceRefresh();
        expect(true).assertTrue();
      });
    });

    describe('getters_return_booleans', () => {
      it('getOnlyCache should return a boolean', 0, () => {
        expect(typeof CacheConstants.getOnlyCache()).assertEqual('boolean');
      });

      it('getForceRefresh should return a boolean', 0, () => {
        expect(typeof CacheConstants.getForceRefresh()).assertEqual('boolean');
      });

      it('isEnableLocalCache should return a boolean', 0, () => {
        expect(typeof CacheConstants.isEnableLocalCache()).assertEqual('boolean');
      });
    });

    describe('Worker_cache_policy_override', () => {
      // Worker 快照优先于 AppStorage / SettingsService，可确定性测试
      it('setWorkerCachePolicy(true,true,true) should override all three getters', 0, () => {
        CacheConstants.setWorkerCachePolicy(true, true, true);
        expect(CacheConstants.isEnableLocalCache()).assertTrue();
        expect(CacheConstants.getOnlyCache()).assertTrue();
        expect(CacheConstants.getForceRefresh()).assertTrue();
      });

      it('setWorkerCachePolicy(false,false,false) should disable all three', 0, () => {
        CacheConstants.setWorkerCachePolicy(false, false, false);
        expect(CacheConstants.isEnableLocalCache()).assertFalse();
        expect(CacheConstants.getOnlyCache()).assertFalse();
        expect(CacheConstants.getForceRefresh()).assertFalse();
      });

      it('setWorkerCachePolicy(true,true,false) should set enable+only but not force', 0, () => {
        CacheConstants.setWorkerCachePolicy(true, true, false);
        expect(CacheConstants.isEnableLocalCache()).assertTrue();
        expect(CacheConstants.getOnlyCache()).assertTrue();
        expect(CacheConstants.getForceRefresh()).assertFalse();
      });

      it('setWorkerCachePolicy(true,false,true) should set enable+force but not only', 0, () => {
        CacheConstants.setWorkerCachePolicy(true, false, true);
        expect(CacheConstants.isEnableLocalCache()).assertTrue();
        expect(CacheConstants.getOnlyCache()).assertFalse();
        expect(CacheConstants.getForceRefresh()).assertTrue();
      });

      it('worker override takes precedence over setOnlyCache', 0, () => {
        CacheConstants.setWorkerCachePolicy(true, false, false);
        CacheConstants.setOnlyCache(true); // 写 AppStorage
        // worker 快照为 false，应覆盖 AppStorage
        expect(CacheConstants.getOnlyCache()).assertFalse();
      });

      it('worker override takes precedence over setForceRefresh', 0, () => {
        CacheConstants.setWorkerCachePolicy(true, false, false);
        CacheConstants.setForceRefresh(true); // 写 AppStorage
        expect(CacheConstants.getForceRefresh()).assertFalse();
      });
    });
  });
}
