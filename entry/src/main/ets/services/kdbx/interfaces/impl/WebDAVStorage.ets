import { FileInfo, IFileStorage } from '../IFileStorage';
import { WebDAVStorageConfig } from '../StorageConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ResultInfo, WebDavClient } from '../../../../common/utils/WebDavClient';
import ResourceManager from '../../../../common/utils/ResourceManager';

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
  public readFile(path: string): Promise<ArrayBuffer> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new Error(ResourceManager.getString($r('app.string.webdav_not_init'))));
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
      return Promise.reject(new Error(error.message));
    }
  }

  public async writeFile(path: string, data: ArrayBuffer): Promise<void> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new Error(ResourceManager.getString($r('app.string.webdav_not_init'))));
    }
    try {
      await this.client.upload(path, data);
    } catch (error) {
      console.error('WebDAV writeFile error:', error);
      throw new Error('Failed to write file to WebDAV');
    }
  }

  /**
   * 检查文件是否存在
   * @param path
   * @returns
   */
  public async exists(path: string): Promise<boolean> {
    return this.getFileInfo(path).then((fileInfo) => {
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
  public async getFileInfo(path: string): Promise<FileInfo> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new Error(ResourceManager.getString($r('app.string.webdav_not_init'))));
    }
    return this.client.list(path).then((res: ResultInfo) => {
      if (res.success && res.data && res.data.length > 0) {
        const fileInfo = res.data[0];
        if (fileInfo.type == 'collection') {
          throw new Error(ResourceManager.getString($r('app.string.webdav_not_file')));
        }
        return Promise.resolve({
          name: fileInfo.displayName,
          size: fileInfo.contentLength,
          modifiedTime: new Date(fileInfo.lastModified).getTime(),
          path: fileInfo.href
        } as FileInfo);
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
