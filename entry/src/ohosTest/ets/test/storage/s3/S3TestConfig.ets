import { S3ClientOptionsImpl } from '../../../../../main/ets/storage/s3/S3Client';
import { StorageConfig } from '../../../../../main/ets/storage/StorageConfig';

/**
 * S3 测试公共配置
 * 指向本地 podman 部署的 SeaweedFS S3 网关（搭建步骤见 docs/s3/seaweedfs-server.md）。
 * 测试通过设备侧 rport 反向隧道访问宿主机服务，设备内地址固定为 127.0.0.1:9000。
 */
export class S3TestConfig {
  /**
   * S3 兼容服务端点（设备侧 rport 隧道 → 宿主机 SeaweedFS S3 网关）
   * 注意：自建网关必须使用 path-style，endpoint 不包含 bucket 名
   */
  static readonly ENDPOINT: string = 'http://127.0.0.1:9000';

  /**
   * Access Key ID（SeaweedFS 未启用 IAM，任意非空凭证即可通过签名校验）
   */
  static readonly ACCESS_KEY_ID: string = 'e2e';

  /**
   * Secret Access Key
   */
  static readonly SECRET_ACCESS_KEY: string = 'e2etest123';

  /**
   * 区域（SeaweedFS 不校验区域，保持 AWS 默认区域）
   */
  static readonly REGION: string = 'us-east-1';

  /**
   * 测试存储桶名称（由 seaweedfs-server.md 中的初始化步骤创建）
   */
  static readonly BUCKET: string = 'e2e-test';

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
   * 自建 S3 网关（SeaweedFS）必须使用 path-style
   */
  static readonly PATH_STYLE: boolean = true;

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
    const config: TestS3StorageConfig = new TestS3StorageConfig(
      S3TestConfig.ENDPOINT,
      S3TestConfig.ACCESS_KEY_ID,
      S3TestConfig.SECRET_ACCESS_KEY,
      S3TestConfig.REGION,
      bucket ?? S3TestConfig.BUCKET
    );
    config.pathStyle = S3TestConfig.PATH_STYLE;
    config.timeout = S3TestConfig.TIMEOUT;
    return config;
  }
}

/**
 * 测试用 S3 存储配置类
 * 直接存储明文凭证，避免 SM4 加密依赖
 */
export class TestS3StorageConfig implements StorageConfig {
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
