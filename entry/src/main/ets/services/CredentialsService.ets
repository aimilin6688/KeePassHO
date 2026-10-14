import { KdbxCredentials } from 'kdbxweb';
import { CredentialsParam } from './TypeDefined';
import { CredentialsBuildStrategy } from './credentials/CredentialsBuildStrategy';
import { ChallengeResponseXcStrategy } from './credentials/ChallengeResponseXcStrategy';
import { OtpSecretStrategy } from './credentials/OtpSecretStrategy';
import { KeyFileOnlyStrategy } from './credentials/KeyFileOnlyStrategy';
import { PasswordKeyFileStrategy } from './credentials/PasswordKeyFileStrategy';
import { PasswordOnlyStrategy } from './credentials/PasswordOnlyStrategy';

/**
 * 凭证服务：按注册顺序遍历构建策略，首个支持该认证方式的策略负责构建
 */
export class CredentialsService {
  /**
   * 构建策略注册表（顺序即分派优先级，兜底策略置末）
   */
  private static readonly strategies: CredentialsBuildStrategy[] = [
    new ChallengeResponseXcStrategy(),
    new OtpSecretStrategy(),
    new KeyFileOnlyStrategy(),
    new PasswordKeyFileStrategy(),
    new PasswordOnlyStrategy()
  ];

  /**
   * 创建凭证
   * @param param 请求
   * @return Promise<KdbxCredentials> 凭证
   * @throws Error 错误
   */
  public static async createKdbxCredentials(param: CredentialsParam): Promise<KdbxCredentials> {
    for (const strategy of CredentialsService.strategies) {
      if (strategy.supports(param)) {
        return strategy.build(param);
      }
    }
    throw new Error('No credentials build strategy matched');
  }
}
