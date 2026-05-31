import { TestStorageConfig } from '../TestStorageConfig';

/**
 * pCloud 测试公共配置
 *
 * 使用方式和 S3TestConfig 完全一致：
 * 硬编码真实凭据，凭据失效测试就会失败。
 *
 * pCloud 的 access_token 持续使用会自动延长 expire_inactive，
 * 只要测试定期运行，token 不会因为不活跃而过期。
 * 如果收到 1000 错误码（需要登录），说明 expire 绝对过期时间到了，
 * 需要重新走 OAuth2 流程获取新 token。
 */
export class PCloudTestConfig extends TestStorageConfig {
  /**
   * 测试用 access_token
   * 通过 pCloud OAuth2 授权码流程获取
   * 如果不填或过期，集成测试会失败——这是正确的行为
   */
  static readonly PCLOUD_TEST_ACCESS_TOKEN: string = '';

  /** 测试 API 端点 */
  static readonly API_BASE_URL: string = 'https://api.pcloud.com';

  /** 根目录文件夹 ID */
  static readonly ROOT_FOLDER_ID: string = 'd0';

  /** 测试超时（毫秒） */
  static readonly TIMEOUT: number = 30000;

  /**
   * 获取用于 init PCloudStorage 的测试配置
   */
  static createStorageConfig(): PCloudStorageTestConfig {
    return new PCloudStorageTestConfig(PCloudTestConfig.PCLOUD_TEST_ACCESS_TOKEN);
  }
}

/**
 * 测试用 pCloud 存储配置
 * 明文存储 access_token，避免 SM4 加密依赖
 */
export class PCloudStorageTestConfig {
  accessToken: string = '';
  timeout: number = PCloudTestConfig.TIMEOUT;

  constructor(accessToken: string) {
    this.accessToken = accessToken;
  }

  getAccessTokenText(): string {
    return this.accessToken;
  }

  get expireAt(): number {
    return 0;
  }
}
