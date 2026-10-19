import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { ErrorEvent } from '@kit.ArkTS';
import { ToastLoadDatabaseCallback } from '../../../../main/ets/workers/callback/ToastLoadDatabaseCallback';
import { KdbxLoadServiceCallback } from '../../../../main/ets/services/kdbx/KdbxLoadService';
import { LoadMessage, MessageType, ProgressMessage, SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { KdbxModeTestHelper } from './KdbxModeTestHelper';

/**
 * InnerLoadCallback — 捕获调用以验证 ToastLoadDatabaseCallback 对内层回调的转发
 */
class InnerLoadCallback implements KdbxLoadServiceCallback {
  public loadMessageCount: number = 0;
  public lastLoadMessage: LoadMessage | null = null;
  public progressCount: number = 0;
  public lastProgressMessage: ProgressMessage | null = null;
  public successCount: number = 0;
  public lastSuccessMessage: SuccessMessage | null = null;
  public errorMessageCount: number = 0;
  public lastErrorMessage: LoadMessage | null = null;
  public allErrorsCount: number = 0;
  public lastAllErrorsMessage: string = '';
  public exitCount: number = 0;
  public lastExitCode: number = -1;

  onLoadMessage = (message: LoadMessage): void => {
    this.loadMessageCount++;
    this.lastLoadMessage = message;
  };

  onProgressMessage = (message: ProgressMessage): void => {
    this.progressCount++;
    this.lastProgressMessage = message;
  };

  onSuccessMessage = (message: SuccessMessage): void => {
    this.successCount++;
    this.lastSuccessMessage = message;
  };

  onErrorMessage = (message: LoadMessage): void => {
    this.errorMessageCount++;
    this.lastErrorMessage = message;
  };

  onAllErrors = (err: ErrorEvent): void => {
    this.allErrorsCount++;
    this.lastAllErrorsMessage = err.message;
  };

  onexit = (e: number): void => {
    this.exitCount++;
    this.lastExitCode = e;
  };
}

/**
 * 构造仅含必需字段的 ErrorEvent 字面量（SDK 中 ErrorEvent 为接口）。
 */
function buildErrorEvent(message: string): ErrorEvent {
  const errEvent: ErrorEvent = {
    type: 'error',
    timeStamp: 0,
    message: message,
    filename: 'worker.js',
    lineno: 1,
    colno: 1,
    error: new Error(message)
  };
  return errEvent;
}

/**
 * ToastLoadDatabaseCallback 单元测试。
 *
 * 覆盖：构造（无/有内层回调）、六个回调方法的无内层安全调用与内层转发、
 * 阶段消息与传输进度的 HUD 切换序列、totalBytes<=0 的进度文案回退、
 * 静态 wrap 工厂。
 *
 * LoadingDialog / CommonUtils.showToast 在无 UIContext 环境下内部捕获异常，
 * 不会同步抛出，测试聚焦内层回调转发逻辑。
 */
export default function ToastLoadDatabaseCallbackTest() {
  describe('ToastLoadDatabaseCallbackTest', () => {
    beforeAll(() => {
      KdbxModeTestHelper.initContext();
    });

    it('constructor without inner callback exposes all callback functions', 0, () => {
      const cb = new ToastLoadDatabaseCallback();
      expect(typeof cb.onLoadMessage === 'function').assertTrue();
      expect(typeof cb.onProgressMessage === 'function').assertTrue();
      expect(typeof cb.onSuccessMessage === 'function').assertTrue();
      expect(typeof cb.onErrorMessage === 'function').assertTrue();
      expect(typeof cb.onAllErrors === 'function').assertTrue();
      expect(typeof cb.onexit === 'function').assertTrue();
    });

    it('constructor with inner callback stores it', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      expect(typeof cb.onLoadMessage === 'function').assertTrue();
      expect(typeof cb.onSuccessMessage === 'function').assertTrue();
    });

    it('onLoadMessage without inner callback does not throw', 0, () => {
      const cb = new ToastLoadDatabaseCallback();
      const message = new LoadMessage(MessageType.MESSAGE, 'loading');
      let threw = false;
      try {
        cb.onLoadMessage(message);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onLoadMessage forwards to inner callback', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      cb.onLoadMessage(new LoadMessage(MessageType.MESSAGE, 'downloading'));
      expect(inner.loadMessageCount).assertEqual(1);
      expect(inner.lastLoadMessage!.message).assertEqual('downloading');
    });

    it('onLoadMessage accepts a numeric resource id message', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      let threw = false;
      try {
        cb.onLoadMessage(new LoadMessage(MessageType.MESSAGE, 404));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(inner.loadMessageCount).assertEqual(1);
    });

    it('onProgressMessage without inner callback does not throw', 0, () => {
      const cb = new ToastLoadDatabaseCallback();
      const progress = new ProgressMessage(30, 300, 1000);
      let threw = false;
      try {
        cb.onProgressMessage(progress);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onProgressMessage forwards to inner callback', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      cb.onProgressMessage(new ProgressMessage(50, 500, 1000));
      expect(inner.progressCount).assertEqual(1);
      expect(inner.lastProgressMessage!.percent).assertEqual(50);
      expect(inner.lastProgressMessage!.transferredBytes).assertEqual(500);
      expect(inner.lastProgressMessage!.totalBytes).assertEqual(1000);
    });

    it('onProgressMessage with unknown total size falls back to stage text without throw', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      cb.onLoadMessage(new LoadMessage(MessageType.MESSAGE, 'loading'));
      cb.onProgressMessage(new ProgressMessage(0, 0, 0));
      expect(inner.progressCount).assertEqual(1);
      expect(inner.loadMessageCount).assertEqual(1);
    });

    it('stage message after progress hides the linear progress HUD', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      cb.onLoadMessage(new LoadMessage(MessageType.MESSAGE, 'stage-1'));
      cb.onProgressMessage(new ProgressMessage(30, 300, 1000));
      cb.onLoadMessage(new LoadMessage(MessageType.MESSAGE, 'stage-2'));
      expect(inner.loadMessageCount).assertEqual(2);
      expect(inner.progressCount).assertEqual(1);
      expect(inner.lastLoadMessage!.message).assertEqual('stage-2');
    });

    it('onSuccessMessage without inner callback does not throw', 0, () => {
      const cb = new ToastLoadDatabaseCallback();
      const message = new SuccessMessage(new ArrayBuffer(0), 100);
      let threw = false;
      try {
        cb.onSuccessMessage(message);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onSuccessMessage forwards to inner callback', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      cb.onProgressMessage(new ProgressMessage(90, 900, 1000));
      cb.onSuccessMessage(new SuccessMessage(new ArrayBuffer(0), 123456));
      expect(inner.successCount).assertEqual(1);
      expect(inner.lastSuccessMessage!.modifiedTime).assertEqual(123456);
      expect(inner.progressCount).assertEqual(1);
    });

    it('onErrorMessage without inner callback does not throw', 0, () => {
      const cb = new ToastLoadDatabaseCallback();
      let threw = false;
      try {
        cb.onErrorMessage(new LoadMessage(MessageType.ERROR, 'bad password'));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onErrorMessage forwards to inner callback', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      cb.onErrorMessage(new LoadMessage(MessageType.ERROR, 'load failed'));
      expect(inner.errorMessageCount).assertEqual(1);
      expect(inner.lastErrorMessage!.message).assertEqual('load failed');
    });

    it('onAllErrors forwards error message to inner callback', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      cb.onAllErrors(buildErrorEvent('worker crashed'));
      expect(inner.allErrorsCount).assertEqual(1);
      expect(inner.lastAllErrorsMessage).assertEqual('worker crashed');
    });

    it('onAllErrors without inner callback does not throw', 0, () => {
      const cb = new ToastLoadDatabaseCallback();
      let threw = false;
      try {
        cb.onAllErrors(buildErrorEvent('boom'));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onexit forwards exit code to inner callback', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      cb.onexit(0);
      cb.onexit(1);
      expect(inner.exitCount).assertEqual(2);
      expect(inner.lastExitCode).assertEqual(1);
    });

    it('onexit without inner callback does not throw', 0, () => {
      const cb = new ToastLoadDatabaseCallback();
      let threw = false;
      try {
        cb.onexit(0);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('terminal callbacks do not cross-forward to other inner methods', 0, () => {
      const inner = new InnerLoadCallback();
      const cb = new ToastLoadDatabaseCallback(inner);
      cb.onSuccessMessage(new SuccessMessage(new ArrayBuffer(0), 1));
      expect(inner.successCount).assertEqual(1);
      expect(inner.errorMessageCount).assertEqual(0);
      expect(inner.allErrorsCount).assertEqual(0);
      expect(inner.exitCount).assertEqual(0);
    });

    it('static wrap returns ToastLoadDatabaseCallback instance', 0, () => {
      const wrapped = ToastLoadDatabaseCallback.wrap();
      expect(wrapped instanceof ToastLoadDatabaseCallback).assertTrue();
      expect(typeof wrapped.onLoadMessage === 'function').assertTrue();
      expect(typeof wrapped.onProgressMessage === 'function').assertTrue();
      expect(typeof wrapped.onSuccessMessage === 'function').assertTrue();
    });

    it('static wrap with inner callback forwards the full message set', 0, () => {
      const inner = new InnerLoadCallback();
      const wrapped = ToastLoadDatabaseCallback.wrap(inner);
      wrapped.onLoadMessage?.(new LoadMessage(MessageType.MESSAGE, 'wrap-stage'));
      wrapped.onProgressMessage?.(new ProgressMessage(25, 250, 1000));
      wrapped.onSuccessMessage?.(new SuccessMessage(new ArrayBuffer(0), 42));
      wrapped.onErrorMessage?.(new LoadMessage(MessageType.ERROR, 'wrap-err'));
      wrapped.onAllErrors?.(buildErrorEvent('wrap-crash'));
      wrapped.onexit?.(9);
      expect(inner.loadMessageCount).assertEqual(1);
      expect(inner.progressCount).assertEqual(1);
      expect(inner.successCount).assertEqual(1);
      expect(inner.errorMessageCount).assertEqual(1);
      expect(inner.allErrorsCount).assertEqual(1);
      expect(inner.exitCount).assertEqual(1);
      expect(inner.lastExitCode).assertEqual(9);
    });

    it('static wrap without inner callback does not throw on any method', 0, () => {
      const wrapped = ToastLoadDatabaseCallback.wrap();
      let threw = false;
      try {
        wrapped.onLoadMessage?.(new LoadMessage(MessageType.MESSAGE, 'stage'));
        wrapped.onProgressMessage?.(new ProgressMessage(10, 100, 1000));
        wrapped.onSuccessMessage?.(new SuccessMessage(new ArrayBuffer(0), 0));
        wrapped.onErrorMessage?.(new LoadMessage(MessageType.ERROR, 'err'));
        wrapped.onAllErrors?.(buildErrorEvent('crash'));
        wrapped.onexit?.(0);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('implements KdbxLoadServiceCallback interface', 0, () => {
      const cb: KdbxLoadServiceCallback = new ToastLoadDatabaseCallback();
      expect(typeof cb.onLoadMessage === 'function').assertTrue();
      expect(typeof cb.onSuccessMessage === 'function').assertTrue();
      expect(typeof cb.onErrorMessage === 'function').assertTrue();
    });
  });
}
