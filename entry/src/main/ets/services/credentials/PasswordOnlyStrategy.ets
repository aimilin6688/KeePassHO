import { KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { CredentialsParam } from '../TypeDefined';
import { CredentialsBuildStrategy } from './CredentialsBuildStrategy';

/**
 * 仅密码策略（兜底：未匹配到其他认证方式时按密码构建）
 */
export class PasswordOnlyStrategy implements CredentialsBuildStrategy {
  supports(_param: CredentialsParam): boolean {
    return true;
  }

  async build(param: CredentialsParam): Promise<KdbxCredentials> {
    return new KdbxCredentials(ProtectedValue.fromString(param.password));
  }
}
