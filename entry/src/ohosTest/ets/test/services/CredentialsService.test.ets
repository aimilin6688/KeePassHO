import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { CredentialsService } from '../../../../main/ets/services/CredentialsService';
import { ByteUtils } from 'kdbxweb';
import { AuthTypeInfo, AuthType, CredentialsParam } from '../../../../main/ets/services/TypeDefined';
import { LoadDatabase } from '../../../../main/ets/workers/DatabaseLoadWorkerParam';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { ResourceManager } from '../../../../main/ets/common/utils/ResourceManager';

function nullishAuthType(): AuthTypeInfo | null {
  return null;
}

export default function CredentialsServiceTest() {
  describe('CredentialsService', () => {
    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      ResourceManager.getInstance().init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('createKdbxCredentials builds credentials for password-only auth type', 0, async () => {
      const param: CredentialsParam = {
        password: 'secret123',
        authType: AuthType.PASSWORD
      };
      const credentials = await CredentialsService.createKdbxCredentials(param);
      expect(credentials !== null && credentials !== undefined).assertTrue();
    });

    it('createKdbxCredentials builds credentials with empty password for password-only', 0, async () => {
      const param: CredentialsParam = {
        password: '',
        authType: AuthType.PASSWORD
      };
      const credentials = await CredentialsService.createKdbxCredentials(param);
      expect(credentials !== null && credentials !== undefined).assertTrue();
    });

    it('createKdbxCredentials throws when keyfile-only auth missing keyLocation', 0, async () => {
      const param: CredentialsParam = {
        password: '',
        authType: AuthType.KEYFILE
      };
      let threw = false;
      let errMsg = '';
      try {
        await CredentialsService.createKdbxCredentials(param);
      } catch (e) {
        threw = true;
        errMsg = (e as Error).message;
      }
      expect(threw).assertTrue();
      expect(errMsg.length > 0).assertTrue();
    });

    it('createKdbxCredentials throws when password+keyfile auth missing keyLocation', 0, async () => {
      const param: CredentialsParam = {
        password: 'pw',
        authType: AuthType.PASSWORD_KEYFILE
      };
      let threw = false;
      try {
        await CredentialsService.createKdbxCredentials(param);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('AuthType.useKeyAuth is true for PASSWORD_KEYFILE and KEYFILE', 0, () => {
      expect(AuthType.useKeyAuth(AuthType.PASSWORD_KEYFILE)).assertTrue();
      expect(AuthType.useKeyAuth(AuthType.KEYFILE)).assertTrue();
    });

    it('AuthType.useKeyAuth is false for PASSWORD', 0, () => {
      expect(AuthType.useKeyAuth(AuthType.PASSWORD)).assertFalse();
    });

    it('AuthType.isKeyfileOnly is true only for KEYFILE', 0, () => {
      expect(AuthType.isKeyfileOnly(AuthType.KEYFILE)).assertTrue();
      expect(AuthType.isKeyfileOnly(AuthType.PASSWORD)).assertFalse();
      expect(AuthType.isKeyfileOnly(AuthType.PASSWORD_KEYFILE)).assertFalse();
    });

    it('AuthType.isKeyfileOnly returns false for a nullish authType', 0, () => {
      expect(AuthType.isKeyfileOnly(nullishAuthType() as AuthTypeInfo)).assertFalse();
    });

    it('AuthType.useKeyAuth returns false for a nullish authType', 0, () => {
      expect(AuthType.useKeyAuth(nullishAuthType() as AuthTypeInfo)).assertFalse();
    });

    it('AuthType.useOtpAuth is true only for OTP types', 0, () => {
      expect(AuthType.useOtpAuth(AuthType.PASSWORD_OTP)).assertTrue();
      expect(AuthType.useOtpAuth(AuthType.PASSWORD_OTP_RECOVERY)).assertTrue();
      expect(AuthType.useOtpAuth(AuthType.PASSWORD)).assertFalse();
      expect(AuthType.useOtpAuth(AuthType.KEYFILE)).assertFalse();
      expect(AuthType.useOtpAuth(AuthType.PASSWORD_KEYFILE)).assertFalse();
      expect(AuthType.useOtpAuth(AuthType.PASSWORD_CHALLENGE_RESPONSE)).assertFalse();
      expect(AuthType.useOtpAuth(AuthType.PASSWORD_CHALLENGE_RESPONSE_XC)).assertFalse();
      expect(AuthType.useOtpAuth(AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC)).assertFalse();
    });

    it('AuthType.useChallengeAuth is true for all challenge types', 0, () => {
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD_CHALLENGE_RESPONSE)).assertTrue();
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD_CHALLENGE_RESPONSE_RECOVERY)).assertTrue();
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD)).assertFalse();
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD_OTP)).assertFalse();
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD_KEYFILE)).assertFalse();
    });

    it('AuthType.useChallengeResponseXc is true only for XC types', 0, () => {
      expect(AuthType.useChallengeResponseXc(AuthType.PASSWORD_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.useChallengeResponseXc(AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.useChallengeResponseXc(AuthType.PASSWORD_CHALLENGE_RESPONSE)).assertFalse();
      expect(AuthType.useChallengeResponseXc(AuthType.PASSWORD_CHALLENGE_RESPONSE_RECOVERY)).assertFalse();
      expect(AuthType.useChallengeResponseXc(AuthType.PASSWORD)).assertFalse();
      expect(AuthType.useChallengeResponseXc(AuthType.PASSWORD_OTP)).assertFalse();
    });

    it('AuthType.isRecoveryMode is true only for recovery types', 0, () => {
      expect(AuthType.isRecoveryMode(AuthType.PASSWORD_OTP_RECOVERY)).assertTrue();
      expect(AuthType.isRecoveryMode(AuthType.PASSWORD_CHALLENGE_RESPONSE_RECOVERY)).assertTrue();
      expect(AuthType.isRecoveryMode(AuthType.PASSWORD_OTP)).assertFalse();
      expect(AuthType.isRecoveryMode(AuthType.PASSWORD_CHALLENGE_RESPONSE_XC)).assertFalse();
      expect(AuthType.isRecoveryMode(AuthType.PASSWORD)).assertFalse();
    });

    it('AuthType new helpers return false for a nullish authType', 0, () => {
      expect(AuthType.useOtpAuth(nullishAuthType() as AuthTypeInfo)).assertFalse();
      expect(AuthType.useChallengeAuth(nullishAuthType() as AuthTypeInfo)).assertFalse();
      expect(AuthType.useChallengeResponseXc(nullishAuthType() as AuthTypeInfo)).assertFalse();
      expect(AuthType.isRecoveryMode(nullishAuthType() as AuthTypeInfo)).assertFalse();
    });

    it('createKdbxCredentials builds OTP credentials with customKey component', 0, async () => {
      const param: CredentialsParam = {
        password: 'test',
        authType: AuthType.PASSWORD_OTP,
        otpSecretHex: '03'.repeat(32)
      };
      const credentials = await CredentialsService.createKdbxCredentials(param);
      const hash = await credentials.getHash();
      // SHA256(SHA256('test') || SHA256(0x03 x 32))，与 KdbxCredentialsCustomKey 密码+customKey 向量一致
      expect(ByteUtils.bytesToHex(hash)).assertEqual(
        '89f0e9a585052c047d768a5cc7df32a5383d3d4790b3793f145e3068197bbd2d'
      );
    });

    it('createKdbxCredentials throws when OTP auth missing otpSecretHex', 0, async () => {
      const param: CredentialsParam = {
        password: 'test',
        authType: AuthType.PASSWORD_OTP
      };
      let threw = false;
      let errMsg = '';
      try {
        await CredentialsService.createKdbxCredentials(param);
      } catch (e) {
        threw = true;
        errMsg = (e as Error).message;
      }
      expect(threw).assertTrue();
      expect(errMsg.length > 0).assertTrue();
    });

    it('createKdbxCredentials builds XC challenge credentials with fixed response', 0, async () => {
      const param: CredentialsParam = {
        password: 'test',
        authType: AuthType.PASSWORD_CHALLENGE_RESPONSE_XC,
        challengeResponseHex: '11'.repeat(20)
      };
      const credentials = await CredentialsService.createKdbxCredentials(param);
      // 固定应答回调：任意 challenge 均返回预计算应答（kdbxweb 再 SHA-256 并入复合密钥）
      const hash = await credentials.getHash(new ArrayBuffer(8));
      // SHA256(SHA256('test') || SHA256(0x11 x 20))
      expect(ByteUtils.bytesToHex(hash)).assertEqual(
        '1be3b3321c5fe8e774cf6fc7bcf045848c8207d6fd4cf0bbd6aae1daa0c2b328'
      );
      // 二次调用结果一致：回调返回副本，不被 kdbxweb zeroBuffer 清零影响
      const hashAgain = await credentials.getHash(new ArrayBuffer(8));
      expect(ByteUtils.bytesToHex(hashAgain)).assertEqual(
        '1be3b3321c5fe8e774cf6fc7bcf045848c8207d6fd4cf0bbd6aae1daa0c2b328'
      );
    });

    it('createKdbxCredentials throws when XC challenge missing challengeResponseHex', 0, async () => {
      const param: CredentialsParam = {
        password: 'test',
        authType: AuthType.PASSWORD_CHALLENGE_RESPONSE_XC
      };
      let threw = false;
      try {
        await CredentialsService.createKdbxCredentials(param);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('createKdbxCredentials throws for legacy KeeChallenge without secret (M5 placeholder)', 0, async () => {
      const param: CredentialsParam = {
        password: 'test',
        authType: AuthType.PASSWORD_CHALLENGE_RESPONSE
      };
      let threw = false;
      try {
        await CredentialsService.createKdbxCredentials(param);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('LoadDatabase new credential fields survive worker JSON channel', 0, () => {
      const loadDatabase = new LoadDatabase('/path/db.kdbx', 'db.kdbx', 'test', AuthType.PASSWORD_OTP);
      expect(loadDatabase.otpSecretHex).assertUndefined();
      loadDatabase.otpSecretHex = 'aabbccdd';
      loadDatabase.challengeResponseHex = '11223344';
      const parsed = JSON.parse(JSON.stringify(loadDatabase)) as LoadDatabase;
      expect(parsed.otpSecretHex).assertEqual('aabbccdd');
      expect(parsed.challengeResponseHex).assertEqual('11223344');
      // 未赋值字段序列化自动丢弃：全新构造消息不携带该字段
      const fresh = new LoadDatabase('/path/db.kdbx', 'db.kdbx', 'test', AuthType.PASSWORD);
      const parsedFresh = JSON.parse(JSON.stringify(fresh)) as LoadDatabase;
      expect(parsedFresh.otpSecretHex).assertUndefined();
      expect(parsedFresh.challengeResponseHex).assertUndefined();
    });
  });
}
