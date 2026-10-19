import { describe, expect, it } from '@ohos/hypium';
import { distributedKVStore } from '@kit.ArkData';
import { BusinessError, emitter } from '@kit.BasicServicesKit';
import { DistributedKVService } from '../../../../main/ets/services/store/DistributedKVService';
import { EventBus } from '../../../../main/ets/services/EventBus';
import { TestContextHelper } from '../TestContextHelper';

function sleep(ms: number): Promise<void> {
  return new Promise<void>(resolve => setTimeout(resolve, ms));
}

/**
 * 轮询等待条件成立（emitter 投递为异步）。
 */
async function waitFor(cond: () => boolean, timeoutMs: number = 2000): Promise<boolean> {
  const deadline: number = Date.now() + timeoutMs;
  while (!cond() && Date.now() < deadline) {
    await sleep(20);
  }
  return cond();
}

/**
 * DistributedKVService 单元测试。
 *
 * 覆盖：SDK 枚举值锚定、未初始化契约（put/get/delete 拒绝、sync/设备列表安全降级）、
 * 真实 KVStore 契约（init、string/number/boolean 往返、缺失键 15100004、删除、
 * 再写入、sync、onDataChange → EventBus.KV_DATA_CHANGE、close 与再初始化）。
 *
 * 顺序约定：Uninitialized describe 必须先于 Contract describe 注册执行
 * （测试进程运行 TestAbility，无应用代码调用 init，进程启动时 KVStore 天然未初始化）；
 * Contract describe 结束时保持初始化状态，供后续 SyncSettingsServiceTest 复用。
 */
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

  describe('DistributedKVServiceUninitialized', () => {
    it('isInitialized is false before init', 0, () => {
      expect(DistributedKVService.isInitialized()).assertFalse();
    });

    it('put rejects with not-initialized error before init', 0, async () => {
      let rejected = false;
      let message = '';
      try {
        await DistributedKVService.put('uninit_key', 'value');
      } catch (err) {
        rejected = true;
        const e = err as Error;
        message = e.message;
      }
      expect(rejected).assertTrue();
      expect(message).assertEqual('KVStore is not initialized');
    });

    it('get rejects with not-initialized error before init', 0, async () => {
      let rejected = false;
      let message = '';
      try {
        await DistributedKVService.get('uninit_key');
      } catch (err) {
        rejected = true;
        const e = err as Error;
        message = e.message;
      }
      expect(rejected).assertTrue();
      expect(message).assertEqual('KVStore is not initialized');
    });

    it('delete rejects with not-initialized error before init', 0, async () => {
      let rejected = false;
      let message = '';
      try {
        await DistributedKVService.delete('uninit_key');
      } catch (err) {
        rejected = true;
        const e = err as Error;
        message = e.message;
      }
      expect(rejected).assertTrue();
      expect(message).assertEqual('KVStore is not initialized');
    });

    it('getConnectedDeviceIds returns empty array before init', 0, () => {
      const ids = DistributedKVService.getConnectedDeviceIds();
      expect(Array.isArray(ids)).assertTrue();
      expect(ids.length).assertEqual(0);
    });

    it('sync is a safe no-op before init (all modes)', 0, () => {
      let threw = false;
      try {
        DistributedKVService.sync();
        DistributedKVService.sync(distributedKVStore.SyncMode.PUSH_ONLY);
        DistributedKVService.sync(distributedKVStore.SyncMode.PULL_ONLY);
        DistributedKVService.sync(distributedKVStore.SyncMode.PUSH_PULL);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });
  });

  describe('DistributedKVServiceContract', () => {
    it('init resolves and marks the store initialized', 0, async () => {
      const context = await TestContextHelper.getUIAbilityContext();
      await DistributedKVService.init(context);
      expect(DistributedKVService.isInitialized()).assertTrue();
    });

    it('put/get round-trips a string value', 0, async () => {
      await DistributedKVService.put('test_str_key', 'hello-distributed');
      const value = await DistributedKVService.get('test_str_key');
      expect(value).assertEqual('hello-distributed');
    });

    it('put/get round-trips a number value', 0, async () => {
      await DistributedKVService.put('test_num_key', 42);
      const value = await DistributedKVService.get('test_num_key');
      expect(value).assertEqual(42);
    });

    it('put/get round-trips a boolean value', 0, async () => {
      await DistributedKVService.put('test_bool_key', true);
      const value = await DistributedKVService.get('test_bool_key');
      expect(value).assertTrue();
    });

    it('get of a missing key rejects with code 15100004', 0, async () => {
      const missingKey = `missing_${Date.now()}`;
      let code = -1;
      try {
        await DistributedKVService.get(missingKey);
      } catch (err) {
        const e = err as BusinessError;
        code = e.code;
      }
      expect(code).assertEqual(15100004);
    });

    it('delete removes the value and subsequent get rejects with 15100004', 0, async () => {
      const key = `del_${Date.now()}`;
      await DistributedKVService.put(key, 'to-delete');
      await DistributedKVService.delete(key);
      let code = -1;
      try {
        await DistributedKVService.get(key);
      } catch (err) {
        const e = err as BusinessError;
        code = e.code;
      }
      expect(code).assertEqual(15100004);
    });

    it('put works again after delete', 0, async () => {
      const key = `rewrite_${Date.now()}`;
      await DistributedKVService.put(key, 'first');
      await DistributedKVService.delete(key);
      await DistributedKVService.put(key, 'second');
      const value = await DistributedKVService.get(key);
      expect(value).assertEqual('second');
      await DistributedKVService.delete(key);
    });

    it('getConnectedDeviceIds returns an array after init', 0, () => {
      const ids = DistributedKVService.getConnectedDeviceIds();
      expect(Array.isArray(ids)).assertTrue();
    });

    it('sync does not throw after init', 0, () => {
      let threw = false;
      try {
        DistributedKVService.sync(distributedKVStore.SyncMode.PUSH_PULL);
        DistributedKVService.sync(distributedKVStore.SyncMode.PUSH_ONLY);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onDataChange emits KV_DATA_CHANGE through EventBus with the notification payload', 0, async () => {
      let received = false;
      let receivedJson = '';
      const cb: Callback<emitter.EventData> = (data: emitter.EventData) => {
        const raw: Object | undefined = data?.data;
        if (raw !== undefined) {
          received = true;
          receivedJson = JSON.stringify(raw);
        }
      };
      EventBus.on(EventBus.KV_DATA_CHANGE, cb);
      const value: distributedKVStore.Value = {
        type: distributedKVStore.ValueType.STRING,
        value: 'tv'
      };
      const entry: distributedKVStore.Entry = { key: 'tk', value: value };
      const notification: distributedKVStore.ChangeNotification = {
        insertEntries: [entry],
        updateEntries: [],
        deleteEntries: [],
        deviceId: 'test-device'
      };
      DistributedKVService.onDataChange(notification);
      await waitFor(() => received);
      EventBus.off(EventBus.KV_DATA_CHANGE, cb);
      expect(received).assertTrue();
      expect(receivedJson).assertEqual(JSON.stringify(notification));
    });

    it('close does not throw and the store can be re-initialized afterwards', 0, async () => {
      const context = await TestContextHelper.getUIAbilityContext();
      let threw = false;
      try {
        DistributedKVService.close();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      // 恢复初始化状态：后续套件（SyncSettingsServiceTest）依赖 KVStore 可用
      await DistributedKVService.init(context);
      expect(DistributedKVService.isInitialized()).assertTrue();
    });
  });
}
