import { StorageConfig } from '../../../../../main/ets/storage/StorageConfig';

/**
 * 华为云盘测试公共配置
 * 包含测试所需的端点、凭证和测试数据
 */
export class HuaweiDriveTestConfig {
  /**
   * 华为云盘API基础URL
   */
  static readonly API_BASE_URL: string = 'https://drive.cloud.huawei.com/drive/v1';

  /**
   * OAuth2 端点
   */
  static readonly OAUTH_AUTHORIZATION_ENDPOINT: string = 'https://oauth-login.cloud.huawei.com/oauth2/v3/authorize';
  static readonly OAUTH_TOKEN_ENDPOINT: string = 'https://oauth-login.cloud.huawei.com/oauth2/v3/token';

  /**
   * 测试用客户端ID
   * 注意：实际测试时需要替换为真实的客户端ID
   */
  static readonly CLIENT_ID: string = 'test_client_id';

  /**
   * 测试用客户端密钥
   * 注意：实际测试时需要替换为真实的客户端密钥
   */
  static readonly CLIENT_SECRET: string = 'test_client_secret';

  /**
   * 测试用重定向URI
   */
  static readonly REDIRECT_URI: string = 'com.keepassho:/oauth2redirect';

  /**
   * 测试用访问令牌
   */
  static readonly ACCESS_TOKEN: string = 'test_access_token_12345';

  /**
   * 测试用刷新令牌
   */
  static readonly REFRESH_TOKEN: string = 'test_refresh_token_67890';

  /**
   * 测试用文件ID
   */
  static readonly TEST_FILE_ID: string = 'test_file_id_123';

  /**
   * 测试用文件夹ID（根目录）
   */
  static readonly TEST_FOLDER_ID: string = 'root';

  /**
   * 测试路径数组 - 包含中文路径、多级目录等场景
   */
  static readonly TEST_FILE_NAMES: string[] = [
    'test-1.kdbx',                           // 根目录文件
    '密码库/test-1.kdbx',                     // 中文目录
    'folder1/folder2/test-1.kdbx',            // 多级目录
    '我的密码/工作账号/test-1.kdbx',           // 中文多级目录
    'test-folder/special_123/test-1.kdbx'     // 混合路径
  ];

  /**
   * 超时时间（毫秒）
   */
  static readonly TIMEOUT: number = 30000;

  /**
   * 授权范围
   */
  static readonly SCOPE_FULL: string = 'https://www.huawei.com/auth/drive';
  static readonly SCOPE_APP_FILE: string = 'https://www.huawei.com/auth/drive.file';

  /**
   * 获取存储配置对象（用于 HuaweiDriveStorage.init）
   * 注意：返回一个模拟的 HuaweiDriveStorageConfig，避免触发 SM4 加密
   */
  static getStorageConfig(): TestHuaweiDriveStorageConfig {
    return new TestHuaweiDriveStorageConfig(
      HuaweiDriveTestConfig.ACCESS_TOKEN,
      HuaweiDriveTestConfig.REFRESH_TOKEN,
      Date.now() + 3600000, // 1小时后过期
      {
        timeout: HuaweiDriveTestConfig.TIMEOUT,
        scope: HuaweiDriveTestConfig.SCOPE_FULL
      }
    );
  }
}

/**
 * 测试用华为云盘存储配置类
 * 直接存储明文凭证，避免 SM4 加密依赖
 */
export class TestHuaweiDriveStorageConfig implements StorageConfig {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  timeout?: number;
  tokenType?: string;
  scope?: string;

  constructor(
    accessToken: string,
    refreshToken: string,
    expiresAt: number,
    options?: {
      timeout?: number;
      tokenType?: string;
      scope?: string;
    }
  ) {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    this.expiresAt = expiresAt;
    this.timeout = options?.timeout;
    this.tokenType = options?.tokenType;
    this.scope = options?.scope;
  }

  /**
   * 返回明文访问令牌
   */
  public getAccessTokenText(): string {
    return this.accessToken;
  }

  /**
   * 返回明文刷新令牌
   */
  public getRefreshTokenText(): string {
    return this.refreshToken;
  }

  /**
   * 检查令牌是否过期
   */
  public isTokenExpired(): boolean {
    if (!this.expiresAt) {
      return false;
    }
    // 提前5分钟认为令牌过期
    return Date.now() > this.expiresAt - 5 * 60 * 1000;
  }
}
