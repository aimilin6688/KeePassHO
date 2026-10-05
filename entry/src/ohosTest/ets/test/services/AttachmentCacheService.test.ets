import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { ByteUtils, CryptoEngine } from 'kdbxweb';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { AttachmentCacheService } from '../../../../main/ets/services/kdbx/AttachmentCacheService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { Constants } from '../../../../main/ets/common/constants/Constants';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

/**
 * S4 附件磁盘缓存服务单元测试（真实 Asset Kit + 真实沙箱目录，无 mock）。
 *
 * 覆盖：
 * - 主线程 Asset Kit 密钥生成幂等（32 字节）
 * - Worker 线程注入密钥 + 注入路径后 store 可用（put/get 往返）
 * - 无 Context 且无注入密钥时优雅降级为 undefined（纯内存模式）
 * - 失败闩锁与 reset 恢复
 * - 主线程 store 实例缓存
 */
export default function AttachmentCacheServiceTest() {
  describe('AttachmentCacheService', () => {
    let appContext: common.Context;
    let mainThreadKey: string = '';

    beforeAll(() => {
      appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
    });

    afterAll(() => {
      // 恢复主线程环境，避免污染后续套件（Worker 双模式测试等依赖 Context）
      KdbxModeTestHelper.initContext();
      CommonUtils.setWorkerPaths('', '');
      AttachmentCacheService.setWorkerKey('');
      AttachmentCacheService.reset();
    });

    it('degradesToUndefinedWithoutContextAndKey', 0, () => {
      CommonUtils.clearContextForTest();
      CommonUtils.setWorkerPaths('', '');
      AttachmentCacheService.setWorkerKey('');
      AttachmentCacheService.reset();
      expect(AttachmentCacheService.getStore()).assertUndefined();
      expect(AttachmentCacheService.getAttachmentsDiskThreshold()).assertUndefined();
    });

    it('generatesStable32ByteAssetKeyOnMainThread', 0, () => {
      KdbxModeTestHelper.initContext();
      const key1 = AttachmentCacheService.getWorkerKeyBase64();
      const key2 = AttachmentCacheService.getWorkerKeyBase64();
      expect(key1.length > 0).assertTrue();
      expect(key1).assertEqual(key2);
      expect(ByteUtils.base64ToBytes(key1).length).assertEqual(32);
      mainThreadKey = key1;
    });

    it('workerInjectedKeyBuildsWorkingStoreWithoutContext', 0, async () => {
      const filesDir = appContext.filesDir;
      const cacheDir = appContext.cacheDir;
      expect(mainThreadKey.length > 0).assertTrue();
      AttachmentCacheService.setWorkerKey(mainThreadKey);
      CommonUtils.clearContextForTest();
      CommonUtils.setWorkerPaths(filesDir, cacheDir);
      AttachmentCacheService.reset();
      const store = AttachmentCacheService.getStore();
      expect(store !== undefined).assertTrue();
      expect(AttachmentCacheService.getAttachmentsDiskThreshold())
        .assertEqual(Constants.ATTACH_DISK_THRESHOLD_BYTES);
      if (store !== undefined) {
        const data = ByteUtils.stringToBuffer('worker-mode-store-verification');
        const digest = await CryptoEngine.sha256(data);
        const hash = ByteUtils.bytesToHex(new Uint8Array(digest));
        await store.put(hash, data);
        const read = await store.get(hash);
        expect(ByteUtils.arrayBufferEquals(read, data)).assertTrue();
      }
    });

    it('resetRestoresStoreAfterFailureLatch', 0, () => {
      CommonUtils.clearContextForTest();
      AttachmentCacheService.setWorkerKey('');
      AttachmentCacheService.reset();
      expect(AttachmentCacheService.getStore()).assertUndefined();
      expect(mainThreadKey.length > 0).assertTrue();
      AttachmentCacheService.setWorkerKey(mainThreadKey);
      AttachmentCacheService.reset();
      expect(AttachmentCacheService.getStore() !== undefined).assertTrue();
    });

    it('mainThreadStoreIsCachedInstance', 0, () => {
      KdbxModeTestHelper.initContext();
      AttachmentCacheService.reset();
      const store1 = AttachmentCacheService.getStore();
      const store2 = AttachmentCacheService.getStore();
      expect(store1 !== undefined).assertTrue();
      expect(store1 === store2).assertTrue();
    });
  });
}
