import { ByteUtils, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { ResourceManager } from '../../common/utils';
import { AuthType, CredentialsParam } from '../TypeDefined';
import { CredentialsBuildStrategy } from './CredentialsBuildStrategy';

/**
 * OTP（OtpKeyProv）/恢复模式策略，及 KeeChallenge 旧版（P2，同以 secret 作为自定义密钥分量）：
 * secret 以 KcpCustomKey（bPerformHash=true）语义并入复合密钥
 */
export class OtpSecretStrategy implements CredentialsBuildStrategy {
  supports(param: CredentialsParam): boolean {
    return AuthType.useOtpAuth(param.authType) || AuthType.useChallengeAuth(param.authType);
  }

  async build(param: CredentialsParam): Promise<KdbxCredentials> {
    if (!param.otpSecretHex) {
      throw new Error(ResourceManager.getString($r('app.string.error_otp_secret_missing')));
    }
    return new KdbxCredentials(ProtectedValue.fromString(param.password), null, undefined,
      ByteUtils.hexToBytes(param.otpSecretHex));
  }
}
