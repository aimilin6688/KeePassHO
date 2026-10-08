import { describe, expect, it } from '@ohos/hypium';
import { ProgressMessage } from '../../../../main/ets/workers/WorkerParam';
import { DatabaseSave } from '../../../../main/ets/workers/DatabaseSave';
import { DatabaseLoad } from '../../../../main/ets/workers/DatabaseLoad';
import { SaveDatabaseCallback } from '../../../../main/ets/workers/callback/SaveDatabaseCallback';

/**
 * 进度回调捕获器（实现 SaveDatabaseCallback，仅记录 onProgress）
 */
class ProgressCapture implements SaveDatabaseCallback {
  public progressCount: number = 0;
  public lastProgressMessage: ProgressMessage | null = null;

  onProgress(message: ProgressMessage): void {
    this.progressCount++;
    this.lastProgressMessage = message;
  }
}

/**
 * 进度消息基类分发单元测试（主线程直开模式）
 *
 * 覆盖：
 * - DatabaseSave.postProgressMessage：分发到 callback.onProgress / 无回调不抛
 * - DatabaseLoad.postProgressMessage：分发到传入的 handler / 未传 handler 不抛
 */
export default function ProgressDispatchTest() {
  describe('ProgressDispatchTest', () => {
    it('DatabaseSave postProgressMessage dispatches to callback onProgress', 0, () => {
      const capture = new ProgressCapture();
      const saver = new DatabaseSave(capture);

      saver.postProgressMessage(new ProgressMessage(20, 200, 1000));

      expect(capture.progressCount).assertEqual(1);
      expect(capture.lastProgressMessage !== null).assertTrue();
      expect(capture.lastProgressMessage!.percent).assertEqual(20);
      expect(capture.lastProgressMessage!.transferredBytes).assertEqual(200);
      expect(capture.lastProgressMessage!.totalBytes).assertEqual(1000);
    });

    it('DatabaseSave postProgressMessage without callback does not throw', 0, () => {
      const saver = new DatabaseSave();
      let threw = false;
      try {
        saver.postProgressMessage(new ProgressMessage(20, 200, 1000));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('DatabaseLoad postProgressMessage dispatches to provided handler', 0, () => {
      const loader = new DatabaseLoad();
      const capture = new ProgressCapture();

      loader.postProgressMessage(new ProgressMessage(45, 450, 1000), (message: ProgressMessage): void => {
        capture.onProgress(message);
      });

      expect(capture.progressCount).assertEqual(1);
      expect(capture.lastProgressMessage !== null).assertTrue();
      expect(capture.lastProgressMessage!.percent).assertEqual(45);
    });

    it('DatabaseLoad postProgressMessage without handler does not throw', 0, () => {
      const loader = new DatabaseLoad();
      let threw = false;
      try {
        loader.postProgressMessage(new ProgressMessage(45, 450, 1000));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });
  });
}
