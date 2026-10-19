import { describe, expect, it } from '@ohos/hypium';
import {
  AuthType,
  AuthTypeInfo,
  ExportType,
  FileContent,
  MoveParam
} from '../../../../main/ets/services/TypeDefined';

/**
 * TypeDefined 单元测试。
 *
 * 覆盖：ExportType 枚举、FileContent 载体、AuthType 认证方式注册表
 * （索引/类型查找、密钥文件/OTP/挑战-应答/恢复模式判定）与 MoveParam 移动参数。
 */
export default function TypeDefinedTest() {
  describe('TypeDefinedTest', () => {
    it('ExportType exposes the four export kinds', 0, () => {
      expect(ExportType.KDBX).assertEqual('KDBX');
      expect(ExportType.XML).assertEqual('XML');
      expect(ExportType.CSV).assertEqual('CSV');
      expect(ExportType.CREATE_KEY).assertEqual('CREATE_KEY');
    });

    it('FileContent carries path and content', 0, () => {
      const content = new FileContent('/tmp/a.kdbx', new ArrayBuffer(8));
      expect(content.filePath).assertEqual('/tmp/a.kdbx');
      expect(content.content.byteLength).assertEqual(8);
    });

    it('AuthType statics expose stable type identifiers', 0, () => {
      expect(AuthType.PASSWORD.type).assertEqual('password');
      expect(AuthType.PASSWORD_KEYFILE.type).assertEqual('password_keyfile');
      expect(AuthType.KEYFILE.type).assertEqual('keyfile');
      expect(AuthType.PASSWORD_OTP.type).assertEqual('password_otp');
      expect(AuthType.PASSWORD_OTP_RECOVERY.type).assertEqual('password_otp_recovery');
      expect(AuthType.PASSWORD_CHALLENGE_RESPONSE.type).assertEqual('password_challenge_response');
      expect(AuthType.PASSWORD_CHALLENGE_RESPONSE_RECOVERY.type).assertEqual('password_challenge_response_recovery');
      expect(AuthType.PASSWORD_CHALLENGE_RESPONSE_XC.type).assertEqual('password_challenge_response_xc');
      expect(AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type).assertEqual('password_keyfile_challenge_response_xc');
    });

    it('getAllTypes returns the 7 enabled auth kinds starting with PASSWORD', 0, () => {
      const types = AuthType.getAllTypes();
      expect(types.length).assertEqual(7);
      expect(types[0].type).assertEqual(AuthType.PASSWORD.type);
      expect(types[6].type).assertEqual(AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type);
    });

    it('getIndexByType maps known types and rejects unknown ones', 0, () => {
      expect(AuthType.getIndexByType('password')).assertEqual(0);
      expect(AuthType.getIndexByType('keyfile')).assertEqual(1);
      expect(AuthType.getIndexByType('password_keyfile')).assertEqual(2);
      expect(AuthType.getIndexByType('password_keyfile_challenge_response_xc')).assertEqual(6);
      expect(AuthType.getIndexByType('unknown_type')).assertEqual(-1);
      // 未在 getAllTypes 中启用的旧版挑战-应答不可索引
      expect(AuthType.getIndexByType('password_challenge_response')).assertEqual(-1);
    });

    it('getByIndex returns the type at index and falls back to PASSWORD for invalid indexes', 0, () => {
      expect(AuthType.getByIndex(0).type).assertEqual('password');
      expect(AuthType.getByIndex(6).type).assertEqual('password_keyfile_challenge_response_xc');
      expect(AuthType.getByIndex(-1).type).assertEqual('password');
      expect(AuthType.getByIndex(999).type).assertEqual('password');
    });

    it('getByType resolves known types and falls back to PASSWORD', 0, () => {
      expect(AuthType.getByType('keyfile').type).assertEqual('keyfile');
      expect(AuthType.getByType('no_such_type').type).assertEqual('password');
    });

    it('useKeyAuth is true only for keyfile-carrying kinds', 0, () => {
      expect(AuthType.useKeyAuth(AuthType.PASSWORD_KEYFILE)).assertTrue();
      expect(AuthType.useKeyAuth(AuthType.KEYFILE)).assertTrue();
      expect(AuthType.useKeyAuth(AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.useKeyAuth(AuthType.PASSWORD)).assertFalse();
      expect(AuthType.useKeyAuth(AuthType.PASSWORD_OTP)).assertFalse();
    });

    it('isKeyfileOnly is true only for the keyfile-only kind', 0, () => {
      expect(AuthType.isKeyfileOnly(AuthType.KEYFILE)).assertTrue();
      expect(AuthType.isKeyfileOnly(AuthType.PASSWORD_KEYFILE)).assertFalse();
      expect(AuthType.isKeyfileOnly(AuthType.PASSWORD)).assertFalse();
    });

    it('needPassword is true for all password-carrying kinds and false for keyfile-only', 0, () => {
      expect(AuthType.needPassword(AuthType.PASSWORD)).assertTrue();
      expect(AuthType.needPassword(AuthType.PASSWORD_KEYFILE)).assertTrue();
      expect(AuthType.needPassword(AuthType.PASSWORD_OTP)).assertTrue();
      expect(AuthType.needPassword(AuthType.PASSWORD_OTP_RECOVERY)).assertTrue();
      expect(AuthType.needPassword(AuthType.PASSWORD_CHALLENGE_RESPONSE)).assertTrue();
      expect(AuthType.needPassword(AuthType.PASSWORD_CHALLENGE_RESPONSE_RECOVERY)).assertTrue();
      expect(AuthType.needPassword(AuthType.PASSWORD_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.needPassword(AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.needPassword(AuthType.KEYFILE)).assertFalse();
    });

    it('useOtpAuth is true for OTP and its recovery mode only', 0, () => {
      expect(AuthType.useOtpAuth(AuthType.PASSWORD_OTP)).assertTrue();
      expect(AuthType.useOtpAuth(AuthType.PASSWORD_OTP_RECOVERY)).assertTrue();
      expect(AuthType.useOtpAuth(AuthType.PASSWORD)).assertFalse();
      expect(AuthType.useOtpAuth(AuthType.PASSWORD_CHALLENGE_RESPONSE_XC)).assertFalse();
    });

    it('useChallengeAuth covers legacy, XC and keyfile+XC kinds', 0, () => {
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD_CHALLENGE_RESPONSE)).assertTrue();
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD_CHALLENGE_RESPONSE_RECOVERY)).assertTrue();
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.useChallengeAuth(AuthType.PASSWORD)).assertFalse();
    });

    it('useChallengeResponseXc is true only for XC-compatible kinds', 0, () => {
      expect(AuthType.useChallengeResponseXc(AuthType.PASSWORD_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.useChallengeResponseXc(AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC)).assertTrue();
      expect(AuthType.useChallengeResponseXc(AuthType.PASSWORD_CHALLENGE_RESPONSE)).assertFalse();
    });

    it('isRecoveryMode is true for OTP/challenge recovery kinds', 0, () => {
      expect(AuthType.isRecoveryMode(AuthType.PASSWORD_OTP_RECOVERY)).assertTrue();
      expect(AuthType.isRecoveryMode(AuthType.PASSWORD_CHALLENGE_RESPONSE_RECOVERY)).assertTrue();
      expect(AuthType.isRecoveryMode(AuthType.PASSWORD_OTP)).assertFalse();
      expect(AuthType.isRecoveryMode(AuthType.PASSWORD)).assertFalse();
    });

    it('auth kinds expose a localized resource value', 0, () => {
      const kinds: AuthTypeInfo[] = AuthType.getAllTypes();
      for (let i = 0; i < kinds.length; i++) {
        expect(kinds[i].value !== undefined).assertTrue();
      }
    });

    it('MoveParam create/getInstance/clearInstance lifecycle', 0, () => {
      MoveParam.clearInstance();
      expect(MoveParam.getInstance()).assertUndefined();
      const param = MoveParam.create(['e1', 'e2'], ['g1'], 'src-group');
      expect(MoveParam.getInstance() === param).assertTrue();
      MoveParam.clearInstance();
      expect(MoveParam.getInstance()).assertUndefined();
    });

    it('MoveParam isMoveItem matches entries and groups', 0, () => {
      const param = MoveParam.create(['e1', 'e2'], ['g1'], 'src');
      expect(param.isMoveItem('e1')).assertTrue();
      expect(param.isMoveItem('e2')).assertTrue();
      expect(param.isMoveItem('g1')).assertTrue();
      expect(param.isMoveItem('other')).assertFalse();
    });

    it('MoveParam hasGroupMove/hasEntryMove reflect payload presence', 0, () => {
      const both = MoveParam.create(['e1'], ['g1'], 'src');
      expect(both.hasEntryMove).assertTrue();
      expect(both.hasGroupMove).assertTrue();
      const groupOnly = MoveParam.create([], ['g1'], 'src');
      expect(groupOnly.hasEntryMove).assertFalse();
      expect(groupOnly.hasGroupMove).assertTrue();
      const entryOnly = MoveParam.create(['e1'], [], 'src');
      expect(entryOnly.hasEntryMove).assertTrue();
      expect(entryOnly.hasGroupMove).assertFalse();
    });
  });
}
