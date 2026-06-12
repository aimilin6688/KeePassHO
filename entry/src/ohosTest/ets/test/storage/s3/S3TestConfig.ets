import { S3ClientOptionsImpl } from '../../../../../main/ets/storage/s3/S3Client';

/**
 * S3 测试公共配置
 * 包含测试所需的端点、凭证和测试数据
 */
export class S3TestConfig {
  /**
   * S3 兼容服务端点（腾讯云 COS）
   * 注意：对于虚拟主机风格，endpoint 不包含 bucket 名
   */
  static readonly ENDPOINT: string = 'https://cos.ap-beijing.myqcloud.com';

  /**
   * Access Key ID
   */
  static readonly ACCESS_KEY_ID: string = 'AKIDicLtENK3Zs0vd7QZVGrGQN9vWvCKH2Zu';

  /**
   * Secret Access Key
   */
  static readonly SECRET_ACCESS_KEY: string = 'DIApJ6pTzMZtDUcdfGnBOSOAnFYjjYEh';

  /**
   * 区域
   */
  static readonly REGION: string = 'ap-beijing';

  /**
   * 测试存储桶名称
   */
  static readonly BUCKET: string = 'default-1253435893';

  /**
   * 测试文件路径
   */
  static readonly TEST_FILE: string = 'test-1.kdbx';

  /**
   * 测试路径数组 - 包含中文路径、多级目录等场景
   */
  static readonly TEST_PATHS: string[] = [
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
   * 是否使用路径风格 URL
   * 注意：2024年1月1日后创建的存储桶不支持 path-style，必须使用 virtual-hosted-style
   * 腾讯云 COS 文档：https://cloud.tencent.com/document/product/436/96243
   */
  static readonly PATH_STYLE: boolean = false;

  /**
   * 获取完整的客户端配置选项
   */
  static getClientOptions(pathStyle: boolean = S3TestConfig.PATH_STYLE): S3ClientOptionsImpl {
    return new S3ClientOptionsImpl(
      S3TestConfig.ENDPOINT,
      S3TestConfig.ACCESS_KEY_ID,
      S3TestConfig.SECRET_ACCESS_KEY,
      S3TestConfig.REGION,
      pathStyle,
      S3TestConfig.TIMEOUT
    );
  }

  /**
   * 获取存储配置对象（用于 S3Storage.init）
   * 注意：返回一个模拟的 S3StorageConfig，避免触发 SM4 加密
   */
  static getStorageConfig(bucket?: string): TestS3StorageConfig {
    return new TestS3StorageConfig(
      S3TestConfig.ENDPOINT,
      S3TestConfig.ACCESS_KEY_ID,
      S3TestConfig.SECRET_ACCESS_KEY,
      S3TestConfig.REGION,
      bucket ?? S3TestConfig.BUCKET
    );
  }
}

/**
 * 测试用 S3 存储配置类
 * 直接存储明文凭证，避免 SM4 加密依赖
 */
export class TestS3StorageConfig {
  endpoint: string;
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  bucket: string;
  pathStyle: boolean = false;
  timeout: number = 30000;

  constructor(
    endpoint: string,
    accessKeyId: string,
    secretAccessKey: string,
    region: string,
    bucket: string
  ) {
    this.endpoint = endpoint;
    this.accessKeyId = accessKeyId;
    this.secretAccessKey = secretAccessKey;
    this.region = region;
    this.bucket = bucket;
  }

  /**
   * 返回明文 Access Key ID
   */
  public getAccessKeyIdText(): string {
    return this.accessKeyId;
  }

  /**
   * 返回明文 Secret Access Key
   */
  public getSecretAccessKeyText(): string {
    return this.secretAccessKey;
  }
}
