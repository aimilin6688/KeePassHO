import { PageConfig, StorageConfig } from '../StorageConfig';
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
 * S3 页面配置
 */
export const S3PageConfig: PageConfig = {
  icon: $r('app.media.ic_s3'),
  title: $r('app.string.s3_button_title'),
  selectDesc: $r('app.string.s3_select_file'),
  saveDesc: $r('app.string.s3_save_file'),
  pageUrl: 'storage/s3/S3Page',
  storageType: StorageType.S3
};
