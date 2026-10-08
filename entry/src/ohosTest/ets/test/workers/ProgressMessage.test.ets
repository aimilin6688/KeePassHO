import { describe, expect, it } from '@ohos/hypium';
import { MessageType, ProgressMessage } from '../../../../main/ets/workers/WorkerParam';

/**
 * ProgressMessage 进度消息单元测试
 *
 * 覆盖：
 * - MessageType.PROGRESS 常量值
 * - 构造器字段赋值 + type 固定为 MessageType.PROGRESS
 * - 边界值（0 / 100）
 */
export default function ProgressMessageTest() {
  describe('ProgressMessageTest', () => {
    it('MessageType.PROGRESS equals PROGRESS', 0, () => {
      expect(MessageType.PROGRESS).assertEqual('PROGRESS');
    });

    it('constructor assigns percent and byte fields', 0, () => {
      const message = new ProgressMessage(42, 4200, 10000);
      expect(message.type).assertEqual(MessageType.PROGRESS);
      expect(message.percent).assertEqual(42);
      expect(message.transferredBytes).assertEqual(4200);
      expect(message.totalBytes).assertEqual(10000);
    });

    it('constructor supports boundary values', 0, () => {
      const zero = new ProgressMessage(0, 0, 0);
      expect(zero.type).assertEqual(MessageType.PROGRESS);
      expect(zero.percent).assertEqual(0);
      expect(zero.transferredBytes).assertEqual(0);
      expect(zero.totalBytes).assertEqual(0);

      const full = new ProgressMessage(100, 999, 999);
      expect(full.percent).assertEqual(100);
      expect(full.transferredBytes).assertEqual(999);
      expect(full.totalBytes).assertEqual(999);
    });
  });
}
