import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig } from '../index';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { S3PageConfig, S3StorageConfig } from './S3Config';
import { S3Client, S3ClientOptionsImpl } from './S3Client';

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
    const options: S3ClientOptionsImpl = new S3ClientOptionsImpl(
      this.config.endpoint,
      this.config.getAccessKeyIdText(),
      this.config.getSecretAccessKeyText(),
      this.config.region,
      this.config.pathStyle,
      this.config.timeout
    );
    this.client = new S3Client(options);
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
    // 去除开头的斜杠，统一处理
    const normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    const parts: string[] = normalizedPath.split('/').filter((p: string): boolean => p.length > 0);

    // 情况1: 配置了默认 bucket
    if (this.config?.bucket) {
      let bucket: string = this.config.bucket;
      let key: string = '';

      if (parts.length === 0) {
        // 空路径，使用默认 bucket，key 为空
        key = '';
      } else if (parts[0] === this.config.bucket) {
        // 路径以 bucket 开头: bucket/key 或 bucket
        bucket = parts[0];
        key = parts.slice(1).join('/');
      } else {
        // 路径不以 bucket 开头，视为 key
        key = parts.join('/');
      }

      const result: S3PathResult = { bucket, key };
      return result;
    }

    // 情况2: 没有配置默认 bucket，路径必须包含 bucket
    if (parts.length === 0) {
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, 'Path must contain bucket name');
    }

    if (parts.length === 1) {
      // 只有 bucket 名称，key 为空
      const result: S3PathResult = { bucket: parts[0], key: '' };
      return result;
    }

    // 路径格式: bucket/key1/key2
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

    // 空路径或只有 bucket 的路径视为目录
    if (!pathResult.key || pathResult.key.length === 0) {
      const info: FileInfo = {
        name: pathResult.bucket,
        size: 0,
        modifiedTime: 0,
        path: path,
        type: FileType.DIR,
        childrenCount: 0
      };
      return info;
    }

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
    // 确保前缀以 / 结尾，这样才能正确列出目录内容
    let prefix: string = pathResult.key;
    if (prefix.length > 0 && !prefix.endsWith('/')) {
      prefix = prefix + '/';
    }
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

      // 判断是否为目录
      const isDir: boolean = obj.key.endsWith('/');

      const info: FileInfo = {
        name: this.getFileName(obj.key),
        size: isDir ? 0 : obj.size,
        // 目录没有修改时间，设为 0
        modifiedTime: isDir ? 0 : obj.lastModified,
        path: `${pathResult.bucket}/${obj.key}`,
        type: isDir ? FileType.DIR : FileType.FILE,
        childrenCount: 0
      };
      files.push(info);
    }

    return files;
  }

  /**
   * 关闭 S3 存储连接，释放资源
   * 应在使用完毕后调用此方法以释放 rcp session
   */
  public close(): void {
    this.client?.close();
    this.client = undefined;
  }
}
