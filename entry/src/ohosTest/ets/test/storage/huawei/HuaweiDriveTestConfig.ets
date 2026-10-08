import { StorageConfig } from '../../../../../main/ets/storage/StorageConfig';

export class TestConfigOptions {
  timeout?: number;
  tokenType?: string;
  scope?: string;
}

/**
 * 华为云盘测试公共配置
 * 包含测试所需的端点、凭证和测试数据
 */
export class HuaweiDriveTestConfig {
  /**
   * 华为云盘API基础URL
   * 全球域名: https://driveapis.cloud.huawei.com.cn/drive/v1
   * 站点域名（需要加 /drive/v1 前缀）:
   * 中国站点：https://drive-drcn.cloud.dbankcloud.cn/drive/v1
   * 欧洲站点：https://drive-dre.cloud.dbankcloud.cn/drive/v1
   * 亚非拉站点：https://drive-dra.cloud.dbankcloud.cn/drive/v1
   * 俄罗斯站点：https://drive-drru.cloud.dbankcloud.cn/drive/v1
   */
  static readonly API_BASE_URL: string = 'https://driveapis.cloud.huawei.com.cn/drive/v1';

  /**
   * OAuth2 端点
   */
  static readonly OAUTH_AUTHORIZATION_ENDPOINT: string = 'https://oauth-login.cloud.huawei.com/oauth2/v3/authorize';
  static readonly OAUTH_TOKEN_ENDPOINT: string = 'https://oauth-login.cloud.huawei.com/oauth2/v3/token';

   /**
    * 测试用客户端ID
    * 注意：实际测试时需要替换为真实的客户端ID
   */
  static readonly CLIENT_ID: string = '119166997';

  /**
   * 测试用客户端密钥
   * 真实回归时填入有效密钥；为空时真实 API 用例不注册（见 isRealApiEnabled）
   */
  static readonly CLIENT_SECRET: string = '';

  /**
   * 测试用重定向URI
   */
  static readonly REDIRECT_URI: string = 'http://aimilin.com/huawei/redirect';

  /**
   * 测试用访问令牌
   * 通过 OAuth2 授权流程获取（见下方 AUTHORIZATION_CODE 说明）。
   * 为空时真实 API 用例不注册（见 isRealApiEnabled 与 docs/storage-regression-test.md）
   */
  static readonly ACCESS_TOKEN: string = '';

  /**
   * 测试用刷新令牌
   * 为空时刷新令牌用例不注册
   */
  static readonly REFRESH_TOKEN: string = '';

  /**
   * 是否启用真实 API 用例。
   * 华为云盘为专有云服务，无法本地自建；未配置有效凭证时，
   * 相关真实 API 用例整体不注册（诚实跳过，而非用 mock 数据伪造通过）。
   */
  static isRealApiEnabled(): boolean {
    return HuaweiDriveTestConfig.ACCESS_TOKEN.length > 0;
  }

  /**
   * 是否启用 resume 断点续传大文件用例（>20M 上传，单次全量运行约产生 60M+ 流量）。
   * 依赖真实凭证（isRealApiEnabled）；无需大流量回归时可置 false 跳过。
   */
  static readonly ENABLE_RESUME_UPLOAD_TESTS: boolean = true;

  /**
   * resume 断点续传用例是否注册：需同时配置有效凭证且显式启用大文件用例
   */
  static isResumeUploadTestEnabled(): boolean {
    return HuaweiDriveTestConfig.isRealApiEnabled() && HuaweiDriveTestConfig.ENABLE_RESUME_UPLOAD_TESTS;
  }

  /**
   * 测试用文件ID
   */
  static readonly TEST_FILE_ID: string = '';

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
   * 授权请求使用的 scope。
   * 文档要求：scope 是空格分隔的字符串数组，必须包含 "openid"。
   * 示例：'openid https://www.huawei.com/auth/drive'
   */
  static readonly SCOPE_AUTH: string = 'openid https://www.huawei.com/auth/drive';

  /**
   * 授权码（一次性）。
   * 运行 should_generate_auth_url 这类用例后会打印出授权 URL，
   * 浏览器打开授权后，把重定向 URL 中 code= 的值填入此处再运行换取 Token 的用例。
   * 注意：授权码是一次性的，且短时效。
   */
  static readonly AUTHORIZATION_CODE: string = '';

  /**
   * 获取存储配置对象（用于 HuaweiDriveStorage.init）
   * 注意：返回一个模拟的 HuaweiDriveStorageConfig，避免触发 SM4 加密
   */
  static getStorageConfig(): TestHuaweiDriveStorageConfig {
    const options = new TestConfigOptions();
    options.timeout = HuaweiDriveTestConfig.TIMEOUT;
    options.scope = HuaweiDriveTestConfig.SCOPE_FULL;
    return new TestHuaweiDriveStorageConfig(
      HuaweiDriveTestConfig.ACCESS_TOKEN,
      HuaweiDriveTestConfig.REFRESH_TOKEN,
      Date.now() + 3600000, // 1小时后过期
      options
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
    options?: TestConfigOptions
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
