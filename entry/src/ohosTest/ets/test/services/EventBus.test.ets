import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { emitter } from '@kit.BasicServicesKit';
import { EventBus } from '../../../../main/ets/services/EventBus';

function sleep(ms: number): Promise<void> {
  return new Promise<void>(resolve => setTimeout(resolve, ms));
}

/**
 * 轮询等待条件成立（上限 timeoutMs）。
 * emitter 投递为异步，固定 sleep 在全量运行高负载下可能早于投递完成，
 * 导致正向断言随机失败（曾现：50ms sleep 后 payload 仍为 null）。
 */
async function waitFor(cond: () => boolean, timeoutMs: number = 2000): Promise<boolean> {
  const deadline: number = Date.now() + timeoutMs;
  while (!cond() && Date.now() < deadline) {
    await sleep(20);
  }
  return cond();
}

export default function EventBusTest() {
  describe('EventBus', () => {
    const EVENT_A = 'test_event_bus_a';
    const EVENT_B = 'test_event_bus_b';
    const EVENT_C = 'test_event_bus_c';

    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
      EventBus.off(EVENT_A);
      EventBus.off(EVENT_B);
      EventBus.off(EVENT_C);
    });

    afterAll(() => {
    });

    it('exposes database event name constants', 0, () => {
      expect(EventBus.DATABASE_RELOAD).assertEqual('database_reload');
      expect(EventBus.DATABASE_UPDATE).assertEqual('database_update');
      expect(EventBus.KV_DATA_CHANGE).assertEqual('kv_data_change');
      expect(EventBus.KV_SYNC_COMPLETE).assertEqual('kv_sync_complete');
    });

    it('emit without subscribers does not throw', 0, () => {
      let threw = false;
      try {
        EventBus.emit<string>(EVENT_A, 'payload');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('on + emit fires the callback with payload data', 0, async () => {
      let received: string | null = null;
      const cb: Callback<emitter.EventData> = (data: emitter.EventData) => {
        const raw: Object | undefined = data?.data;
        if (typeof raw === 'string') {
          received = raw;
        }
      };
      EventBus.on(EVENT_A, cb);
      EventBus.emit<string>(EVENT_A, 'hello');
      await waitFor(() => received !== null);
      expect(received).assertEqual('hello');
    });

    it('emit with undefined data still invokes callback', 0, async () => {
      let invoked = false;
      const cb: Callback<emitter.EventData> = () => {
        invoked = true;
      };
      EventBus.on(EVENT_B, cb);
      EventBus.emit<string>(EVENT_B);
      await waitFor(() => invoked);
      expect(invoked).assertTrue();
    });

    it('multiple subscribers on same event both fire', 0, async () => {
      let count = 0;
      const cb1: Callback<emitter.EventData> = () => {
        count++;
      };
      const cb2: Callback<emitter.EventData> = () => {
        count++;
      };
      EventBus.on(EVENT_C, cb1);
      EventBus.on(EVENT_C, cb2);
      EventBus.emit<string>(EVENT_C);
      await waitFor(() => count === 2);
      expect(count).assertEqual(2);
    });

    it('off with specific callback stops only that callback', 0, async () => {
      let alive = 0;
      let dead = 0;
      const keep: Callback<emitter.EventData> = () => {
        alive++;
      };
      const gone: Callback<emitter.EventData> = () => {
        dead++;
      };
      EventBus.on(EVENT_A, keep);
      EventBus.on(EVENT_A, gone);
      EventBus.off(EVENT_A, gone);
      EventBus.emit<string>(EVENT_A);
      await waitFor(() => alive === 1);
      expect(alive).assertEqual(1);
      expect(dead).assertEqual(0);
    });

    it('off without callback stops all subscribers for that event', 0, async () => {
      let count = 0;
      const cb1: Callback<emitter.EventData> = () => {
        count++;
      };
      const cb2: Callback<emitter.EventData> = () => {
        count++;
      };
      EventBus.on(EVENT_A, cb1);
      EventBus.on(EVENT_A, cb2);
      EventBus.off(EVENT_A);
      EventBus.emit<string>(EVENT_A);
      await sleep(50);
      expect(count).assertEqual(0);
    });

    it('off for an event with no subscribers does not throw', 0, () => {
      let threw = false;
      try {
        EventBus.off(EVENT_B);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });
  });
}
