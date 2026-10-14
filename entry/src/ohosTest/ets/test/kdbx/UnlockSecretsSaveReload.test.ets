import { beforeAll, afterAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ByteUtils, Consts, Kdbx, KdbxCredentials, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { ResourceManager } from '../../../../main/ets/common/utils';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import KdbxLoadService, { KdbxLoadServiceCallback } from '../../../../main/ets/services/kdbx/KdbxLoadService';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { FileService } from '../../../../main/ets/services/FileService';
import KdbxSaveService from '../../../../main/ets/services/kdbx/KdbxSaveService';
import { AuthType, CredentialsParam, DbFileParam } from '../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../main/ets/storage';
import { ConflictStrategy, SaveDatabaseMessage } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { LoadDatabase } from '../../../../main/ets/workers/DatabaseLoadWorkerParam';
import { SuccessMessage } from '../../../../main/ets/workers/WorkerParam';
import { SaveDatabaseCallback } from '../../../../main/ets/workers/callback/SaveDatabaseCallback';
import { KdbxModeTestHelper, SyncSaveResult } from '../workers/KdbxModeTestHelper';

const TEST_TIMEOUT_MS: number = 60000;

function withTimeout<T>(pending: Promise<T>, timeoutMs: number): Promise<T> {
  return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void) => {
    const timerId = setTimeout(() => {
      reject(new Error('test timeout'));
    }, timeoutMs);
    pending.then((value: T) => {
      clearTimeout(timerId);
      resolve(value);
    }, (error: Error) => {
      clearTimeout(timerId);
      reject(error);
    });
  });
}

/**
 * 解锁链路 secret 透传端到端回归（缺口修复 1/2/3）。
 *
 * 覆盖：
 * - OTP 库 Worker 容器直传解锁 → 主线程按 otpSecretHex 重建凭证解析（缺口 2 正例）
 * - 保存携带 otpSecretHex 落盘 → 静态 secret 重开保存产物可用（缺口 1 端到端）
 * - 容器还原缺 otpSecretHex 时 OtpSecretStrategy 明确拒绝（回归钉：DbFileParam 必须携带）
 * - XC 模型路径加载消费 challengeResponseHex，并在传输前剥离挑战回调（缺口 2 XC 侧）
 * - XC 加载缺 challengeResponseHex 时明确拒绝，不静默降级为仅密码
 * - XC 保存被服务入口拦截：明确报错且远端文件字节不变（缺口 3）
 */
export default function UnlockSecretsSaveReloadTest() {
  describe('UnlockSecretsSaveReload', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let otpDbPath: string;
    let xcDbPath: string;
    const otpDbFileName: string = 'unlock-secrets-otp-e2e.kdbx';
    const xcDbFileName: string = 'unlock-secrets-xc-e2e.kdbx';
    /** OTP secret（hex）：与建库 customKey 字节严格一致（KcpCustomKey 语义） */
    let otpSecretHex: string;
    /** XC 固定应答（hex）：与建库挑战回调返回字节严格一致 */
    let xcResponseHex: string;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      otpDbPath = appContext.filesDir + '/' + otpDbFileName;
      xcDbPath = appContext.filesDir + '/' + xcDbFileName;

      // OTP 库：主密码 + customKey（32 字节 0x01）；
      // 指定 ChaCha20 → Worker 加载走 M0 v3 直传容器（SFW1 流式），对齐大库真实调度路径
      otpSecretHex = ByteUtils.bytesToHex(new Uint8Array(32).fill(1));
      const otpCredentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD),
        null, undefined, new Uint8Array(32).fill(1));
      const otpDatabase = Kdbx.create(otpCredentials, 'UnlockSecretsOtpDb');
      otpDatabase.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
      KdbxModeTestHelper.addEntry(otpDatabase, 'otp-base-entry');
      await fileManager.write(otpDbPath, await otpDatabase.save());

      // XC 库：主密码 + 固定应答回调（20 字节 0x02，对任意挑战恒定返回）
      xcResponseHex = ByteUtils.bytesToHex(new Uint8Array(20).fill(2));
      const fixedResponse = (_challenge: ArrayBuffer): Promise<Uint8Array> => {
        const copy: Uint8Array = new Uint8Array(20).fill(2);
        return Promise.resolve(copy);
      };
      const xcCredentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD),
        null, fixedResponse);
      const xcDatabase = Kdbx.create(xcCredentials, 'UnlockSecretsXcDb');
      KdbxModeTestHelper.addEntry(xcDatabase, 'xc-base-entry');
      await fileManager.write(xcDbPath, await xcDatabase.save());
    });

    afterAll(async () => {
      KdbxLoadService.stopWorker();
      // XC 拦截用例污染的 FileService 状态复位为无害 PASSWORD 态，防泄漏到后续套件
      const cleanupDatabase = await KdbxModeTestHelper.createDatabase('UnlockSecretsCleanupDb', 'cleanup-entry');
      FileService.setDbFileParam({
        filePath: '',
        fileName: '',
        password: '',
        database: cleanupDatabase,
        authType: AuthType.PASSWORD,
        storageType: StorageType.LOCAL,
        storageConfig: {},
        modifiedTime: 0,
        version: null,
        contentHash: null
      });
      try { fs.unlinkSync(otpDbPath); } catch { /* ignore */ }
      try { fs.unlinkSync(xcDbPath); } catch { /* ignore */ }
    });

    it('OTP worker container unlock, save with otpSecretHex, reopen saved file', 0, async () => {
      // 阶段一：Worker 容器直传解锁（强制 Worker 调度；v4+ChaCha20 → m0 容器）
      const loadParam = new LoadDatabase(otpDbPath, otpDbFileName, KdbxModeTestHelper.DB_PASSWORD,
        AuthType.PASSWORD_OTP, undefined, StorageType.LOCAL, {});
      loadParam.otpSecretHex = otpSecretHex;
      KdbxModeTestHelper.forceWorkerDispatch(otpDbPath);

      const message = await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
        const callback: KdbxLoadServiceCallback = {
          onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
          onErrorMessage: () => { reject(new Error('load failed')); }
        };
        KdbxLoadService.loadDatabase(loadParam, callback);
      }), TEST_TIMEOUT_MS);
      KdbxLoadService.stopWorker();

      // 容器直传成立；主线程按 credentialsParam（含 otpSecretHex）重建凭证解析
      expect(message.m0Path !== undefined && message.m0Path.length > 0).assertTrue();
      const restored: Kdbx = await withTimeout(KdbxUtils.successMessageToKdbx(message, loadParam),
        TEST_TIMEOUT_MS);
      expect(KdbxModeTestHelper.collectEntryTitles(restored).includes('otp-base-entry')).assertTrue();

      // 阶段二：添加条目 → 保存（dbFileParam 携带 otpSecretHex）
      KdbxModeTestHelper.addEntry(restored, 'otp-saved-entry');
      const dbFileParam: DbFileParam = {
        filePath: otpDbPath,
        fileName: otpDbFileName,
        password: KdbxModeTestHelper.DB_PASSWORD,
        database: restored,
        authType: AuthType.PASSWORD_OTP,
        storageType: StorageType.LOCAL,
        storageConfig: {},
        modifiedTime: message.modifiedTime,
        version: message.version,
        contentHash: message.contentHash,
        otpSecretHex: otpSecretHex
      };
      const saveResult: SyncSaveResult = await withTimeout(
        KdbxModeTestHelper.saveSync(new SaveDatabaseMessage(restored, dbFileParam, ConflictStrategy.AUTO)),
        TEST_TIMEOUT_MS);
      expect(saveResult.success !== null).assertTrue();
      expect(saveResult.success !== null && saveResult.success.contentHash !== message.contentHash).assertTrue();

      // 阶段三：重开（主线程模型路径）——保存产物仍可用同一静态 secret 解锁
      const reopenParam = new LoadDatabase(otpDbPath, otpDbFileName, KdbxModeTestHelper.DB_PASSWORD,
        AuthType.PASSWORD_OTP, undefined, StorageType.LOCAL, {});
      reopenParam.otpSecretHex = otpSecretHex;
      const reopenMessage = await withTimeout(KdbxModeTestHelper.loadSync(reopenParam), TEST_TIMEOUT_MS);
      const reopened: Kdbx = await withTimeout(KdbxUtils.successMessageToKdbx(reopenMessage, reopenParam),
        TEST_TIMEOUT_MS);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(reopened);
      expect(titles.includes('otp-base-entry')).assertTrue();
      expect(titles.includes('otp-saved-entry')).assertTrue();
    });

    it('OTP container restore without otpSecretHex fails with error_otp_secret_missing', 0, async () => {
      // 正常 Worker 容器解锁
      const loadParam = new LoadDatabase(otpDbPath, otpDbFileName, KdbxModeTestHelper.DB_PASSWORD,
        AuthType.PASSWORD_OTP, undefined, StorageType.LOCAL, {});
      loadParam.otpSecretHex = otpSecretHex;
      KdbxModeTestHelper.forceWorkerDispatch(otpDbPath);

      const message = await withTimeout(new Promise<SuccessMessage>((resolve, reject) => {
        const callback: KdbxLoadServiceCallback = {
          onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
          onErrorMessage: () => { reject(new Error('load failed')); }
        };
        KdbxLoadService.loadDatabase(loadParam, callback);
      }), TEST_TIMEOUT_MS);
      KdbxLoadService.stopWorker();
      expect(message.m0Path !== undefined && message.m0Path.length > 0).assertTrue();

      // 主线程还原缺 otpSecretHex：OtpSecretStrategy 明确拒绝
      const brokenParam: CredentialsParam = {
        password: KdbxModeTestHelper.DB_PASSWORD,
        authType: AuthType.PASSWORD_OTP
      };
      let caughtMessage: string = '';
      try {
        await withTimeout(KdbxUtils.successMessageToKdbx(message, brokenParam), TEST_TIMEOUT_MS);
      } catch (error) {
        const err = error as Error;
        caughtMessage = err.message;
      }
      expect(caughtMessage.length > 0).assertTrue();
      expect(caughtMessage).assertEqual(ResourceManager.getString($r('app.string.error_otp_secret_missing')));
    });

    it('XC model-path load consumes challengeResponseHex and strips challenge fn', 0, async () => {
      const loadParam = new LoadDatabase(xcDbPath, xcDbFileName, KdbxModeTestHelper.DB_PASSWORD,
        AuthType.PASSWORD_CHALLENGE_RESPONSE_XC, undefined, StorageType.LOCAL, {});
      loadParam.challengeResponseHex = xcResponseHex;
      const message = await withTimeout(KdbxModeTestHelper.loadSync(loadParam), TEST_TIMEOUT_MS);
      const kdbx: Kdbx = await withTimeout(KdbxUtils.successMessageToKdbx(message, loadParam),
        TEST_TIMEOUT_MS);
      expect(KdbxModeTestHelper.collectEntryTitles(kdbx).includes('xc-base-entry')).assertTrue();

      // 传输前已剥离挑战回调：函数体不可跨线程结构化克隆；剥离后探测返回 null
      const probe: ArrayBuffer | Uint8Array | null =
        await kdbx.credentials.getChallengeResponse(new ArrayBuffer(64));
      expect(probe === null).assertTrue();
    });

    it('XC load without challengeResponseHex fails with error_challenge_response_missing', 0, async () => {
      const loadParam = new LoadDatabase(xcDbPath, xcDbFileName, KdbxModeTestHelper.DB_PASSWORD,
        AuthType.PASSWORD_CHALLENGE_RESPONSE_XC, undefined, StorageType.LOCAL, {});
      let caughtMessage: string = '';
      try {
        await withTimeout(KdbxModeTestHelper.loadSync(loadParam), TEST_TIMEOUT_MS);
      } catch (error) {
        const err = error as Error;
        caughtMessage = err.message;
      }
      expect(caughtMessage.length > 0).assertTrue();
      expect(caughtMessage).assertEqual(
        ResourceManager.getString($r('app.string.error_challenge_response_missing')));
    });

    it('XC save is blocked at service entry with explicit error and file untouched', 0, async () => {
      // 构造 XC authType 保存现场（内存模型 + 远端文件字节基线）
      const blockerDatabase = await KdbxModeTestHelper.createDatabase('XcBlockDb', 'xc-block-entry');
      const beforeContent = await fileManager.read(xcDbPath);
      const beforeHash: string = await KdbxModeTestHelper.sha256Hex(beforeContent.content);

      FileService.setDbFileParam({
        filePath: xcDbPath,
        fileName: xcDbFileName,
        password: KdbxModeTestHelper.DB_PASSWORD,
        database: blockerDatabase,
        authType: AuthType.PASSWORD_CHALLENGE_RESPONSE_XC,
        storageType: StorageType.LOCAL,
        storageConfig: {},
        modifiedTime: 0,
        version: null,
        contentHash: null
      });

      let errorMessage: string = '';
      let successCalled: boolean = false;
      await withTimeout(new Promise<void>((resolve) => {
        const callback: SaveDatabaseCallback = {
          onSuccess: () => { successCalled = true; resolve(); },
          onError: (msg: string) => { errorMessage = msg; resolve(); },
          onConflict: () => { resolve(); }
        };
        KdbxSaveService.saveDatabase(callback);
      }), TEST_TIMEOUT_MS);

      expect(successCalled).assertFalse();
      expect(errorMessage).assertEqual(
        ResourceManager.getString($r('app.string.error_challenge_response_save_unsupported')));

      // 拦截发生在任何落盘之前：远端文件字节不变
      const afterContent = await fileManager.read(xcDbPath);
      const afterHash: string = await KdbxModeTestHelper.sha256Hex(afterContent.content);
      expect(afterHash).assertEqual(beforeHash);
    });
  });
}
