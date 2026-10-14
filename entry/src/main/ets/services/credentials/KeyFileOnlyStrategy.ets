import { KdbxCredentials } from 'kdbxweb';
import { AuthType, CredentialsParam } from '../TypeDefined';
import { CredentialsBuildStrategy } from './CredentialsBuildStrategy';
import { KeyFileReader } from './KeyFileReader';

/**
 * 仅密钥文件策略：不使用密码
 */
export class KeyFileOnlyStrategy implements CredentialsBuildStrategy {
  supports(param: CredentialsParam): boolean {
    return AuthType.isKeyfileOnly(param.authType);
  }

  async build(param: CredentialsParam): Promise<KdbxCredentials> {
    const keyFileContent = await KeyFileReader.requireAndRead(param, 'keyfile only');
    return new KdbxCredentials(null, keyFileContent);
  }
}
