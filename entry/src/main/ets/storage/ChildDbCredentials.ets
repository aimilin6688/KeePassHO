import { Sm4Utils } from '../common/utils/Sm4Utils';
import { IocCredentials } from './ChildDbSupport';
import { StorageConfig } from './StorageConfig';

/**
 * 子库连接凭据提取共享助手（各凭据型适配器 extractCredentials 共用）
 */
export class ChildDbCredentials {
  /**
   * 从 storageConfig（类实例或 plain JSON 同名字段——RecentFile 往返后为
   * plain JSON）按加密字段名解密提取连接凭据：
   * 字段缺失或解密失败（SM4 密钥变更/密文损坏）返回 undefined，调用方跳过写入。
   */
  public static fromEncryptedFields(config: StorageConfig, userKey: string, passwordKey: string): IocCredentials | undefined {
    try {
      const record = config as Record<string, Object>;
      const userName: Object | undefined = record[userKey];
      const password: Object | undefined = record[passwordKey];
      if (userName === undefined || password === undefined) {
        return undefined;
      }
      return new IocCredentials(Sm4Utils.tryDecryptWithPrefix(String(userName)), Sm4Utils.tryDecryptWithPrefix(String(password)));
    } catch (error) {
      return undefined;
    }
  }
}
