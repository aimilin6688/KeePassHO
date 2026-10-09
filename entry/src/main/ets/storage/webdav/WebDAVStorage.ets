import { BaseFileStorage, FileInfo, FileType, PageConfig, TransferProgressCallback, WriteOption } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ResultInfo, WebDavClient } from '../../common/utils/WebDavClient';
import { ResourceManager } from '../../common/utils'
import { HTTP_UPLOAD_MAX_BYTES, StorageError, StorageErrorCodes } from '../StorageError';
import { WebDAVPageConfig, WebDAVStorageConfig } from './WebDAVConfig';

const DOMAIN = 0x0000;
const TAG = 'WebDAVStorage';

/**
 * WebDAV存储实现类
 */
export class WebDAVStorage extends BaseFileStorage {
  private config: WebDAVStorageConfig | undefined;
  private client: WebDavClient | undefined;

  constructor(config?: WebDAVStorageConfig) {
    super();
    if (config) {
      this.init(config);
    }
  }

  public getPageConfig(): PageConfig {
    return WebDAVPageConfig;
  }

  /**
   * 版本快速路径 opt-in：version 为 `etag|lastModified` 复合串（弱 ETag 时以 lastModified 为主），
   * write/writeFromFile 已履约 expectedVersion 条件写入（写前复核 + VERSION_CONFLICT）。
   * 加载侧额外叠加 size 双比对（编排层契约），误判窗口收敛为"同秒 + 同尺寸两次修改"。
   */
  public supportsVersionFastPath(): boolean {
    return true;
  }

  public init(config: WebDAVStorageConfig) {
    const parsedConfig = this.parseConfig(config);
    // 配置相同，复用现有连接，避免 close 导致进行中的请求被取消
    if (this.isSameConfig(parsedConfig)) {
      this.config = parsedConfig;
      return;
    }
    // 配置不同，关闭旧连接，创建新连接
    this.config = parsedConfig;
    this.closeClient();
    this.client = new WebDavClient({
      url: this.config.url,
      username: this.config.getUserNameText(),
      password: this.config.getPasswordText(),
      certValidationMode: this.config.certValidationMode,
      customCaCertContent: this.config.customCaCertContent
    });
  }

  /**
   * 关闭 WebDAV 客户端连接
   */
  private closeClient() {
    if (this.client) {
      try {
        this.client.close();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Close old WebDAV client error: %{public}s', e?.message);
      }
    }
  }

  /**
   * 判断配置是否相同
   * 比较 url/username/password 三个字段，相同则 session 等价，无需重建
   * 注意：比较解密后的值，因为加密结果每次不同
   */
  private isSameConfig(newConfig: WebDAVStorageConfig): boolean {
    if (!this.config) {
      return false;
    }
    return this.config.url === newConfig.url
      && this.config.getUserNameText() === newConfig.getUserNameText()
      && this.config.getPasswordText() === newConfig.getPasswordText();
  }

  private parseConfig(config: WebDAVStorageConfig): WebDAVStorageConfig {
    if (config instanceof WebDAVStorageConfig) {
      return config;
    }
    config = config as WebDAVStorageConfig;
    return new WebDAVStorageConfig(config.url, config.username, config.password, { rootPath: config.rootPath, timeout: config.timeout });
  }

  /**
   * 读取文件内容
   * @param path  文件路径
   * @returns 结果
   */
  public read(path: string): Promise<ArrayBuffer> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, ResourceManager.getString($r('app.string.webdav_not_init'))));
    }
    try {
      return this.client.get(path).then((res: ResultInfo) => {
        if (res.success && res.body) {
          return Promise.resolve(res.body);
        }
        return Promise.reject(new Error(res.message));
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'WebDAV readFile error:%{public}s', error.message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, error.message));
    }
  }

  public async write(path: string, data: ArrayBuffer, option?: WriteOption): Promise<void> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, ResourceManager.getString($r('app.string.webdav_not_init'))));
    }
    // CP-UP：整缓冲上传超过 http 栈上限必然失败，提前拒绝并给出明确原因
    if (data.byteLength > HTTP_UPLOAD_MAX_BYTES) {
      throw new StorageError(StorageErrorCodes.UPLOAD_TOO_LARGE, `${data.byteLength} bytes`);
    }
    const expectedVersion: string | null = option?.expectedVersion ?? null;
    try {
      // 条件写入：写前复核远端版本，防止覆盖其他设备的修改（TOCTOU 窗口由上层重试兜底）
      if (expectedVersion !== null) {
        await this.checkVersionUnchanged(path, expectedVersion);
      }
      await this.client.upload(path, data);
    } catch (error) {
      // 版本冲突直接透传，保持错误码不被改写
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      // upload 失败以 ResultInfo 形式 reject（含 statusCode 与映射后的可读消息），
      // 此处透传为携带状态码的错误信息，不吞错、不静默成功
      let errorMessage: string;
      if (error instanceof ResultInfo) {
        errorMessage = `${error.message}(${error.statusCode})`;
      } else {
        errorMessage = error.message;
      }
      hilog.error(DOMAIN, TAG, 'WebDAV writeFile error: %{public}s', errorMessage);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, errorMessage));
    }
  }

  /**
   * 写前复核：校验远端当前版本与期望版本一致，不一致抛出版本冲突
   * @param path 文件路径
   * @param expectedVersion 期望的远端版本
   * @throws StorageError(VERSION_CONFLICT) 版本不一致时抛出
   */
  private async checkVersionUnchanged(path: string, expectedVersion: string): Promise<void> {
    const currentInfo: FileInfo = await this.getInfo(path);
    const currentVersion: string | null = currentInfo.version ?? null;
    if (currentVersion === null || currentVersion !== expectedVersion) {
      hilog.warn(DOMAIN, TAG, 'WebDAV version conflict, path: %{public}s, expected: %{public}s, current: %{public}s',
        path, expectedVersion, currentVersion);
      throw new StorageError(StorageErrorCodes.VERSION_CONFLICT, 'WebDAV file version changed');
    }
  }

  /**
   * 流式下载到本地文件（rcp.downloadToFile，响应体不驻留内存，修 P8/P9）
   * @param path 远端路径
   * @param destPath 本地目标路径
   */
  public async readToFile(path: string, destPath: string): Promise<FileInfo> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED,
        ResourceManager.getString($r('app.string.webdav_not_init')));
    }
    try {
      const result: ResultInfo = await this.client.downloadToFile(path, destPath);
      if (!result.success) {
        throw new StorageError(StorageErrorCodes.FILE_READ_ERROR,
          `${result.message}(${result.statusCode})`);
      }
      // 下载完成后取远端 FileInfo（含 ETag 作为 version）
      return await this.getInfo(path);
    } catch (error) {
      if (error instanceof StorageError) {
        throw error;
      }
      hilog.error(DOMAIN, TAG, 'WebDAV readToFile error:%{public}s', error.message);
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, error.message);
    }
  }

  /**
   * 流式从本地文件上传（S7：rcp Request + UploadFromFile，PUT 请求体不驻内存）
   * 写前复核远端版本（TOCTOU 窗口由上层重试兜底），完成后返回远端 FileInfo
   * @param onProgress 上传进度回调（可选）：rcp onUploadProgress 字节级透传
   */
  public async writeFromFile(path: string, srcPath: string, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<FileInfo> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED,
        ResourceManager.getString($r('app.string.webdav_not_init')));
    }
    const expectedVersion: string | null = option?.expectedVersion ?? null;
    try {
      if (expectedVersion !== null) {
        await this.checkVersionUnchanged(path, expectedVersion);
      }
      const progressAdapter: ((totalSize: number, transferredSize: number) => void) | undefined =
        onProgress ? (totalSize: number, transferredSize: number): void => {
          onProgress(transferredSize, totalSize);
        } : undefined;
      await this.client.uploadFromFile(path, srcPath, progressAdapter);
      return await this.getInfo(path);
    } catch (error) {
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      let errorMessage: string;
      if (error instanceof ResultInfo) {
        errorMessage = `${error.message}(${error.statusCode})`;
      } else {
        errorMessage = error.message;
      }
      hilog.error(DOMAIN, TAG, 'WebDAV writeFromFile error: %{public}s', errorMessage);
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, errorMessage);
    }
  }

  /**
   * 获取文件信息；404 返回 null，其他错误上抛（无法判定）
   * @param path 远端路径
   * @return Promise<FileInfo | null> 文件信息，确定不存在时为 null
   */
  public async getInfoOrNull(path: string): Promise<FileInfo | null> {
    hilog.info(DOMAIN, TAG, `Query path exists: ${path}`);
    try {
      return await this.getInfo(path);
    } catch (error) {
      if (error instanceof WebDAVError && error.code === 404) {
        return null;
      }
      throw error as Error;
    }
  }

  /**
   * 获取文件信息
   * @param path
   * @returns
   */
  public async getInfo(path: string): Promise<FileInfo> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, ResourceManager.getString($r('app.string.webdav_not_init'))));
    }
    return this.client.list(path, 0).then((res: ResultInfo) => {
      if (res.success && res.data && res.data.length > 0) {
        const fileInfo = res.data[0];
        return Promise.resolve({
          name: fileInfo.displayName,
          size: fileInfo.contentLength,
          modifiedTime: new Date(fileInfo.lastModified).getTime(),
          path: fileInfo.href,
          type: fileInfo.type == 'collection' ? FileType.DIR : FileType.FILE,
          childrenCount: 0,
          version: WebDAVStorage.buildVersion(fileInfo.etag, fileInfo.lastModified)
        } as FileInfo);
      } else {
        return Promise.reject(new WebDAVError(res.statusCode, res.message));
      }
    });
  }

  /**
   * 构建不透明版本标识：ETag 与 Last-Modified 复合串
   * 弱 ETag（W/"..."）不可靠，以 Last-Modified 为主；两者皆空返回 null
   * @param etag ETag 值
   * @param lastModified 最后修改时间字符串
   */
  private static buildVersion(etag: string | undefined, lastModified: string): string | null {
    const normalizedEtag: string = etag ?? '';
    if (!normalizedEtag && !lastModified) {
      return null;
    }
    return `${normalizedEtag}|${lastModified}`;
  }

  /**
   * 获取目录内容
   * @param path 目录路径
   * @returns 目录内容
   */
  public async listDir(path: string): Promise<Array<FileInfo>> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, ResourceManager.getString($r('app.string.webdav_not_init'))));
    }
    // 单次目录列表请求（FR-005），不再查询子目录计数，childrenCount 恒为 0
    return this.client.list(path, 0).then((res: ResultInfo) => {
      if (res.success && res.data) {
        if (res.data.length <= 0) {
          return Promise.resolve([]);
        }
        const files = new Array<FileInfo>(res.data.length);
        for (let i = 0; i < res.data.length; i++) {
          const fileInfo = res.data[i];
          // 目录浏览，第一个元素是目录本身，跳过
          if (i === 0 && fileInfo.type === 'collection') {
            continue;
          }
          files.push({
            name: fileInfo.displayName,
            size: fileInfo.contentLength,
            modifiedTime: new Date(fileInfo.lastModified).getTime(),
            path: fileInfo.href,
            type: fileInfo.type == 'collection' ? FileType.DIR : FileType.FILE,
            childrenCount: 0
          } as FileInfo);
        }
        return Promise.resolve(files);
      } else {
        return Promise.reject(new WebDAVError(res.statusCode, res.message));
      }
    });
  }
}

export class WebDAVError extends Error {
  public readonly code: number;

  constructor(code: number, message?: string) {
    super('Error ' + code + (message ? ': ' + message : ''));

    this.name = 'WebDAVError';
    this.code = code;
  }
}