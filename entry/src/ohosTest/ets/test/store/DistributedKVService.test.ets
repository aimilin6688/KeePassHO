import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { distributedKVStore } from '@kit.ArkData';

export default function DistributedKVServiceTest() {
  describe('DistributedKVService', () => {
    it('SyncMode PUSH_ONLY should equal 1', 0, () => {
      expect(distributedKVStore.SyncMode.PUSH_ONLY).assertEqual(1);
    });

    it('SyncMode PULL_ONLY should equal 0', 0, () => {
      expect(distributedKVStore.SyncMode.PULL_ONLY).assertEqual(0);
    });

    it('SyncMode PUSH_PULL should equal 2', 0, () => {
      expect(distributedKVStore.SyncMode.PUSH_PULL).assertEqual(2);
    });

    it('SecurityLevel S1 should be available', 0, () => {
      expect(distributedKVStore.SecurityLevel.S1).assertEqual(2);
    });

    it('SubscribeType SUBSCRIBE_TYPE_REMOTE should equal 1', 0, () => {
      expect(distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_REMOTE).assertEqual(1);
    });

    it('SubscribeType SUBSCRIBE_TYPE_ALL should equal 2', 0, () => {
      expect(distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_ALL).assertEqual(2);
    });
  });
}
