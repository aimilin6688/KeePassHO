import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { Kdbx } from 'kdbxweb';

import KdbxLoadService, { KdbxLoadServiceCallback } from '../../../../main/ets/services/kdbx/KdbxLoadService';
import { LoadDatabase } from '../../../../main/ets/workers/DatabaseLoadWorkerParam';
import { LoadMessage, SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { StorageType } from '../../../../main/ets/storage';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { KdbxModeTestHelper } from './KdbxModeTestHelper';

/** 队列任务等待超时（毫秒） */
const QUEUE_TIMEOUT: number = 30000;

/**
 * 等待条件成立（轮询），超时抛错（防止用例挂死拖垮整个测试批次）
 */
function waitFor(condition: () => boolean, timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const start: number = Date.now();
    const timer = setInterval(() => {
      if (condition()) {
        clearInterval(timer);
        resolve();
        return;
      }
      if (Date.now() - start > timeoutMs) {
        clearInterval(timer);
        reject(new Error('waitFor timeout'));
      }
    }, 50);
  });
}

/**
 * KdbxLoadService.enqueueLoad（M3 串行加载队列）单元测试。
 *
 * 覆盖：
 * - 多任务同时入队：FIFO 串行完成，无 worker_busy 拒绝
 * - 队首任务失败（错误密码）：队列继续派发后续任务
 */
export default function DatabaseLoadQueueTest() {
  describe('DatabaseLoadQueue', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let dbPaths: string[] = [];
    let dbNames: string[] = [];

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      dbPaths = [];
      dbNames = [];
      for (let i = 0; i < 3; i++) {
        const database: Kdbx = await KdbxModeTestHelper.createDatabase(`QueueDb${i}`, `queue-entry-${i}`);
        const path = `${appContext.filesDir}/db-queue-${i}.kdbx`;
        await fileManager.write(path, await database.save());
        dbPaths.push(path);
        dbNames.push(`db-queue-${i}.kdbx`);
      }
    });

    it('enqueueLoad processes queued loads serially in FIFO order without busy rejection', 0, async () => {
      const completionOrder: string[] = [];
      const promises: Promise<void>[] = [];
      for (let i = 0; i < 3; i++) {
        const loadParam: LoadDatabase = KdbxModeTestHelper.makeLoadParam(dbPaths[i], dbNames[i],
          KdbxModeTestHelper.DB_PASSWORD);
        promises.push(new Promise<void>((resolve, reject) => {
          const callback: KdbxLoadServiceCallback = {
            onSuccessMessage: (message: SuccessMessage) => {
              completionOrder.push(`ok${i}`);
              resolve();
            },
            onErrorMessage: (message: LoadMessage) => {
              reject(new Error(`load ${i} rejected: ${String(message.message)}`));
            }
          };
          KdbxLoadService.enqueueLoad(loadParam, callback);
        }));
      }
      await Promise.all(promises);
      await waitFor(() => completionOrder.length === 3, QUEUE_TIMEOUT);
      // FIFO：完成顺序与入队顺序一致，全程无 worker_busy 错误（否则上方 reject 已失败）
      expect(completionOrder[0]).assertEqual('ok0');
      expect(completionOrder[1]).assertEqual('ok1');
      expect(completionOrder[2]).assertEqual('ok2');
    });

    it('enqueueLoad continues queue after load failure', 0, async () => {
      const badParam: LoadDatabase = KdbxModeTestHelper.makeLoadParam(dbPaths[0], dbNames[0], 'wrong-password');
      const goodParam: LoadDatabase = KdbxModeTestHelper.makeLoadParam(dbPaths[1], dbNames[1],
        KdbxModeTestHelper.DB_PASSWORD);
      const badResult: Promise<string> = new Promise<string>((resolve, reject) => {
        const callback: KdbxLoadServiceCallback = {
          onSuccessMessage: (message: SuccessMessage) => {
            reject(new Error('bad load unexpectedly succeeded'));
          },
          onErrorMessage: (message: LoadMessage) => {
            resolve(String(message.message));
          }
        };
        KdbxLoadService.enqueueLoad(badParam, callback);
      });
      const goodResult: Promise<string> = new Promise<string>((resolve, reject) => {
        const callback: KdbxLoadServiceCallback = {
          onSuccessMessage: (message: SuccessMessage) => {
            resolve('ok');
          },
          onErrorMessage: (message: LoadMessage) => {
            reject(new Error(`good load rejected: ${String(message.message)}`));
          }
        };
        KdbxLoadService.enqueueLoad(goodParam, callback);
      });
      const badError: string = await badResult;
      expect(badError.length > 0).assertTrue();
      // 队首失败后队列继续：第二个任务正常成功（不被 worker_busy 或队首错误阻塞）
      const good: string = await goodResult;
      expect(good).assertEqual('ok');
    });
  });
}
