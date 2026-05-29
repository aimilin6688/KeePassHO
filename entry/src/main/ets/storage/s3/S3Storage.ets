import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { S3StorageConfig, S3PageConfig } from './S3Config';
import { S3Client } from './S3Client';
import { FilenameUtils } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'S3Storage';

/**
 * S3 存储实现
 */
export class S3Storage implements IFileStorage {
  private config: S3StorageConfig | undefined;
  private client: S3Client | undefined;

  constructor(config?: S3StorageConfig) {
    if (config) {
      this.init(config);
    }
  }

  public getPageConfig(): PageConfig {
    return S3PageConfig;
  }

  public init(config: StorageConfig): void {
    this.config = this.parseConfig(config);
    this.client = new S3Client({
      endpoint: this.config.endpoint,
      accessKeyId: this.config.getAccessKeyIdText(),
      secretAccessKey: this.config.getSecretAccessKeyText(),
      region: this.config.region,
      pathStyle: this.config.pathStyle,
      timeout: this.config.timeout
    });
  }

  private parseConfig(config: StorageConfig): S3StorageConfig {
    if (config instanceof S3StorageConfig) {
      return config;
    }
    const inputConfig = config as Record<string, Object>;
    return new S3StorageConfig(
      inputConfig['endpoint'] as string,
      inputConfig['accessKeyId'] as string,
      inputConfig['secretAccessKey'] as string,
      {
        region: inputConfig['region'] as string | undefined,
        bucket: inputConfig['bucket'] as string | undefined,
        pathStyle: inputConfig['pathStyle'] as boolean | undefined,
        timeout: inputConfig['timeout'] as number | undefined
      }
    );
  }

  private parsePath(path: string): { bucket: string; key: string } {
    const parts = path.split('/').filter(p => p.length > 0);

    if (this.config?.bucket) {
      return {
        bucket: this.config.bucket,
        key: path.startsWith('/') ? path.substring(1) : path
      };
    }

    if (parts.length < 2) {
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, 'Invalid path format');
    }

    return {
      bucket: parts[0],
      key: parts.slice(1).join('/')
    };
  }

  private getFileName(key: string): string {
    const parts = key.split('/');
    return parts[parts.length - 1] || key;
  }

  public async read(path: string): Promise<ArrayBuffer> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const { bucket, key } = this.parsePath(path);
    const result = await this.client.getObject(bucket, key);

    if (!result.success || !result.data) {
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, result.message);
    }

    return result.data;
  }

  public async write(path: string, content: ArrayBuffer): Promise<void> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const { bucket, key } = this.parsePath(path);
    const result = await this.client.putObject(bucket, key, content);

    if (!result.success) {
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, result.message);
    }
  }

  public async exists(path: string): Promise<boolean> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    try {
      const { bucket, key } = this.parsePath(path);
      const result = await this.client.headObject(bucket, key);
      return result.success;
    } catch {
      return false;
    }
  }

  public async getInfo(path: string): Promise<FileInfo> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const { bucket, key } = this.parsePath(path);
    const result = await this.client.headObject(bucket, key);

    if (!result.success || !result.data) {
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, result.message);
    }

    return {
      name: this.getFileName(key),
      size: result.data.size,
      modifiedTime: result.data.lastModified,
      path: path,
      type: FileType.FILE,
      childrenCount: 0
    };
  }

  public async listDir(path: string): Promise<FileInfo[]> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const { bucket, key: prefix } = this.parsePath(path);
    const result = await this.client.listObjects(bucket, prefix);

    if (!result.success || !result.data) {
      throw new StorageError(StorageErrorCodes.NOT_IMPLEMENTED, result.message);
    }

    const files: FileInfo[] = [];
    for (const obj of result.data) {
      if (obj.key === prefix || obj.key === prefix + '/') {
        continue;
      }

      files.push({
        name: this.getFileName(obj.key),
        size: obj.size,
        modifiedTime: obj.lastModified,
        path: `${bucket}/${obj.key}`,
        type: obj.key.endsWith('/') ? FileType.DIR : FileType.FILE,
        childrenCount: 0
      });
    }

    return files;
  }
}
