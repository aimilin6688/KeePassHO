import { KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { AuthType, CredentialsParam } from '../TypeDefined';
import { CredentialsBuildStrategy } from './CredentialsBuildStrategy';
import { KeyFileReader } from './KeyFileReader';

/**
 * 密码 + 密钥文件策略
 */
export class PasswordKeyFileStrategy implements CredentialsBuildStrategy {
  supports(param: CredentialsParam): boolean {
    return AuthType.useKeyAuth(param.authType);
  }

  async build(param: CredentialsParam): Promise<KdbxCredentials> {
    const keyFileContent = await KeyFileReader.requireAndRead(param, 'password + keyfile');
    return new KdbxCredentials(ProtectedValue.fromString(param.password), keyFileContent);
  }
}
