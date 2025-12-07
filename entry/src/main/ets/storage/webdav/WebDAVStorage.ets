import { FileInfo, FileType, IFileStorage, PageConfig } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ResultInfo, WebDavClient } from '../../common/utils/WebDavClient';
import ResourceManager from '../../common/utils/ResourceManager';
import { StorageError, StorageErrorCodes } from '../../services/error/StorageError';
import { WebDAVPageConfig, WebDAVStorageConfig } from './WebDAVConfig';

const DOMAIN = 0x0000;
const TAG = 'WebDAVStorage';

/**
 * WebDAV存储实现类
 */
export class WebDAVStorage implements IFileStorage {
  private config: WebDAVStorageConfig | undefined;
  private client: WebDavClient | undefined;

  constructor(config?: WebDAVStorageConfig) {
    if (config) {
      this.init(config);
    }
  }

  public getPageConfig(): PageConfig {
    return WebDAVPageConfig;
  }

  public init(config: WebDAVStorageConfig) {
    this.config = this.parseConfig(config);
    if (this.client) {
      this.client.close();
    }
    this.client = new WebDavClient({
      url: this.config.url,
      username: this.config.getUserNameText(),
      password: this.config.getPasswordText()
    });
  }

  private parseConfig(config: WebDAVStorageConfig): WebDAVStorageConfig {
    if (config instanceof WebDAVStorageConfig) {
      return config;
    }
    config = config as WebDAVStorageConfig;
    return new WebDAVStorageConfig(config.url, config.username, config.password, { rootPath: config.rootPath, timeout: config.timeout }, true);
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

  public async write(path: string, data: ArrayBuffer): Promise<void> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, ResourceManager.getString($r('app.string.webdav_not_init'))));
    }
    try {
      await this.client.upload(path, data);
    } catch (error) {
      console.error('WebDAV writeFile error:', error);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, error.message));
    }
  }

  /**
   * 检查文件是否存在
   * @param path
   * @returns
   */
  public async exists(path: string): Promise<boolean> {
    return this.getInfo(path).then((fileInfo) => {
      return fileInfo != null;
    }).catch((error: Error) => {
      if (error instanceof WebDAVError && error.code === 404) {
        return false;
      }
      return Promise.reject(error);
    });
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
    return this.client.list(path, 0, false).then((res: ResultInfo) => {
      if (res.success && res.data && res.data.length > 0) {
        const fileInfo = res.data[0];
        return Promise.resolve({
          name: fileInfo.displayName,
          size: fileInfo.contentLength,
          modifiedTime: new Date(fileInfo.lastModified).getTime(),
          path: fileInfo.href,
          type: fileInfo.type == 'collection' ? FileType.DIR : FileType.FILE,
          childrenCount: fileInfo.childrenCount
        } as FileInfo);
      } else {
        return Promise.reject(new WebDAVError(res.statusCode, res.message));
      }
    });
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
    return this.client.list(path, 0, true).then((res: ResultInfo) => {
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
            childrenCount: fileInfo.childrenCount
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