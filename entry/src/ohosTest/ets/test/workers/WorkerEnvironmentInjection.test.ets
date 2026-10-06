import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { CommonUtils, StorageContextStub } from '../../../../main/ets/common/utils/CommonUtils';
import { CacheConstants } from '../../../../main/ets/storage/cache/CacheConstants';
import { InitWorkerMessage, MessageType } from '../../../../main/ets/workers/WorkerParam';

function initTestContext(): common.Context {
  const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  CommonUtils.init(appContext as common.UIAbilityContext);
  return appContext;
}

export default function WorkerEnvironmentInjectionTest() {
  describe('WorkerEnvironmentInjectionTest', () => {
    let appContext: common.Context;

    beforeAll(() => {
      appContext = initTestContext();
    });

    /**
     * InitWorkerMessage 携带路径、缓存策略与会话密钥/目录
     */
    it('InitWorkerMessage carries paths and cache policy', 0, () => {
      const msg = new InitWorkerMessage('/data/files', '/data/cache', true, false, true, '',
        'c2Vzc2lvbi1rZXk=', '/data/files/session-test');
      expect(msg.type).assertEqual(MessageType.INIT_WORKER);
      expect(msg.filesDir).assertEqual('/data/files');
      expect(msg.cacheDir).assertEqual('/data/cache');
      expect(msg.enableLocalCache).assertTrue();
      expect(msg.onlyUseCache).assertFalse();
      expect(msg.forceRefresh).assertTrue();
      expect(msg.sessionKeyBase64).assertEqual('c2Vzc2lvbi1rZXk=');
      expect(msg.sessionDir).assertEqual('/data/files/session-test');
    });

    /**
     * CommonUtils.getAppFilesDir 主线程返回真实 Context 路径
     */
    it('getAppFilesDir returns real path on main thread', 0, () => {
      const path = CommonUtils.getAppFilesDir();
      expect(path.length).assertLarger(0);
      expect(path.includes('files')).assertTrue();
    });

    /**
     * CommonUtils.getCacheDir 主线程返回真实 Context 路径
     */
    it('getCacheDir returns real path on main thread', 0, () => {
      const path = CommonUtils.getCacheDir();
      expect(path.length).assertLarger(0);
      expect(path.includes('cache')).assertTrue();
    });

    /**
     * setWorkerPaths 注入后 getAppFilesDir/getCacheDir 返回注入值
     * 模拟 Worker 线程：清除主线程 Context
     */
    it('setWorkerPaths overrides getAppFilesDir/getCacheDir', 0, () => {
      CommonUtils.clearContextForTest();
      CommonUtils.setWorkerPaths('/injected/files', '/injected/cache');
      expect(CommonUtils.getAppFilesDir()).assertEqual('/injected/files');
      expect(CommonUtils.getCacheDir()).assertEqual('/injected/cache');
      // 恢复主线程环境
      initTestContext();
    });

    /**
     * getStorageContext 主线程返回真实 Context
     */
    it('getStorageContext returns real context on main thread', 0, () => {
      initTestContext(); // 确保有 context
      const ctx = CommonUtils.getStorageContext();
      expect(ctx instanceof StorageContextStub).assertFalse();
    });

    /**
     * getStorageContext Worker 线程返回 StorageContextStub
     */
    it('getStorageContext returns stub when context is null', 0, () => {
      CommonUtils.clearContextForTest();
      CommonUtils.setWorkerPaths('/injected/files', '/injected/cache');
      const ctx = CommonUtils.getStorageContext();
      expect(ctx instanceof StorageContextStub).assertTrue();
      const stub = ctx as StorageContextStub;
      expect(stub.cacheDir).assertEqual('/injected/cache');
      // 恢复
      initTestContext();
    });

    /**
     * StorageContextStub 仅含 cacheDir 属性
     */
    it('StorageContextStub holds cacheDir string', 0, () => {
      const stub = new StorageContextStub('/stub/cache');
      expect(stub.cacheDir).assertEqual('/stub/cache');
    });

    /**
     * CacheConstants.setWorkerCachePolicy 注入后 isEnableLocalCache 返回注入值
     */
    it('CacheConstants worker cache policy snapshot', 0, () => {
      CacheConstants.setWorkerCachePolicy(false, true, false);
      expect(CacheConstants.isEnableLocalCache()).assertFalse();
      expect(CacheConstants.getOnlyCache()).assertTrue();
      expect(CacheConstants.getForceRefresh()).assertFalse();
      // 恢复
      CacheConstants.setWorkerCachePolicy(true, false, false);
    });

    /**
     * CacheConstants forceRefresh 快照正确返回
     */
    it('CacheConstants worker forceRefresh snapshot returns true', 0, () => {
      CacheConstants.setWorkerCachePolicy(true, false, true);
      expect(CacheConstants.getForceRefresh()).assertTrue();
      // 恢复
      CacheConstants.setWorkerCachePolicy(true, false, false);
    });

    /**
     * CacheConstants 主线程无快照时走 AppStorage（getForceRefresh 返回 false）
     */
    it('CacheConstants main thread uses AppStorage when no snapshot', 0, () => {
      // 确保无 Worker 快照
      CacheConstants.setWorkerCachePolicy(true, false, false);
      // 主线程 AppStorage 默认 false
      expect(CacheConstants.getForceRefresh()).assertFalse();
    });
  });
}
