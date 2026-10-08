import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { ToastSaveDatabaseCallback } from '../../../../main/ets/workers/callback/ToastSaveDatabaseCallback';
import { SaveDatabaseCallback } from '../../../../main/ets/workers/callback/SaveDatabaseCallback';
import { ConflictMessage, ProgressMessage, SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

/**
 * InnerCallback — captures calls for verifying ToastSaveDatabaseCallback delegates to inner callback
 */
class InnerCallback implements SaveDatabaseCallback {
  public successCount: number = 0;
  public errorCount: number = 0;
  public messageCount: number = 0;
  public conflictCount: number = 0;
  public lastSuccessMessage: SuccessMessage | null = null;
  public lastErrorMessage: string = '';
  public lastMessageString: string = '';
  public progressCount: number = 0;
  public lastProgressMessage: ProgressMessage | null = null;

  onSuccess(message: SuccessMessage): void {
    this.successCount++;
    this.lastSuccessMessage = message;
  }

  onError(message: string): void {
    this.errorCount++;
    this.lastErrorMessage = message;
  }

  onMessage(message: string): void {
    this.messageCount++;
    this.lastMessageString = message;
  }

  onConflict(message: ConflictMessage): void {
    this.conflictCount++;
  }

  onProgress(message: ProgressMessage): void {
    this.progressCount++;
    this.lastProgressMessage = message;
  }
}

/**
 * ToastSaveDatabaseCallback 单元测试。
 *
 * 覆盖：
 * - 构造函数：无内层回调 / 有内层回调
 * - onSuccess：隐藏加载弹框 + 显示 Toast + 转发内层回调
 * - onError：隐藏加载弹框 + 显示 Toast + 转发内层回调
 * - onMessage：显示加载弹框 + 转发内层回调
 * - 无内层回调时不抛异常
 * - 静态 wrap 工厂方法
 *
 * LoadingDialog / CommonUtils.showToast 在无 UIContext 环境下内部捕获异常，
 * 不会同步抛出，测试聚焦于内层回调转发逻辑。
 */
export default function ToastSaveDatabaseCallbackTest() {
  describe('ToastSaveDatabaseCallbackTest', () => {
    beforeAll(() => {
      KdbxModeTestHelper.initContext();
    });

    it('constructor without inner callback sets call to undefined', 0, () => {
      const cb = new ToastSaveDatabaseCallback();
      expect(typeof cb.onSuccess === 'function').assertTrue();
      expect(typeof cb.onError === 'function').assertTrue();
      expect(typeof cb.onMessage === 'function').assertTrue();
    });

    it('constructor with inner callback stores it', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);
      expect(typeof cb.onSuccess === 'function').assertTrue();
      expect(typeof cb.onError === 'function').assertTrue();
      expect(typeof cb.onMessage === 'function').assertTrue();
    });

    it('onSuccess without inner callback does not throw', 0, () => {
      const cb = new ToastSaveDatabaseCallback();
      const message = new SuccessMessage(new ArrayBuffer(0), 100, false, 'v1', 'h1');
      let threw = false;
      try {
        cb.onSuccess(message);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onError without inner callback does not throw', 0, () => {
      const cb = new ToastSaveDatabaseCallback();
      let threw = false;
      try {
        cb.onError('test error');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onMessage without inner callback does not throw', 0, () => {
      const cb = new ToastSaveDatabaseCallback();
      let threw = false;
      try {
        cb.onMessage('loading...');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onSuccess forwards to inner callback', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);
      const message = new SuccessMessage(new ArrayBuffer(0), 200, false, 'v2', 'h2');

      cb.onSuccess(message);

      expect(inner.successCount).assertEqual(1);
      expect(inner.lastSuccessMessage !== null).assertTrue();
      expect(inner.lastSuccessMessage!.modifiedTime).assertEqual(200);
      expect(inner.lastSuccessMessage!.version).assertEqual('v2');
    });

    it('onError forwards to inner callback', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);

      cb.onError('save failed');

      expect(inner.errorCount).assertEqual(1);
      expect(inner.lastErrorMessage).assertEqual('save failed');
    });

    it('onMessage forwards to inner callback', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);

      cb.onMessage('saving database');

      expect(inner.messageCount).assertEqual(1);
      expect(inner.lastMessageString).assertEqual('saving database');
    });

    it('onSuccess does not forward to inner onError', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);
      const message = new SuccessMessage(new ArrayBuffer(0), 0, false, null, null);

      cb.onSuccess(message);

      expect(inner.successCount).assertEqual(1);
      expect(inner.errorCount).assertEqual(0);
      expect(inner.messageCount).assertEqual(0);
    });

    it('onError does not forward to inner onSuccess', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);

      cb.onError('error only');

      expect(inner.errorCount).assertEqual(1);
      expect(inner.successCount).assertEqual(0);
    });

    it('multiple onSuccess calls forward each time', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);
      const msg1 = new SuccessMessage(new ArrayBuffer(0), 1, false, null, null);
      const msg2 = new SuccessMessage(new ArrayBuffer(0), 2, false, null, null);

      cb.onSuccess(msg1);
      cb.onSuccess(msg2);

      expect(inner.successCount).assertEqual(2);
      expect(inner.lastSuccessMessage!.modifiedTime).assertEqual(2);
    });

    it('multiple onError calls forward each time', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);

      cb.onError('e1');
      cb.onError('e2');
      cb.onError('e3');

      expect(inner.errorCount).assertEqual(3);
      expect(inner.lastErrorMessage).assertEqual('e3');
    });

    it('static wrap returns ToastSaveDatabaseCallback instance', 0, () => {
      const wrapped = ToastSaveDatabaseCallback.wrap();
      expect(wrapped instanceof ToastSaveDatabaseCallback).assertTrue();
      expect(typeof wrapped.onSuccess === 'function').assertTrue();
      expect(typeof wrapped.onError === 'function').assertTrue();
      expect(typeof wrapped.onMessage === 'function').assertTrue();
    });

    it('static wrap with inner callback forwards calls', 0, () => {
      const inner = new InnerCallback();
      const wrapped = ToastSaveDatabaseCallback.wrap(inner);
      const message = new SuccessMessage(new ArrayBuffer(0), 42, false, 'wrap-v', 'wrap-h');

      wrapped.onSuccess?.(message);
      wrapped.onError?.('wrap-err');
      wrapped.onMessage?.('wrap-msg');

      expect(inner.successCount).assertEqual(1);
      expect(inner.errorCount).assertEqual(1);
      expect(inner.messageCount).assertEqual(1);
      expect(inner.lastSuccessMessage!.modifiedTime).assertEqual(42);
      expect(inner.lastSuccessMessage!.version).assertEqual('wrap-v');
      expect(inner.lastErrorMessage).assertEqual('wrap-err');
      expect(inner.lastMessageString).assertEqual('wrap-msg');
    });

    it('static wrap without inner callback does not throw on any method', 0, () => {
      const wrapped = ToastSaveDatabaseCallback.wrap();
      const message = new SuccessMessage(new ArrayBuffer(0), 0, false, null, null);
      let threw = false;
      try {
        wrapped.onSuccess?.(message);
        wrapped.onError?.('err');
        wrapped.onMessage?.('msg');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onSuccess with isMerge true forwards merge flag', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);
      const message = new SuccessMessage(new ArrayBuffer(0), 0, true, null, null);

      cb.onSuccess(message);

      expect(inner.lastSuccessMessage!.isMerge).assertTrue();
    });

    it('onProgress without inner callback does not throw', 0, () => {
      const cb = new ToastSaveDatabaseCallback();
      const progress = new ProgressMessage(30, 300, 1000);
      let threw = false;
      try {
        cb.onProgress(progress);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onProgress forwards to inner callback', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);
      const progress = new ProgressMessage(50, 500, 1000);

      cb.onProgress(progress);

      expect(inner.progressCount).assertEqual(1);
      expect(inner.lastProgressMessage !== null).assertTrue();
      expect(inner.lastProgressMessage!.percent).assertEqual(50);
      expect(inner.lastProgressMessage!.transferredBytes).assertEqual(500);
      expect(inner.lastProgressMessage!.totalBytes).assertEqual(1000);
    });

    it('multiple onProgress events forward each time', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);

      cb.onProgress(new ProgressMessage(0, 0, 1000));
      cb.onProgress(new ProgressMessage(25, 250, 1000));
      cb.onProgress(new ProgressMessage(100, 1000, 1000));

      expect(inner.progressCount).assertEqual(3);
      expect(inner.lastProgressMessage!.percent).assertEqual(100);
    });

    it('onMessage after onProgress resets stage without throw', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);

      cb.onProgress(new ProgressMessage(10, 100, 1000));
      cb.onMessage('stage change');

      expect(inner.progressCount).assertEqual(1);
      expect(inner.messageCount).assertEqual(1);
      expect(inner.lastMessageString).assertEqual('stage change');
    });

    it('onSuccess after onProgress hides progress HUD without throw', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);

      cb.onProgress(new ProgressMessage(90, 900, 1000));
      cb.onSuccess(new SuccessMessage(new ArrayBuffer(0), 1, false, null, null));

      expect(inner.progressCount).assertEqual(1);
      expect(inner.successCount).assertEqual(1);
    });

    it('onError after onProgress hides progress HUD without throw', 0, () => {
      const inner = new InnerCallback();
      const cb = new ToastSaveDatabaseCallback(inner);

      cb.onProgress(new ProgressMessage(40, 400, 1000));
      cb.onError('upload failed');

      expect(inner.progressCount).assertEqual(1);
      expect(inner.errorCount).assertEqual(1);
    });

    it('static wrap forwards onProgress to inner callback', 0, () => {
      const inner = new InnerCallback();
      const wrapped = ToastSaveDatabaseCallback.wrap(inner);

      wrapped.onProgress?.(new ProgressMessage(75, 750, 1000));

      expect(inner.progressCount).assertEqual(1);
      expect(inner.lastProgressMessage!.percent).assertEqual(75);
    });

    it('implements SaveDatabaseCallback interface', 0, () => {
      const cb: SaveDatabaseCallback = new ToastSaveDatabaseCallback();
      expect(typeof cb.onSuccess === 'function').assertTrue();
      expect(typeof cb.onError === 'function').assertTrue();
      expect(typeof cb.onMessage === 'function').assertTrue();
    });
  });
}
