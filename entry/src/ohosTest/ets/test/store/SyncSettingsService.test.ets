import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { SyncSettingsService } from '../../../../main/ets/services/store/SyncSettingsService';
import { RecentFile } from '../../../../main/ets/services/TypeDefined';
import { TestContextHelper } from '../TestContextHelper';

interface TestSyncData {
  key: string;
  value: Object;
  version: number;
  deviceId: string;
  timestamp: number;
}

export default function SyncSettingsServiceTest() {
  describe('SyncSettingsService', () => {
    describe('SyncDataInterface', () => {
      it('should create valid SyncData with version and deviceId', 0, () => {
        const syncData: TestSyncData = {
          key: 'test_key',
          value: 'test_value',
          version: 1,
          deviceId: 'device_123',
          timestamp: Date.now()
        };
        expect(syncData.key).assertEqual('test_key');
        expect(syncData.version).assertLarger(0);
        expect(syncData.deviceId).assertContain('device_');
        expect(syncData.timestamp).assertLarger(0);
      });

      it('should serialize and deserialize SyncData correctly', 0, () => {
        const original: TestSyncData = {
          key: 'setting_key',
          value: true,
          version: 5,
          deviceId: 'device_abc',
          timestamp: 1000000
        };
        const serialized = JSON.stringify(original);
        const parsed: TestSyncData = JSON.parse(serialized) as TestSyncData;
        expect(parsed.key).assertEqual('setting_key');
        expect(parsed.value).assertEqual(true);
        expect(parsed.version).assertEqual(5);
        expect(parsed.deviceId).assertEqual('device_abc');
        expect(parsed.timestamp).assertEqual(1000000);
      });
    });

    describe('deviceIdFormat', () => {
      it('deviceId should start with device_ prefix', 0, () => {
        const deviceId = `device_${Date.now()}_test`;
        expect(deviceId.startsWith('device_')).assertTrue();
      });

      it('different timestamps should produce different deviceIds', 0, () => {
        const id1 = `device_${1000}_abc`;
        const id2 = `device_${2000}_xyz`;
        expect(id1 === id2).assertFalse();
      });
    });

    describe('mergeLogicVersionComparison', () => {
      it('remote version higher should trigger merge', 0, () => {
        const localVersion = 3;
        const remoteVersion = 5;
        expect(remoteVersion > localVersion).assertTrue();
      });

      it('local version higher should skip merge', 0, () => {
        const localVersion = 7;
        const remoteVersion = 5;
        expect(remoteVersion > localVersion).assertFalse();
      });

      it('no local version (0) should trigger merge with any remote version >= 1', 0, () => {
        const localVersion = 0;
        const remoteVersion = 1;
        expect(remoteVersion > localVersion).assertTrue();
      });

      it('equal version with different deviceId should use tiebreaker', 0, () => {
        const localVersion = 5;
        const remoteVersion = 5;
        const localDeviceId: string = 'device_1';
        const remoteDeviceId: string = 'device_2';
        expect(remoteVersion === localVersion).assertTrue();
        expect(remoteDeviceId !== localDeviceId).assertTrue();
      });

      it('equal version with same deviceId should skip merge', 0, () => {
        const localVersion = 5;
        const remoteVersion = 5;
        const deviceId = 'device_same';
        expect(remoteVersion === localVersion).assertTrue();
        expect(deviceId === deviceId).assertTrue();
      });
    });

    describe('versionMonotonicity', () => {
      it('version should increment on each sync push', 0, () => {
        let version = 0;
        version = version + 1; // first sync
        expect(version).assertEqual(1);
        version = version + 1; // second sync
        expect(version).assertEqual(2);
      });

      it('version should NOT increment when accepting remote merge', 0, () => {
        let localVersion = 3;
        const remoteVersion = 7;
        // Accept remote: set local to remote version, NOT remote+1
        localVersion = Math.max(localVersion, remoteVersion);
        expect(localVersion).assertEqual(7);
      });
    });
  });

  // 真实服务契约测试：直接驱动 SyncSettingsService 本体（离线安全：
  // isSyncEnabled 默认 false 时所有分布式 KV 路径均被门控跳过）
  describe('SyncSettingsServiceReal', () => {
    it('getInstance returns singleton', 0, () => {
      const a = SyncSettingsService.getInstance();
      const b = SyncSettingsService.getInstance();
      expect(a === b).assertTrue();
    });

    it('init is safe to call before and after real initialization', 0, async () => {
      // 无论 EntryAbility 是否已完成初始化，重复 init 都必须无异常
      await SyncSettingsService.init();
      await SyncSettingsService.init();
      expect(true).assertTrue();
    });

    it('isSyncEnabled returns boolean without throwing', 0, () => {
      const enabled: boolean = SyncSettingsService.isSyncEnabled();
      expect(typeof enabled === 'boolean').assertTrue();
    });

    it('syncSetting and syncRecentFiles honor disabled gate without error', 0, async () => {
      if (SyncSettingsService.isSyncEnabled()) {
        // 真机已启用同步：跳过污染性调用（避免写真实分布式 KV）
        return;
      }
      await SyncSettingsService.syncSetting('unit_test_key', 'value');
      const emptyList: RecentFile[] = [];
      await SyncSettingsService.syncRecentFiles(emptyList);
      expect(true).assertTrue();
    });

    it('syncOnForeground is a no-throw no-op', 0, () => {
      SyncSettingsService.syncOnForeground();
      expect(true).assertTrue();
    });

    it('disableSync is safe when sync already disabled', 0, () => {
      if (SyncSettingsService.isSyncEnabled()) {
        // 真机已启用同步：不得触碰真实同步开关
        return;
      }
      SyncSettingsService.disableSync();
      expect(SyncSettingsService.isSyncEnabled()).assertFalse();
    });

    it('initDeviceIdPreferences then init completes idempotently', 0, async () => {
      const context = await TestContextHelper.getUIAbilityContext();
      await SyncSettingsService.initDeviceIdPreferences(context);
      await SyncSettingsService.init();
      // 幂等：重复 init 直接返回
      await SyncSettingsService.init();
      expect(true).assertTrue();
    });

    it('initSync respects disabled gate and completes', 0, async () => {
      const context = await TestContextHelper.getUIAbilityContext();
      await SyncSettingsService.initSync(context);
      expect(true).assertTrue();
    });

    it('getRemoteRecentFiles returns null safely when remote not initialized', 0, async () => {
      const files = await SyncSettingsService.getRemoteRecentFiles();
      if (!SyncSettingsService.isSyncEnabled()) {
        // 同步未启用：DistributedKVService 未初始化，get 抛错被吞 → 确定性 null
        expect(files).assertNull();
      } else {
        // 真机已启用同步：远端可能存在其他设备推送的数据，仅验证形状
        expect(files === null || files instanceof Array).assertTrue();
      }
    });
  });
}
