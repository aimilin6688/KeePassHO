import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Consts, Kdbx, KdbxUuid } from 'kdbxweb';
import { LocalFileStorage } from '../../../../main/ets/storage/local/LocalFileStorage';
import { FileStorageFactory } from '../../../../main/ets/storage/FileStorageFactory';
import { FileInfo, StorageType, TransferProgressCallback } from '../../../../main/ets/storage';
import { DatabaseLoad } from '../../../../main/ets/workers/DatabaseLoad';
import { LoadDatabase } from '../../../../main/ets/workers/DatabaseLoadWorkerParam';
import { LoadMessage, ProgressMessage, SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { KdbxLoadServiceCallback } from '../../../../main/ets/services/kdbx/KdbxLoadService';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { HashUtils } from '../../../../main/ets/common/utils/HashUtils';
import { AuthType } from '../../../../main/ets/services/TypeDefined';
import { KdbxModeTestHelper } from './KdbxModeTestHelper';
import { TestContextHelper } from '../TestContextHelper';

/**
 * 部分进度存储：下载完成后仅上报 1%（不补 100%），
 * 驱动限频器 finish() 兜底补发末条 100% 分支（真实存储全程上报时该分支不触发）。
 */
class PartialProgressStorage extends LocalFileStorage {
  public async readToFile(path: string, destPath: string, onProgress?: TransferProgressCallback):
    Promise<FileInfo> {
    const info: FileInfo = await super.readToFile(path, destPath);
    if (onProgress) {
      onProgress(1, 100);
    }
    return info;
  }
}

/**
 * M0 v3 直传容器运输子类（镜像 DatabaseLoadWorker 的 useContainerTransport），
 * 基类 post* 直接转发回调，主线程可断言（Worker 子类 post* 走 workerPort 无法回调）。
 */
class ContainerTransportLoad extends DatabaseLoad {
  protected useContainerTransport(): boolean {
    return true;
  }
}

/**
 * DatabaseLoad 回调与分支覆盖：
 * - 全回调加载（onLoadMessage/onProgressMessage/onSuccessMessage）与进度兜底 100%
 * - 错误密码走 onErrorMessage
 * - loadKdbxFileToFile 空路径守卫与 CP1 超限拒绝（设置快照恢复）
 * - v3 直传容器快路径：ChaCha20 命中（m0Path + 空缓冲）/ AES 回退全模型
 */
export default function DatabaseLoadCallbackTest() {
  describe('DatabaseLoadCallback', () => {
    let appContext: common.Context;
    let aesPath: string;
    let chachaPath: string;
    const aesFileName: string = 'db-load-callback-aes.kdbx';
    const chachaFileName: string = 'db-load-callback-chacha.kdbx';

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      await SettingsService.getInstance().init(await TestContextHelper.getUIAbilityContext());
      aesPath = appContext.filesDir + '/' + aesFileName;
      chachaPath = appContext.filesDir + '/' + chachaFileName;
      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new PartialProgressStorage());

      const aesDatabase: Kdbx = await KdbxModeTestHelper.createDatabase('LoadCallbackAesDb', 'load-callback-aes-entry');
      await new KdbxFileManager(StorageType.LOCAL).write(aesPath, await aesDatabase.save());

      const chachaDatabase: Kdbx = await KdbxModeTestHelper.createDatabase('LoadCallbackChachaDb', 'load-callback-chacha-entry');
      chachaDatabase.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
      await new KdbxFileManager(StorageType.LOCAL).write(chachaPath, await chachaDatabase.save());
    });

    afterAll(() => {
      FileStorageFactory.getInstance().registerStorage(StorageType.LOCAL, new LocalFileStorage());
      for (const p of [aesPath, chachaPath]) {
        try {
          fs.unlinkSync(p);
        } catch {
          // 文件不存在：忽略
        }
      }
    });

    it('full callback load receives stage, progress and success messages', 0, async () => {
      const loadStages: string[] = [];
      const progressPercents: number[] = [];
      const successMessages: SuccessMessage[] = [];
      const callback: KdbxLoadServiceCallback = {
        onLoadMessage: (message: LoadMessage) => {
          loadStages.push(String(message.message));
        },
        onProgressMessage: (message: ProgressMessage) => {
          progressPercents.push(message.percent);
        },
        onSuccessMessage: (message: SuccessMessage) => {
          successMessages.push(message);
        },
        onErrorMessage: (message: LoadMessage) => {
        }
      };

      await new DatabaseLoad().handleLoadDatabase(
        KdbxModeTestHelper.makeLoadParam(aesPath, aesFileName, KdbxModeTestHelper.DB_PASSWORD), callback);

      expect(loadStages.length >= 4).assertTrue();
      expect(progressPercents.includes(1)).assertTrue();
      expect(progressPercents.includes(100)).assertTrue();
      expect(successMessages.length === 1).assertTrue();
      expect(successMessages[0].data instanceof Kdbx).assertTrue();
    });

    it('wrong password load reports error through onErrorMessage', 0, async () => {
      let errorMessage: LoadMessage | null = null;
      const callback: KdbxLoadServiceCallback = {
        onSuccessMessage: (message: SuccessMessage) => {
        },
        onErrorMessage: (message: LoadMessage) => {
          errorMessage = message;
        }
      };

      await new DatabaseLoad().handleLoadDatabase(
        KdbxModeTestHelper.makeLoadParam(aesPath, aesFileName, 'Wrong-Pass-999'), callback);

      expect(errorMessage !== null).assertTrue();
    });

    it('loadKdbxFileToFile rejects empty file path', 0, async () => {
      const param: LoadDatabase = new LoadDatabase('', 'empty.kdbx', KdbxModeTestHelper.DB_PASSWORD,
        AuthType.PASSWORD, undefined, StorageType.LOCAL, {});
      let rejected = false;
      try {
        await new DatabaseLoad().loadKdbxFileToFile(param, appContext.cacheDir + '/load-callback-empty.tmp');
      } catch {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('guard rejects database load when max size limit is zero (CP1)', 0, async () => {
      const originalLimit: number = SettingsService.getSync<number>(SettingsService.KEY_DATABASE_MAX_SIZE,
        SettingsService.KEY_DATABASE_MAX_SIZE_DEFAULT);
      await SettingsService.put(SettingsService.KEY_DATABASE_MAX_SIZE, 0);
      try {
        let rejected = false;
        let message = '';
        try {
          await KdbxModeTestHelper.loadSync(
            KdbxModeTestHelper.makeLoadParam(aesPath, aesFileName, KdbxModeTestHelper.DB_PASSWORD));
        } catch (e) {
          rejected = true;
          message = (e as Error).message;
        }
        expect(rejected).assertTrue();
        expect(message.includes('database_too_large')).assertTrue();
      } finally {
        await SettingsService.put(SettingsService.KEY_DATABASE_MAX_SIZE, originalLimit);
      }
    });

    it('container transport loads chacha20 database into m0 session file', 0, async () => {
      const successMessages: SuccessMessage[] = [];
      const callback: KdbxLoadServiceCallback = {
        onSuccessMessage: (message: SuccessMessage) => {
          successMessages.push(message);
        },
        onErrorMessage: (message: LoadMessage) => {
        }
      };

      await new ContainerTransportLoad().handleLoadDatabase(
        KdbxModeTestHelper.makeLoadParam(chachaPath, chachaFileName, KdbxModeTestHelper.DB_PASSWORD), callback);

      expect(successMessages.length === 1).assertTrue();
      const message = successMessages[0];
      expect(message.m0Path !== undefined && message.m0Path.length > 0).assertTrue();
      expect((message.data as ArrayBuffer).byteLength).assertEqual(0);
      const fileContent = await new KdbxFileManager(StorageType.LOCAL).read(chachaPath);
      expect(message.contentHash ?? '').assertEqual(await HashUtils.sha256Hex(fileContent.content));
    });

    it('container transport falls back to model path for aes database', 0, async () => {
      const successMessages: SuccessMessage[] = [];
      const callback: KdbxLoadServiceCallback = {
        onSuccessMessage: (message: SuccessMessage) => {
          successMessages.push(message);
        },
        onErrorMessage: (message: LoadMessage) => {
        }
      };

      await new ContainerTransportLoad().handleLoadDatabase(
        KdbxModeTestHelper.makeLoadParam(aesPath, aesFileName, KdbxModeTestHelper.DB_PASSWORD), callback);

      expect(successMessages.length === 1).assertTrue();
      const message = successMessages[0];
      expect(message.data instanceof Kdbx).assertTrue();
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(message.data as Kdbx);
      expect(titles.includes('load-callback-aes-entry')).assertTrue();
    });

    it('container transport surfaces corrupt database payload as error', 0, async () => {
      const corruptBytes: ArrayBuffer = new ArrayBuffer(512);
      const view: Uint8Array = new Uint8Array(corruptBytes);
      for (let i = 0; i < view.length; i++) {
        view[i] = (i * 31 + 7) % 256;
      }
      const corruptPath: string = appContext.filesDir + '/db-load-callback-corrupt.kdbx';
      await new KdbxFileManager(StorageType.LOCAL).write(corruptPath, corruptBytes);
      try {
        const errorMessages: LoadMessage[] = [];
        const callback: KdbxLoadServiceCallback = {
          onSuccessMessage: (message: SuccessMessage) => {
          },
          onErrorMessage: (message: LoadMessage) => {
            errorMessages.push(message);
          }
        };

        await new ContainerTransportLoad().handleLoadDatabase(
          KdbxModeTestHelper.makeLoadParam(corruptPath, 'db-load-callback-corrupt.kdbx',
            KdbxModeTestHelper.DB_PASSWORD), callback);

        expect(errorMessages.length === 1).assertTrue();
      } finally {
        try {
          fs.unlinkSync(corruptPath);
        } catch {
          // 文件不存在：忽略
        }
      }
    });
  });
}
