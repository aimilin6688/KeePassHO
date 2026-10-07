import { afterAll, afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { FTPConfig, FTPHandler } from '../../../../../main/ets/storage/ftp/FTPHandler';
import { StorageError, StorageErrorCodes } from '../../../../../main/ets/storage/StorageError';
import { CommonUtils } from '../../../../../main/ets/common/utils/CommonUtils';

function makeConfig(): FTPConfig {
  return {
    host: '127.0.0.1',
    port: 1,
    username: 'user',
    password: 'pass'
  };
}

function makeUnreachableConfig(): FTPConfig {
  return {
    host: '127.0.0.1',
    port: 1,
    username: 'user',
    password: 'pass',
    timeout: 3000
  };
}

export default function FTPHandlerTest() {
  describe('FTPHandlerTest', () => {

    describe('NotConnected', () => {
      it('isClosed should be true before connect', 0, () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        expect(handler.isClosed()).assertTrue();
      });

      it('close should resolve before connect (idempotent)', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        await handler.close();
        expect(handler.isClosed()).assertTrue();
      });

      it('close should be idempotent when called twice', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        await handler.close();
        await handler.close();
        expect(handler.isClosed()).assertTrue();
      });

      it('getFileInfo(/) should throw before connect', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        try {
          await handler.getFileInfo('/');
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertContain('not connected');
        }
      });

      it('getFileInfo(empty) should throw before connect', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        try {
          await handler.getFileInfo('');
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertContain('not connected');
        }
      });

      it('getFileInfo(non-root) should throw before connect', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        try {
          await handler.getFileInfo('/a.kdbx');
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertContain('not connected');
        }
      });

      it('downloadFrom should throw before connect', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        try {
          await handler.downloadFrom('/remote.kdbx', '/local.kdbx');
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertContain('not connected');
        }
      });

      it('uploadTo should throw before connect', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        try {
          await handler.uploadTo('/local.kdbx', '/remote.kdbx');
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertContain('not connected');
        }
      });

      it('listDir should throw before connect', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        try {
          await handler.listDir('/');
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertContain('not connected');
        }
      });

      it('exists should throw "Failed to check if file exists" before connect', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        try {
          await handler.exists('/some/path.kdbx');
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertEqual('Failed to check if file exists');
        }
      });

      it('exists(/) should throw "Failed to check if file exists" before connect', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeConfig());
        try {
          await handler.exists('/');
          expect(false).assertTrue();
        } catch (e) {
          expect((e as Error).message).assertEqual('Failed to check if file exists');
        }
      });
    });

    describe('FTPHandlerConnectTest', () => {
      beforeAll(() => {
        const appContext: common.Context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext();
        CommonUtils.init(appContext as common.UIAbilityContext);
      });

      it('connect to unreachable port should reject with StorageError CONNECT_ERROR', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeUnreachableConfig());
        try {
          await handler.connect();
          expect(false).assertTrue();
        } catch (e) {
          expect(e instanceof StorageError).assertTrue();
          if (e instanceof StorageError) {
            expect(e.code).assertEqual(StorageErrorCodes.CONNECT_ERROR);
          }
        }
      });

      it('isClosed should stay true after failed connect', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeUnreachableConfig());
        try {
          await handler.connect();
        } catch {
          // 预期失败
        }
        expect(handler.isClosed()).assertTrue();
      });

      it('close should resolve after failed connect', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeUnreachableConfig());
        try {
          await handler.connect();
        } catch {
          // 预期失败
        }
        await handler.close();
        expect(handler.isClosed()).assertTrue();
      });

      it('consecutive connect failures should both reject with CONNECT_ERROR', 0, async () => {
        const handler: FTPHandler = new FTPHandler(makeUnreachableConfig());
        for (let i = 0; i < 2; i++) {
          try {
            await handler.connect();
            expect(false).assertTrue();
          } catch (e) {
            expect(e instanceof StorageError).assertTrue();
            if (e instanceof StorageError) {
              expect(e.code).assertEqual(StorageErrorCodes.CONNECT_ERROR);
            }
          }
        }
      });
    });
  });
}
