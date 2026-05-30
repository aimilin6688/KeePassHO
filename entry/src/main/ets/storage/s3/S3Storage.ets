import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { S3StorageConfig, S3PageConfig } from './S3Config';
import { S3Client } from './S3Client';
import { FilenameUtils } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'S3Storage';

/**
 * S3 路径解析结果
 */
interface S3PathResult {
  bucket: string;
  key: string;
}

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

  private parsePath(path: string): S3PathResult {
    const parts: string[] = path.split('/').filter((p: string): boolean => p.length > 0);

    if (this.config?.bucket) {
      const result: S3PathResult = {
        bucket: this.config.bucket,
        key: path.startsWith('/') ? path.substring(1) : path
      };
      return result;
    }

    if (parts.length < 2) {
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, 'Invalid path format');
    }

    const result: S3PathResult = {
      bucket: parts[0],
      key: parts.slice(1).join('/')
    };
    return result;
  }

  private getFileName(key: string): string {
    const parts = key.split('/');
    return parts[parts.length - 1] || key;
  }

  public async read(path: string): Promise<ArrayBuffer> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const pathResult: S3PathResult = this.parsePath(path);
    const result = await this.client.getObject(pathResult.bucket, pathResult.key);

    if (!result.success || !result.data) {
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, result.message);
    }

    return result.data;
  }

  public async write(path: string, content: ArrayBuffer): Promise<void> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const pathResult: S3PathResult = this.parsePath(path);
    const result = await this.client.putObject(pathResult.bucket, pathResult.key, content);

    if (!result.success) {
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, result.message);
    }
  }

  public async exists(path: string): Promise<boolean> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    try {
      const pathResult: S3PathResult = this.parsePath(path);
      const result = await this.client.headObject(pathResult.bucket, pathResult.key);
      return result.success;
    } catch {
      return false;
    }
  }

  public async getInfo(path: string): Promise<FileInfo> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const pathResult: S3PathResult = this.parsePath(path);
    const result = await this.client.headObject(pathResult.bucket, pathResult.key);

    if (!result.success || !result.data) {
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, result.message);
    }

    const info: FileInfo = {
      name: this.getFileName(pathResult.key),
      size: result.data.size,
      modifiedTime: result.data.lastModified,
      path: path,
      type: FileType.FILE,
      childrenCount: 0
    };
    return info;
  }

  public async listDir(path: string): Promise<FileInfo[]> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const pathResult: S3PathResult = this.parsePath(path);
    const prefix: string = pathResult.key;
    const result = await this.client.listObjects(pathResult.bucket, prefix);

    if (!result.success || !result.data) {
      throw new StorageError(StorageErrorCodes.NOT_IMPLEMENTED, result.message);
    }

    const files: FileInfo[] = [];
    for (let i = 0; i < result.data.length; i++) {
      const obj = result.data[i];
      if (obj.key === prefix || obj.key === prefix + '/') {
        continue;
      }

      const info: FileInfo = {
        name: this.getFileName(obj.key),
        size: obj.size,
        modifiedTime: obj.lastModified,
        path: `${pathResult.bucket}/${obj.key}`,
        type: obj.key.endsWith('/') ? FileType.DIR : FileType.FILE,
        childrenCount: 0
      };
      files.push(info);
    }

    return files;
  }
}
