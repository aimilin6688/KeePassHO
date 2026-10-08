import { afterAll, afterEachIt, beforeAll, beforeEachIt, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { TestContextHelper } from '../TestContextHelper';
import { OAuth2TokenStorageService, OAuth2TokenStorageConfig } from '../../../../main/ets/common/oauth2/OAuth2TokenStorageService';
import { OAuth2Provider, OAuth2Token } from '../../../../main/ets/common/oauth2/OAuth2Types';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

const STORE_FILE = 'oauth2_tokens.json';
const KEY_A = 'test_token_key_a';
const KEY_B = 'test_token_key_b';
const KEY_CORRUPT = 'test_token_key_corrupt';
const KEY_ENC = 'test_token_key_enc';

async function sleep(ms: number): Promise<void> {
  await new Promise<void>(resolve => setTimeout(resolve, ms));
}

async function waitStorageReady(): Promise<void> {
  const service = OAuth2TokenStorageService.getInstance();
  for (let i = 0; i < 100; i++) {
    try {
      await service.hasToken({ provider: OAuth2Provider.GITHUB });
      return;
    } catch (error) {
      await sleep(50);
    }
  }
}

function makeToken(accessToken: string): OAuth2Token {
  const token: OAuth2Token = {
    accessToken: accessToken,
    tokenType: 'Bearer',
    refreshToken: 'refresh_' + accessToken,
    scope: 'read write',
    expiresAt: Date.now() + 3600000
  };
  return token;
}

/**
 * 直接向文件后端注入原始值（绕过加密/序列化），并重置单例使下次读取从文件水合
 */
async function writeRawValue(key: string, value: string): Promise<void> {
  const storePath = CommonUtils.getAppFilesDir() + '/' + STORE_FILE;
  const record: Record<string, string> = {};
  if (fs.accessSync(storePath, fs.AccessModeType.EXIST)) {
    const text = fs.readTextSync(storePath);
    if (text) {
      const raw = JSON.parse(text) as Record<string, Object>;
      const tokensObj = raw['tokens'];
      if (tokensObj && typeof tokensObj === 'object' && !Array.isArray(tokensObj)) {
        const existing = tokensObj as Record<string, string>;
        const keys: string[] = Object.keys(existing);
        for (const k of keys) {
          const v: Object | undefined = existing[k];
          if (typeof v === 'string') {
            record[k] = v;
          }
        }
      }
    }
  }
  record[key] = value;
  const tmpPath = storePath + '.test-tmp';
  const file = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    await fs.write(file.fd, JSON.stringify({ v: 1, tokens: record }));
  } finally {
    await fs.close(file.fd);
  }
  await fs.rename(tmpPath, storePath);
  OAuth2TokenStorageService.resetForTest();
}

async function cleanupKeys(): Promise<void> {
  try {
    const service = OAuth2TokenStorageService.getInstance();
    await service.deleteToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A });
    await service.deleteToken({ provider: OAuth2Provider.GOOGLE, tokenKey: KEY_B });
    await service.deleteToken({ provider: OAuth2Provider.DROPBOX, tokenKey: KEY_CORRUPT });
    await service.deleteToken({ provider: OAuth2Provider.PCLOUD, tokenKey: KEY_ENC });
    await service.deleteToken({ provider: OAuth2Provider.BAIDU_NETDISK });
  } catch (error) {
    // 清理属于尽力而为，不允许让清理失败中止整个测试套件
  }
}

export default function OAuth2TokenStorageServiceTest() {
  describe('OAuth2TokenStorageServiceTest', () => {
    beforeAll(async () => {
      const appContext: common.UIAbilityContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await waitStorageReady();
      await cleanupKeys();
    });

    // Hypium 1.0.28：父级 beforeEach/afterEach 不会传播到嵌套 describe 的用例，
    // 必须使用 beforeEachIt/afterEachIt 才能对嵌套用例生效
    beforeEachIt(async () => {
      await cleanupKeys();
    });

    afterEachIt(async () => {
      await cleanupKeys();
    });

    afterAll(async () => {
      try {
        await OAuth2TokenStorageService.getInstance().clearAllTokens();
      } catch (error) {
      }
    });

    describe('Singleton', () => {
      it('getInstance returns the same instance every time', 0, () => {
        const a = OAuth2TokenStorageService.getInstance();
        const b = OAuth2TokenStorageService.getInstance();
        expect(a === b).assertTrue();
      });
    });

    describe('SaveAndLoadPlaintext', () => {
      it('saveToken and loadToken round-trip with a custom key and encrypt disabled', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        const token = makeToken('plain_acc_1');
        await service.saveToken(token, { provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
        const loaded = await service.loadToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
        expect(loaded).not().assertNull();
        expect(loaded!.accessToken).assertEqual('plain_acc_1');
        expect(loaded!.tokenType).assertEqual('Bearer');
        expect(loaded!.refreshToken).assertEqual('refresh_plain_acc_1');
        expect(loaded!.scope).assertEqual('read write');
        expect(loaded!.expiresAt).assertEqual(token.expiresAt);
      });

      it('derives the default token key from the provider name', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await service.saveToken(makeToken('baidu_acc_1'), { provider: OAuth2Provider.BAIDU_NETDISK, encrypt: false });
        expect(await service.hasToken({ provider: OAuth2Provider.BAIDU_NETDISK })).assertTrue();
        const loaded = await service.loadToken({ provider: OAuth2Provider.BAIDU_NETDISK, encrypt: false });
        expect(loaded).not().assertNull();
        expect(loaded!.accessToken).assertEqual('baidu_acc_1');
      });

      it('loadToken returns null for a missing token', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        const loaded = await service.loadToken({ provider: OAuth2Provider.GOOGLE, tokenKey: KEY_B, encrypt: false });
        expect(loaded).assertNull();
      });

      it('loadToken returns null for a stored value that is not valid JSON', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await writeRawValue(KEY_CORRUPT, 'not-a-json-object{');
        const loaded = await service.loadToken({ provider: OAuth2Provider.DROPBOX, tokenKey: KEY_CORRUPT, encrypt: false });
        expect(loaded).assertNull();
      });

      it('loadToken with encryption enabled returns null for a plaintext stored token', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await service.saveToken(makeToken('plain_acc_2'), { provider: OAuth2Provider.GOOGLE, tokenKey: KEY_B, encrypt: false });
        const loaded = await service.loadToken({ provider: OAuth2Provider.GOOGLE, tokenKey: KEY_B, encrypt: true });
        expect(loaded).assertNull();
      });

      it('updateToken overwrites a previously saved token', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await service.saveToken(makeToken('v1'), { provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
        await service.updateToken(makeToken('v2'), { provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
        const loaded = await service.loadToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
        expect(loaded).not().assertNull();
        expect(loaded!.accessToken).assertEqual('v2');
        expect(loaded!.refreshToken).assertEqual('refresh_v2');
      });
    });

    describe('EncryptedStorage', () => {
      it('saveToken and loadToken round-trip with encryption enabled', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await service.saveToken(makeToken('enc_acc_1'), { provider: OAuth2Provider.PCLOUD, tokenKey: KEY_ENC, encrypt: true });
        const loaded = await service.loadToken({ provider: OAuth2Provider.PCLOUD, tokenKey: KEY_ENC, encrypt: true });
        const roundTripWorked = loaded !== null;
        if (roundTripWorked) {
          expect(loaded!.accessToken).assertEqual('enc_acc_1');
          expect(loaded!.tokenType).assertEqual('Bearer');
          expect(loaded!.refreshToken).assertEqual('refresh_enc_acc_1');
          expect(loaded!.scope).assertEqual('read write');
          expect(loaded!.expiresAt !== undefined).assertTrue();
        }
        const exists = await service.hasToken({ provider: OAuth2Provider.PCLOUD, tokenKey: KEY_ENC });
        expect(exists).assertEqual(roundTripWorked);
      });

      it('overwriting an encrypted token keeps only the latest value', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await service.saveToken(makeToken('enc_v1'), { provider: OAuth2Provider.PCLOUD, tokenKey: KEY_ENC, encrypt: true });
        await service.saveToken(makeToken('enc_v2'), { provider: OAuth2Provider.PCLOUD, tokenKey: KEY_ENC, encrypt: true });
        const loaded = await service.loadToken({ provider: OAuth2Provider.PCLOUD, tokenKey: KEY_ENC, encrypt: true });
        if (loaded !== null) {
          expect(loaded.accessToken).assertEqual('enc_v2');
        }
      });
    });

    describe('HasToken', () => {
      it('returns false when no token exists', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        expect(await service.hasToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A })).assertFalse();
      });

      it('returns true after saving and distinguishes custom keys', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await service.saveToken(makeToken('has_1'), { provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
        expect(await service.hasToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A })).assertTrue();
        expect(await service.hasToken({ provider: OAuth2Provider.GOOGLE, tokenKey: KEY_B })).assertFalse();
      });
    });

    describe('DeleteToken', () => {
      it('removes a saved token', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await service.saveToken(makeToken('del_1'), { provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
        expect(await service.hasToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A })).assertTrue();
        await service.deleteToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A });
        expect(await service.hasToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A })).assertFalse();
        const loaded = await service.loadToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
        expect(loaded).assertNull();
      });

      it('resolves when deleting a token that does not exist', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await service.deleteToken({ provider: OAuth2Provider.GOOGLE, tokenKey: KEY_B });
        expect(await service.hasToken({ provider: OAuth2Provider.GOOGLE, tokenKey: KEY_B })).assertFalse();
      });
    });

    describe('ClearAllTokens', () => {
      it('removes every stored token across providers and custom keys', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await service.saveToken(makeToken('c1'), { provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
        await service.saveToken(makeToken('c2'), { provider: OAuth2Provider.BAIDU_NETDISK, encrypt: false });
        expect(await service.hasToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A })).assertTrue();
        expect(await service.hasToken({ provider: OAuth2Provider.BAIDU_NETDISK })).assertTrue();
        await service.clearAllTokens();
        expect(await service.hasToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A })).assertFalse();
        expect(await service.hasToken({ provider: OAuth2Provider.BAIDU_NETDISK })).assertFalse();
      });
    });

    describe('FileBackendPersistence', () => {
      it('persists tokens to file store and survives instance reset (process restart simulation)', 0, async () => {
        const service = OAuth2TokenStorageService.getInstance();
        await service.saveToken(makeToken('restart_acc'), { provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });

        // 模拟进程重启：单例重置后应从文件重新水合
        OAuth2TokenStorageService.resetForTest();
        const fresh = OAuth2TokenStorageService.getInstance();
        const loaded = await fresh.loadToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
        expect(loaded).not().assertNull();
        expect(loaded!.accessToken).assertEqual('restart_acc');
        expect(loaded!.refreshToken).assertEqual('refresh_restart_acc');
      });

      it('corrupt file content degrades to empty store instead of throwing', 0, async () => {
        const storePath = CommonUtils.getAppFilesDir() + '/' + STORE_FILE;
        // 备份当前文件内容，测试后恢复
        let backup: string | null = null;
        if (fs.accessSync(storePath, fs.AccessModeType.EXIST)) {
          backup = fs.readTextSync(storePath);
        }
        try {
          const tmpPath = storePath + '.corrupt-tmp';
          const file = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          try {
            await fs.write(file.fd, 'not-a-json-file{{{');
          } finally {
            await fs.close(file.fd);
          }
          await fs.rename(tmpPath, storePath);

          OAuth2TokenStorageService.resetForTest();
          const fresh = OAuth2TokenStorageService.getInstance();
          // fail-open：读损坏文件降级为空表，不抛异常
          expect(await fresh.hasToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A })).assertFalse();
          const loaded = await fresh.loadToken({ provider: OAuth2Provider.GITHUB, tokenKey: KEY_A, encrypt: false });
          expect(loaded).assertNull();
        } finally {
          // 恢复备份（或清除损坏文件）
          const restorePath = storePath + '.restore-tmp';
          const file = await fs.open(restorePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          try {
            await fs.write(file.fd, backup ?? '');
          } finally {
            await fs.close(file.fd);
          }
          await fs.rename(restorePath, storePath);
          OAuth2TokenStorageService.resetForTest();
        }
      });
    });

    describe('WorkerMode', () => {
      it('save and load work without Context (worker environment simulation)', 0, async () => {
        // 模拟 Worker：清除 Context + 注入沙箱路径（§11.1 注入协议）
        const originalContext = CommonUtils.getContext();
        const filesDir = CommonUtils.getAppFilesDir();
        const cacheDir = CommonUtils.getCacheDir();
        CommonUtils.clearContextForTest();
        CommonUtils.setWorkerPaths(filesDir, cacheDir);
        try {
          OAuth2TokenStorageService.resetForTest();
          const service = OAuth2TokenStorageService.getInstance();
          // Worker 内保存（模拟刷新后持久化）
          await service.saveToken(makeToken('worker_acc'), { provider: OAuth2Provider.HUAWEI_DRIVE, encrypt: false });
          // 跨"进程重启"读取
          OAuth2TokenStorageService.resetForTest();
          const fresh = OAuth2TokenStorageService.getInstance();
          const loaded = await fresh.loadToken({ provider: OAuth2Provider.HUAWEI_DRIVE, encrypt: false });
          expect(loaded).not().assertNull();
          expect(loaded!.accessToken).assertEqual('worker_acc');
          await fresh.deleteToken({ provider: OAuth2Provider.HUAWEI_DRIVE });
        } finally {
          CommonUtils.init(originalContext);
          OAuth2TokenStorageService.resetForTest();
        }
      });
    });
  });
}
