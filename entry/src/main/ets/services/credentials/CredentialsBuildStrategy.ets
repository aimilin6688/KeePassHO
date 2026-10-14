import { KdbxCredentials } from 'kdbxweb';
import { CredentialsParam } from '../TypeDefined';

/**
 * 凭证构建策略：每种认证方式一种实现，新增认证方式时新增实现类并注册到 CredentialsService
 */
export interface CredentialsBuildStrategy {
  /**
   * 是否支持该认证方式
   */
  supports(param: CredentialsParam): boolean;

  /**
   * 构建凭证
   * @throws Error 缺少必要参数时抛出
   */
  build(param: CredentialsParam): Promise<KdbxCredentials>;
}
