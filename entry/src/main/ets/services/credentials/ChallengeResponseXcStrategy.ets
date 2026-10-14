import { ByteUtils, KdbxChallengeResponseFn, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { ResourceManager } from '../../common/utils';
import { AuthType, CredentialsParam } from '../TypeDefined';
import { CredentialsBuildStrategy } from './CredentialsBuildStrategy';
import { KeyFileReader } from './KeyFileReader';

/**
 * KeePassXC 兼容挑战-应答策略：主线程已预计算应答，以固定应答回调组装
 * （kdbxweb 加载时对 KDF seed 调用回调，对返回值 SHA-256 后并入复合密钥）
 */
export class ChallengeResponseXcStrategy implements CredentialsBuildStrategy {
  supports(param: CredentialsParam): boolean {
    return AuthType.useChallengeResponseXc(param.authType);
  }

  async build(param: CredentialsParam): Promise<KdbxCredentials> {
    if (!param.challengeResponseHex) {
      throw new Error(ResourceManager.getString($r('app.string.error_challenge_response_missing')));
    }
    const responseBytes: Uint8Array = ByteUtils.hexToBytes(param.challengeResponseHex);
    // 每次调用返回副本：kdbxweb 哈希后会 zeroBuffer 清零返回的缓冲
    const fixedResponse: KdbxChallengeResponseFn = (_challenge: ArrayBuffer) => {
      const copy: Uint8Array = new Uint8Array(responseBytes.length);
      copy.set(responseBytes);
      return Promise.resolve(copy);
    };
    if (AuthType.useKeyAuth(param.authType)) {
      // 密码 + 密钥文件 + 挑战-应答（XC）
      const keyFileContent = await KeyFileReader.requireAndRead(param, 'challenge-response xc');
      return new KdbxCredentials(ProtectedValue.fromString(param.password), keyFileContent, fixedResponse);
    }
    // 密码 + 挑战-应答（XC）
    return new KdbxCredentials(ProtectedValue.fromString(param.password), null, fixedResponse);
  }
}
