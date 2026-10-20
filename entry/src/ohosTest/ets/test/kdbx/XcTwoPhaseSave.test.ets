import { beforeAll, afterAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ByteUtils, CryptoEngine, Kdbx, KdbxChallengeResponseFn, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { FileService } from '../../../../main/ets/services/FileService';
import { AuthType, DbFileParam } from '../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../main/ets/storage';
import { ConflictStrategy, SaveChallengePair, SaveDatabaseMessage } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
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
 * XC 两阶段保存 Worker 链路回归（§9 M2/M5）。
 *
 * 覆盖：
 * - 预挑战对注入端到端：保存产物文件头 KDF seed 'S' == 注入 salt，
 *   且以预挑战固定应答可回开（注入 salt 与新应答严格配对）
 * - 保存后会话固定应答还原（finally 防护）：内存库凭证仍回会话应答
 * - 挑战对 salt 长度非法时保存明确失败，远端文件字节不变（不裸保存）
 */
export default function XcTwoPhaseSaveTest() {
  describe('XcTwoPhaseSave', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let xcDbPath: string;
    const xcDbFileName: string = 'xc-two-phase-save.kdbx';
    /** 会话固定应答（hex，20 字节 0x02）：建库与保存后会话还原基准 */
    let sessionResponseHex: string;
    /** 预挑战固定应答（hex，20 字节 0x03）：保存注入用 */
    let challengeResponseHex: string;
    /** 预挑战 KDF salt（hex，32 字节随机） */
    let challengeSaltHex: string;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      xcDbPath = appContext.filesDir + '/' + xcDbFileName;

      sessionResponseHex = ByteUtils.bytesToHex(new Uint8Array(20).fill(2));
      const sessionResponse: KdbxChallengeResponseFn = (_challenge: ArrayBuffer) => {
        const copy: Uint8Array = new Uint8Array(20).fill(2);
        return Promise.resolve(copy);
      };
      const credentials = new KdbxCredentials(
        ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD), null, sessionResponse);
      const database = Kdbx.create(credentials, 'XcTwoPhaseDb');
      KdbxModeTestHelper.addEntry(database, 'xc-2p-base-entry');
      await fileManager.write(xcDbPath, await database.save());

      challengeSaltHex = ByteUtils.bytesToHex(CryptoEngine.random(32));
      challengeResponseHex = ByteUtils.bytesToHex(new Uint8Array(20).fill(3));
    });

    afterAll(async () => {
      const cleanupDatabase = await KdbxModeTestHelper.createDatabase('XcTwoPhaseCleanupDb', 'cleanup-entry');
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
      try { fs.unlinkSync(xcDbPath); } catch { /* ignore */ }
    });

    it('two-phase save injects pre-challenge salt and reopens with new response', 0, async () => {
      // 阶段一：以会话固定应答解锁远端文件
      const sessionResponse: KdbxChallengeResponseFn = (_challenge: ArrayBuffer) => {
        const copy: Uint8Array = new Uint8Array(20).fill(2);
        return Promise.resolve(copy);
      };
      const sessionCredentials = new KdbxCredentials(
        ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD), null, sessionResponse);
      const fileContent = await fileManager.read(xcDbPath);
      const database = await Kdbx.load(fileContent.content, sessionCredentials);
      KdbxModeTestHelper.addEntry(database, 'xc-2p-saved-entry');

      // 阶段二：携带预挑战对保存（注入 salt + 新固定应答）
      const pair: SaveChallengePair = { kdfSaltHex: challengeSaltHex, responseHex: challengeResponseHex };
      const dbFileParam: DbFileParam = {
        filePath: xcDbPath,
        fileName: xcDbFileName,
        password: KdbxModeTestHelper.DB_PASSWORD,
        database: database,
        authType: AuthType.PASSWORD_CHALLENGE_RESPONSE_XC,
        storageType: StorageType.LOCAL,
        storageConfig: {},
        modifiedTime: 0,
        version: fileContent.version ?? null,
        contentHash: null,
        challengeResponseHex: sessionResponseHex
      };
      const saveResult: SyncSaveResult = await withTimeout(
        KdbxModeTestHelper.saveSync(new SaveDatabaseMessage(database, dbFileParam, ConflictStrategy.AUTO, pair)),
        TEST_TIMEOUT_MS);
      expect(saveResult.success !== null).assertTrue();

      // 阶段三：以预挑战新固定应答回开保存产物
      const challengeResponse: KdbxChallengeResponseFn = (_challenge: ArrayBuffer) => {
        const copy: Uint8Array = new Uint8Array(20).fill(3);
        return Promise.resolve(copy);
      };
      const reopenCredentials = new KdbxCredentials(
        ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD), null, challengeResponse);
      const savedContent = await fileManager.read(xcDbPath);
      const reopened = await withTimeout(Kdbx.load(savedContent.content, reopenCredentials), TEST_TIMEOUT_MS);
      const titles: string[] = KdbxModeTestHelper.collectEntryTitles(reopened);
      expect(titles.includes('xc-2p-base-entry')).assertTrue();
      expect(titles.includes('xc-2p-saved-entry')).assertTrue();

      // 文件头 KDF seed 'S' == 注入的预挑战 salt（注入与应答配对一致）
      const kdfParameters = reopened.header.kdfParameters;
      expect(kdfParameters !== undefined && kdfParameters !== null).assertTrue();
      const savedSalt = kdfParameters!.get('S');
      expect(savedSalt instanceof ArrayBuffer).assertTrue();
      expect(ByteUtils.bytesToHex(new Uint8Array(savedSalt as ArrayBuffer))).assertEqual(challengeSaltHex);

      // 保存后会话固定应答还原（finally 防护）：内存库凭证仍回会话应答（0x02）。
      // getChallengeResponse 返回 SHA-256 后的应答，比较哈希值
      const restored = await database.credentials.getChallengeResponse(new ArrayBuffer(64));
      expect(restored !== null).assertTrue();
      const expectedRestored: ArrayBuffer = await CryptoEngine.sha256(new Uint8Array(20).fill(2));
      expect(ByteUtils.bytesToHex(new Uint8Array(restored as ArrayBuffer)))
        .assertEqual(ByteUtils.bytesToHex(new Uint8Array(expectedRestored)));
    });

    it('two-phase save rejects invalid salt length and leaves file untouched', 0, async () => {
      // 独立文件：前一用例已把共享文件的应答轮换为预挑战应答（0x03），本用例不依赖其副作用
      const invalidDbPath: string = appContext.filesDir + '/xc-two-phase-save-invalid.kdbx';
      const sessionResponse: KdbxChallengeResponseFn = (_challenge: ArrayBuffer) => {
        const copy: Uint8Array = new Uint8Array(20).fill(2);
        return Promise.resolve(copy);
      };
      const createCredentials = new KdbxCredentials(
        ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD), null, sessionResponse);
      const freshDatabase = Kdbx.create(createCredentials, 'XcTwoPhaseInvalidSaltDb');
      KdbxModeTestHelper.addEntry(freshDatabase, 'xc-2p-invalid-salt-base');
      await fileManager.write(invalidDbPath, await freshDatabase.save());

      const beforeContent = await fileManager.read(invalidDbPath);
      const beforeHash: string = await KdbxModeTestHelper.sha256Hex(beforeContent.content);

      const reopenCredentials = new KdbxCredentials(
        ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD), null, sessionResponse);
      const database = await Kdbx.load(beforeContent.content, reopenCredentials);
      KdbxModeTestHelper.addEntry(database, 'xc-2p-invalid-salt-entry');

      // 非法挑战对：salt 31 字节
      const badSaltHex: string = ByteUtils.bytesToHex(CryptoEngine.random(31));
      const badPair: SaveChallengePair = { kdfSaltHex: badSaltHex, responseHex: challengeResponseHex };
      const dbFileParam: DbFileParam = {
        filePath: invalidDbPath,
        fileName: 'xc-two-phase-save-invalid.kdbx',
        password: KdbxModeTestHelper.DB_PASSWORD,
        database: database,
        authType: AuthType.PASSWORD_CHALLENGE_RESPONSE_XC,
        storageType: StorageType.LOCAL,
        storageConfig: {},
        modifiedTime: 0,
        version: beforeContent.version ?? null,
        contentHash: null,
        challengeResponseHex: sessionResponseHex
      };
      let caught: Error | null = null;
      try {
        await withTimeout(KdbxModeTestHelper.saveSync(
          new SaveDatabaseMessage(database, dbFileParam, ConflictStrategy.AUTO, badPair)), TEST_TIMEOUT_MS);
      } catch (error) {
        caught = error as Error;
      }
      expect(caught !== null).assertTrue();
      // 明确以 32 字节校验拒绝，而非裸保存后报错
      expect(caught!.message.includes('32 bytes')).assertTrue();

      // 非法对在任何落盘之前失败：远端文件字节不变
      const afterContent = await fileManager.read(invalidDbPath);
      const afterHash: string = await KdbxModeTestHelper.sha256Hex(afterContent.content);
      expect(afterHash).assertEqual(beforeHash);

      try { fs.unlinkSync(invalidDbPath); } catch { /* ignore */ }
    });
  });
}
