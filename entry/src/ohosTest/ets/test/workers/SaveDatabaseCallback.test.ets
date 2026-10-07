import { describe, expect, it, beforeAll } from '@ohos/hypium';
import { Kdbx } from 'kdbxweb';
import { SaveDatabaseCallback } from '../../../../main/ets/workers/callback/SaveDatabaseCallback';
import { ToastSaveDatabaseCallback } from '../../../../main/ets/workers/callback/ToastSaveDatabaseCallback';
import { ConflictMessage, SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

/**
 * FullCallback — all four methods implemented
 */
class FullCallback implements SaveDatabaseCallback {
  public successCount: number = 0;
  public errorCount: number = 0;
  public messageCount: number = 0;
  public conflictCount: number = 0;
  public lastSuccessMessage: SuccessMessage | null = null;
  public lastErrorMessage: string = '';
  public lastMessageString: string = '';
  public lastConflictMessage: ConflictMessage | null = null;

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
    this.lastConflictMessage = message;
  }
}

/**
 * PartialCallback — only onSuccess and onError implemented
 */
class PartialCallback implements SaveDatabaseCallback {
  public successCount: number = 0;
  public errorCount: number = 0;

  onSuccess(message: SuccessMessage): void {
    this.successCount++;
  }

  onError(message: string): void {
    this.errorCount++;
  }
}

/**
 * SaveDatabaseCallback 接口契约单元测试。
 *
 * 接口定义四个可选方法：onSuccess / onError / onMessage / onConflict。
 * 覆盖完整实现、部分实现、空实现、对象字面量实现，以及 ToastSaveDatabaseCallback
 * 作为接口实现者的行为一致性。
 */
export default function SaveDatabaseCallbackTest() {
  describe('SaveDatabaseCallbackTest', () => {
    beforeAll(() => {
      KdbxModeTestHelper.initContext();
    });

    it('FullCallback implements all four methods', 0, () => {
      const cb: SaveDatabaseCallback = new FullCallback();
      const success = new SuccessMessage(new ArrayBuffer(0), 100, false, 'v1', 'h1');
      const conflict = new ConflictMessage(200, 'v2');

      cb.onSuccess?.(success);
      cb.onError?.('err');
      cb.onMessage?.('msg');
      cb.onConflict?.(conflict);

      const full = cb as FullCallback;
      expect(full.successCount).assertEqual(1);
      expect(full.errorCount).assertEqual(1);
      expect(full.messageCount).assertEqual(1);
      expect(full.conflictCount).assertEqual(1);
      expect(full.lastSuccessMessage !== null).assertTrue();
      expect(full.lastErrorMessage).assertEqual('err');
      expect(full.lastMessageString).assertEqual('msg');
      expect(full.lastConflictMessage !== null).assertTrue();
    });

    it('FullCallback lastSuccessMessage carries correct fields', 0, () => {
      const cb: SaveDatabaseCallback = new FullCallback();
      const success = new SuccessMessage(new ArrayBuffer(0), 999, true, 'ver', 'hash');
      cb.onSuccess?.(success);

      const full = cb as FullCallback;
      expect(full.lastSuccessMessage !== null).assertTrue();
      expect(full.lastSuccessMessage!.modifiedTime).assertEqual(999);
      expect(full.lastSuccessMessage!.isMerge).assertTrue();
      expect(full.lastSuccessMessage!.version).assertEqual('ver');
      expect(full.lastSuccessMessage!.contentHash).assertEqual('hash');
    });

    it('FullCallback lastConflictMessage carries correct fields', 0, () => {
      const cb: SaveDatabaseCallback = new FullCallback();
      const conflict = new ConflictMessage(1234567, 'remote-v1');
      cb.onConflict?.(conflict);

      const full = cb as FullCallback;
      expect(full.lastConflictMessage !== null).assertTrue();
      expect(full.lastConflictMessage!.remoteModifiedTime).assertEqual(1234567);
      expect(full.lastConflictMessage!.remoteVersion).assertEqual('remote-v1');
    });

    it('PartialCallback implements only onSuccess and onError', 0, () => {
      const cb: SaveDatabaseCallback = new PartialCallback();
      const success = new SuccessMessage(new ArrayBuffer(0), 100, false, 'v1', 'h1');

      cb.onSuccess?.(success);
      cb.onError?.('err');

      const partial = cb as PartialCallback;
      expect(partial.successCount).assertEqual(1);
      expect(partial.errorCount).assertEqual(1);
    });

    it('PartialCallback onMessage and onConflict are undefined', 0, () => {
      const cb: SaveDatabaseCallback = new PartialCallback();
      expect(cb.onMessage).assertUndefined();
      expect(cb.onConflict).assertUndefined();
    });

    it('object literal satisfies interface with all methods', 0, () => {
      let successCalled = false;
      let errorCalled = false;
      let messageCalled = false;
      let conflictCalled = false;

      const cb: SaveDatabaseCallback = {
        onSuccess: (message: SuccessMessage) => { successCalled = true; },
        onError: (message: string) => { errorCalled = true; },
        onMessage: (message: string) => { messageCalled = true; },
        onConflict: (message: ConflictMessage) => { conflictCalled = true; }
      };

      const success = new SuccessMessage(new ArrayBuffer(0), 0, false, null, null);
      const conflict = new ConflictMessage(0, null);

      cb.onSuccess?.(success);
      cb.onError?.('e');
      cb.onMessage?.('m');
      cb.onConflict?.(conflict);

      expect(successCalled).assertTrue();
      expect(errorCalled).assertTrue();
      expect(messageCalled).assertTrue();
      expect(conflictCalled).assertTrue();
    });

    it('object literal satisfies interface with no methods', 0, () => {
      const cb: SaveDatabaseCallback = {};
      expect(cb.onSuccess).assertUndefined();
      expect(cb.onError).assertUndefined();
      expect(cb.onMessage).assertUndefined();
      expect(cb.onConflict).assertUndefined();
    });

    it('object literal satisfies interface with only onError', 0, () => {
      let errorReceived = '';
      const cb: SaveDatabaseCallback = {
        onError: (message: string) => { errorReceived = message; }
      };
      expect(cb.onSuccess).assertUndefined();
      expect(cb.onMessage).assertUndefined();
      expect(cb.onConflict).assertUndefined();
      cb.onError?.('only-error');
      expect(errorReceived).assertEqual('only-error');
    });

    it('ToastSaveDatabaseCallback satisfies SaveDatabaseCallback interface', 0, () => {
      const cb: SaveDatabaseCallback = new ToastSaveDatabaseCallback();
      expect(typeof cb.onSuccess === 'function').assertTrue();
      expect(typeof cb.onError === 'function').assertTrue();
      expect(typeof cb.onMessage === 'function').assertTrue();
      expect(cb.onConflict).assertUndefined();
    });

    it('SuccessMessage data field accepts Kdbx instance', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('CallbackInterfaceDb', 'cb-entry');
      const message = new SuccessMessage(database, Date.now(), false, 'v1', 'h1');
      let received: SuccessMessage | null = null;

      const cb: SaveDatabaseCallback = {
        onSuccess: (msg: SuccessMessage) => { received = msg; }
      };
      cb.onSuccess?.(message);

      expect(received !== null).assertTrue();
      expect(received!.data instanceof Kdbx).assertTrue();
      expect(received!.version).assertEqual('v1');
      expect(received!.contentHash).assertEqual('h1');
    });

    it('multiple invocations increment counters correctly', 0, () => {
      const cb: SaveDatabaseCallback = new FullCallback();
      const success = new SuccessMessage(new ArrayBuffer(0), 0, false, null, null);

      cb.onSuccess?.(success);
      cb.onSuccess?.(success);
      cb.onSuccess?.(success);
      cb.onError?.('e1');
      cb.onError?.('e2');

      const full = cb as FullCallback;
      expect(full.successCount).assertEqual(3);
      expect(full.errorCount).assertEqual(2);
    });
  });
}
