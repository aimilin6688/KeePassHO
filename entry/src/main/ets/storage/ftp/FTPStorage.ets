import { FileInfo, FileType, IFileStorage, PageConfig } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Client } from '@ohos/basic-ftp';
import { CommonUtils, ResourceManager } from '../../common/utils';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { FTPPageConfig, FTPStorageConfig } from './FTPConfig';

const DOMAIN = 0x0000;
const TAG = 'FTPStorage';

/**
 * FTP存储实现类
 */
export class FTPStorage implements IFileStorage {
  private config: FTPStorageConfig | undefined;
  private client: Client | undefined;

  constructor(config?: FTPStorageConfig) {
    if (config) {
      this.init(config);
    }
  }

  public getPageConfig(): PageConfig {
    return FTPPageConfig;
  }

  public init(config: FTPStorageConfig): void {
    this.config = this.parseConfig(config);
    if (this.client) {
      this.client.close();
    }
    this.client = new Client(CommonUtils.getContext(), this.config.timeout);
  }

  private parseConfig(config: FTPStorageConfig): FTPStorageConfig {
    if (config instanceof FTPStorageConfig) {
      return config;
    }
    config = config as FTPStorageConfig;
    return new FTPStorageConfig(config.host, config.getUserNameText(), config.getPasswordText(), {
      rootPath: config.rootPath,
      timeout: config.timeout,
      secure: config.secure,
      port: config.port
    });
  }

  private async ensureConnected(): Promise<Client> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'FTP client not initialized');
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, ResourceManager.getString($r('app.string.ftp_not_init')));
    }

    if (!this.config) {
      hilog.error(DOMAIN, TAG, 'FTP config not initialized');
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, ResourceManager.getString($r('app.string.ftp_not_init')));
    }

    try {
      // 连接到FTP服务器
      await this.client.ftp.reset();
      await this.client.access({
        host: this.config.host,
        port: this.config.port,
        user: this.config.getUserNameText(),
        password: this.config.getPasswordText(),
        secure: this.config.secure
      });
      return this.client;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'FTP connection failed: ' + error.message);
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, error.message);
    }
  }

  private getFullPath(path: string): string {
    if (!this.config?.rootPath) {
      return path;
    }
    // 确保路径格式正确
    const rootPath = this.config.rootPath.startsWith('/') ? this.config.rootPath : '/' + this.config.rootPath;
    const targetPath = path.startsWith('/') ? path : '/' + path;
    return rootPath + targetPath;
  }

  /**
   * 读取文件内容
   * @param path 文件路径
   * @returns 结果
   */
  public async read(path: string): Promise<ArrayBuffer> {
    try {
      const client = await this.ensureConnected();
      const fullPath = this.getFullPath(path);

      // 创建临时文件来存储下载内容
      const tempDir = CommonUtils.getContext().cacheDir;
      const tempFilePath = tempDir + '/temp_' + Date.now() + '.tmp';

      try {
        // 下载文件到临时位置
        await client.downloadTo(tempFilePath, fullPath);

        // 读取临时文件内容
        const file = await fs.open(tempFilePath, fs.OpenMode.READ_ONLY);
        const fileInfo = await fs.stat(file.fd);
        const buffer = new ArrayBuffer(fileInfo.size);
        await fs.read(file.fd, buffer);
        await fs.close(file.fd);

        // 删除临时文件
        await fs.unlink(tempFilePath);

        return buffer;
      } catch (downloadError) {
        // 清理临时文件（如果存在）
        try {
          await fs.unlink(tempFilePath);
        } catch (cleanupError) {
          // 忽略清理错误
        }
        if (downloadError instanceof Error) {
          throw downloadError;
        } else {
          throw new Error(String(downloadError));
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'FTP read error: ' + error.message);
      if (error instanceof StorageError) {
        throw error;
      }
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, error.message);
    }
  }

  public async write(path: string, content: ArrayBuffer): Promise<void> {
    try {
      const client = await this.ensureConnected();
      const fullPath = this.getFullPath(path);

      // 创建临时文件来存储上传内容
      const tempDir = CommonUtils.getContext().cacheDir;
      const tempFilePath = tempDir + '/temp_upload_' + Date.now() + '.tmp';

      try {
        // 写入内容到临时文件
        const file = await fs.open(tempFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        await fs.write(file.fd, content);
        await fs.close(file.fd);

        // 从临时文件上传到FTP服务器
        await client.uploadFrom(fullPath, tempFilePath);

        // 删除临时文件
        await fs.unlink(tempFilePath);
      } catch (uploadError) {
        // 清理临时文件（如果存在）
        try {
          await fs.unlink(tempFilePath);
        } catch (cleanupError) {
          // 忽略清理错误
        }
        if (uploadError instanceof Error) {
          throw uploadError;
        } else {
          throw new Error(String(uploadError));
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'FTP write error: ' + error.message);
      if (error instanceof StorageError) {
        throw error;
      }
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, error.message);
    }
  }

  /**
   * 检查文件是否存在
   * @param path 文件路径
   * @returns 是否存在
   */
  public async exists(path: string): Promise<boolean> {
    try {
      const fileInfo = await this.getInfo(path);
      return fileInfo != null;
    } catch (error) {
      if (error instanceof StorageError) {
        // 检查是否是文件未找到错误
        const err = error as StorageError;
        if (err.message && err.message.includes('File not found')) {
          return false;
        }
      }
      if (error instanceof Error) {
        throw error;
      } else {
        throw new Error(String(error));
      }
    }
  }

  /**
   * 获取文件信息
   * @param path 文件路径
   * @returns 文件信息
   */
  public async getInfo(path: string): Promise<FileInfo> {
    try {
      const client = await this.ensureConnected();
      const fullPath = this.getFullPath(path);

      // 获取文件所在目录的信息
      const dirPath = fullPath.substring(0, fullPath.lastIndexOf('/'));
      const fileName = fullPath.substring(fullPath.lastIndexOf('/') + 1);

      const files = await client.list(dirPath);
      const targetFile = files.find(file => file.name === fileName);

      if (!targetFile) {
        throw new Error('File not found: ' + path);
      }

      return {
        name: targetFile.name,
        size: targetFile.size,
        modifiedTime: targetFile.modifiedAt ? targetFile.modifiedAt.getTime() : 0,
        path: fullPath,
        type: targetFile.isDirectory ? FileType.DIR : FileType.FILE,
        childrenCount: 0
      } as FileInfo;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'FTP get info error: ' + error.message);
      if (error instanceof StorageError) {
        throw error;
      }
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, error.message);
    }
  }

  /**
   * 获取目录内容
   * @param path 目录路径
   * @returns 目录内容
   */
  public async listDir(path: string): Promise<Array<FileInfo>> {
    try {
      const client = await this.ensureConnected();
      const fullPath = this.getFullPath(path);

      const files = await client.list(fullPath);
      const result = new Array<FileInfo>();

      for (const file of files) {
        result.push({
          name: file.name,
          size: file.size,
          modifiedTime: file.modifiedAt ? file.modifiedAt.getTime() : 0,
          path: fullPath + (fullPath.endsWith('/') ? '' : '/') + file.name,
          type: file.isDirectory ? FileType.DIR : FileType.FILE,
          childrenCount: 0
        } as FileInfo);
      }

      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'FTP list dir error: ' + error.message);
      if (error instanceof StorageError) {
        throw error;
      }
      throw new StorageError(StorageErrorCodes.NOT_IMPLEMENTED, error.message);
    }
  }

  /**
   * 清理资源
   */
  public close(): void {
    if (this.client) {
      this.client.close();
      this.client = undefined;
    }
  }
}