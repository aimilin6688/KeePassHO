import { ChildDbCredentialKeys, ChildDbRebuildArgs, ChildDbScheme, ChildDbUrlKind, ChildTarget,
  PageConfig, StorageConfig } from '../StorageConfig';
import { Sm4Utils } from '../../common/utils/Sm4Utils';
import { StorageType } from '..';

/**
 * S3 存储配置选项
 */
export interface S3ConfigOptions {
  /**
   * 区域，默认 us-east-1
   */
  region?: string;

  /**
   * 默认存储桶
   */
  bucket?: string;

  /**
   * 是否使用路径样式 URL，默认 false
   */
  pathStyle?: boolean;

  /**
   * 超时时间（毫秒），默认 30000
   */
  timeout?: number;
}

/**
 * S3 存储配置类
 */
export class S3StorageConfig implements StorageConfig {
  /**
   * 服务端点，如 https://s3.amazonaws.com
   */
  endpoint: string;

  /**
   * Access Key ID，加密存储
   */
  accessKeyId: string;

  /**
   * Secret Access Key，加密存储
   */
  secretAccessKey: string;

  /**
   * 区域
   */
  region: string;

  /**
   * 默认存储桶
   */
  bucket?: string;

  /**
   * 是否使用路径样式 URL
   */
  pathStyle: boolean;

  /**
   * 超时时间（毫秒）
   */
  timeout: number;

  constructor(
    endpoint: string,
    accessKeyId: string,
    secretAccessKey: string,
    options?: S3ConfigOptions
  ) {
    this.endpoint = endpoint;
    this.accessKeyId = Sm4Utils.encryptWithPrefix(accessKeyId);
    this.secretAccessKey = Sm4Utils.encryptWithPrefix(secretAccessKey);
    this.region = options?.region || 'us-east-1';
    this.bucket = options?.bucket;
    this.pathStyle = options?.pathStyle ?? false;
    this.timeout = options?.timeout ?? 30000;
  }

  /**
   * 获取 Access Key ID（解密后）
   */
  public getAccessKeyIdText(): string {
    return Sm4Utils.decryptWithPrefix(this.accessKeyId);
  }

  /**
   * 获取 Secret Access Key（解密后）
   */
  public getSecretAccessKeyText(): string {
    return Sm4Utils.decryptWithPrefix(this.secretAccessKey);
  }
}

/**
 * S3 Multipart Upload 配置常量
 */
export class S3MultipartConfig {
  /**
   * 最小分块大小：5MB（S3 标准）
   * 所有非最后一个 part 必须至少 5MB
   */
  static readonly MIN_PART_SIZE = 5 * 1024 * 1024; // 5MB

  /**
   * 推荐分块大小：8MB
   * 平衡上传效率和重试成本
   */
  static readonly RECOMMENDED_PART_SIZE = 8 * 1024 * 1024; // 8MB

  /**
   * 最大分块大小：32MB
   * 避免单个分块过大导致内存问题
   */
  static readonly MAX_PART_SIZE = 32 * 1024 * 1024; // 32MB

  /**
   * Multipart 上传阈值：5MB
   * 文件 >= 5MB 时启用 multipart upload
   */
  static readonly MULTIPART_THRESHOLD = 5 * 1024 * 1024; // 5MB

  /**
   * 目标分块数量：500
   * 自适应算法的目标分块数
   */
  static readonly TARGET_PART_COUNT = 500;

  /**
   * 并发上传数量：3
   * 同时上传的分块数量
   */
  static readonly CONCURRENT_UPLOADS = 3;

  /**
   * 最大重试次数
   */
  static readonly MAX_RETRY_COUNT = 3;

  /**
   * 进度回调最小间隔：100ms
   * 避免过于频繁的进度更新
   */
  static readonly PROGRESS_CALLBACK_INTERVAL = 100; // ms
}

/**
 * 子库打开时 storageConfig 重建（PageConfig.childDbConfigRebuilder 契约，M6.3）：
 * IocUserName=AccessKeyId / IocPassword=SecretAccessKey
 * + endpoint/bucket + S3Region/S3PathStyle 自定义字符串（本项目扩展，可选）
 */
export function s3ChildDbConfigRebuilder(args: ChildDbRebuildArgs,
  target: ChildTarget): StorageConfig | undefined {
  if (args.iocUserName.length === 0 || target.endpoint.length === 0) {
    return undefined;
  }
  const regionRaw = args.customStrings.get('S3Region') ?? '';
  const region = regionRaw.replace(/^\s+/, '').replace(/\s+$/, '');
  const pathStyleRaw = args.customStrings.get('S3PathStyle') ?? '';
  return new S3StorageConfig(target.endpoint, args.iocUserName, args.iocPassword, {
    region: region.length > 0 ? region : undefined,
    bucket: target.bucket.length > 0 ? target.bucket : undefined,
    pathStyle: pathStyleRaw.toLowerCase() === 'true'
  });
}

/**
 * 子库写侧附加自定义字符串（PageConfig.childDbExtraFields 契约，M6.4）：
 * 非默认 region 或开启 pathStyle 时产出微调字段（保持条目简洁，默认值不写）
 */
export function s3ChildDbExtraFields(config: StorageConfig): Map<string, string> {
  const fields = new Map<string, string>();
  let region = '';
  let pathStyle = false;
  if (config instanceof S3StorageConfig) {
    region = config.region ?? '';
    pathStyle = config.pathStyle;
  } else {
    const record = config as Record<string, Object>;
    const regionValue: Object | undefined = record['region'];
    region = regionValue === undefined ? '' : String(regionValue);
    const pathStyleValue: Object | undefined = record['pathStyle'];
    pathStyle = pathStyleValue !== undefined && String(pathStyleValue) === 'true';
  }
  if (region.length > 0 && region !== 'us-east-1') {
    fields.set('S3Region', region);
  }
  if (pathStyle) {
    fields.set('S3PathStyle', 'True');
  }
  return fields;
}

/**
 * S3 页面配置
 */
export const S3PageConfig: PageConfig = {
  icon: $r('app.media.ic_s3'),
  title: $r('app.string.s3_button_title'),
  selectDesc: $r('app.string.s3_select_file'),
  saveDesc: $r('app.string.s3_save_file'),
  pageUrl: 'storage/s3/S3Page',
  storageType: StorageType.S3,
  // M6 子库 scheme 声明（ENDPOINT_BUCKET 文法）：endpoint权威/bucket/key
  childDbSchemes: [new ChildDbScheme('s3', ChildDbUrlKind.ENDPOINT_BUCKET)],
  childDbCredentialKeys: new ChildDbCredentialKeys('accessKeyId', 'secretAccessKey'),
  childDbConfigRebuilder: s3ChildDbConfigRebuilder,
  childDbExtraFields: s3ChildDbExtraFields
};
