import { FileInfo, FileType, IFileStorage, PageConfig } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CommonUtils, ResourceManager } from '../../common/utils';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { FTPPageConfig, FTPStorageConfig, ProtocolType } from './FTPConfig';
import { IFTPHandler } from './IFTPHandler';
import { SFTPHandler } from './SFTPHandler';
import { FTPHandler } from './FTPHandler';

const DOMAIN = 0x0000;
const TAG = 'FTPStorage';

/**
 * FTP存储实现类
 * 作为FTP和SFTP的统一接口，根据配置选择合适的处理器
 */
export class FTPStorage implements IFileStorage {
  private config: FTPStorageConfig | undefined;
  private handler: IFTPHandler | undefined;

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
    this.createHandler();
  }

  private parseConfig(config: FTPStorageConfig): FTPStorageConfig {
    if (config instanceof FTPStorageConfig) {
      return config;
    }
    const inputConfig: Record<string, Object> = config;
    const protocolValue = inputConfig['protocol'] as string | undefined;
    let protocol = ProtocolType.FTP;
    if (protocolValue === 'SFTP') {
      protocol = ProtocolType.SFTP;
    }

    const portValue = inputConfig['port'] as number | string | undefined;
    const port: number | undefined = typeof portValue === 'string' ? parseInt(portValue) : portValue;

    return new FTPStorageConfig(
      inputConfig['host'] as string,
      inputConfig['username'] as string,
      inputConfig['password'] as string,
      {
        rootPath: inputConfig['rootPath'] as string | undefined,
        timeout: inputConfig['timeout'] as number | undefined,
        secure: inputConfig['secure'] as boolean | undefined,
        port: port,
        protocol: protocol
      }
    );
  }

  private createHandler(): void {
    if (!this.config) {
      return;
    }

    const config = this.config;

    // 根据协议类型创建对应的处理器
    if (config.isSFTP()) {
      this.handler = new SFTPHandler({
        host: config.host,
        port: config.port,
        username: config.getUserNameText(),
        password: config.getPasswordText(),
        timeout: config.timeout
      });
    } else {
      this.handler = new FTPHandler({
        host: config.host,
        port: config.port,
        username: config.getUserNameText(),
        password: config.getPasswordText(),
        secure: config.secure,
        timeout: config.timeout
      });
    }
  }

  /**
   * 确保已连接
   */
  private async ensureConnected(): Promise<IFTPHandler> {
    if (!this.handler) {
      hilog.error(DOMAIN, TAG, 'Storage handler not initialized');
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, ResourceManager.getString($r('app.string.ftp_not_init')));
    }

    if (!this.config) {
      hilog.error(DOMAIN, TAG, 'Storage config not initialized');
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, ResourceManager.getString($r('app.string.ftp_not_init')));
    }

    const config = this.config;

    // 检查连接状态，如果未连接则连接
    const ftpHandler = this.handler as FTPHandler;
    const sftpHandler = this.handler as SFTPHandler;

    if (config.isSFTP() && sftpHandler.isClosed()) {
      await sftpHandler.connect();
    } else if (!config.isSFTP() && ftpHandler.isClosed()) {
      await ftpHandler.connect();
    }

    return this.handler;
  }

  private getFullPath(path: string): string {
    const config = this.config;
    if (!config?.rootPath) {
      return path;
    }
    const rootPath = config.rootPath.startsWith('/') ? config.rootPath : '/' + config.rootPath;
    const targetPath = path.startsWith('/') ? path : '/' + path;

    // 避免重复的斜杠: 如果rootPath以'/'结尾且path以'/'开头,去掉path的前导'/'
    if (rootPath.endsWith('/') && targetPath.startsWith('/')) {
      return rootPath + targetPath.substring(1);
    }
    return rootPath + targetPath;
  }

  /**
   * 读取文件内容
   */
  public async read(path: string): Promise<ArrayBuffer> {
    const config = this.config;
    try {
      const fullPath = this.getFullPath(path);
      const tempDir = CommonUtils.getContext().cacheDir;
      const tempFilePath = tempDir + '/temp_' + Date.now() + '.tmp';

      try {
        const handler = await this.ensureConnected();
        await handler.downloadFrom(fullPath, tempFilePath);

        const file = await fs.open(tempFilePath, fs.OpenMode.READ_ONLY);
        const fileInfo = await fs.stat(file.fd);
        const buffer = new ArrayBuffer(fileInfo.size);
        await fs.read(file.fd, buffer);
        await fs.close(file.fd);
        await fs.unlink(tempFilePath);

        return buffer;
      } catch (downloadError) {
        try {
          await fs.unlink(tempFilePath);
        } catch {
          // 忽略清理错误
        }
        const err = downloadError instanceof Error ? downloadError : new Error(String(downloadError));
        throw err;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `${config?.protocol || 'FTP'} read error: ${error.message}`);
      if (error instanceof StorageError) {
        throw error;
      }
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, error.message);
    }
  }

  /**
   * 写入文件内容
   */
  public async write(path: string, content: ArrayBuffer): Promise<void> {
    const config = this.config;
    try {
      const fullPath = this.getFullPath(path);
      const tempDir = CommonUtils.getContext().cacheDir;
      const tempFilePath = tempDir + '/temp_upload_' + Date.now() + '.tmp';

      try {
        const file = await fs.open(tempFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        await fs.write(file.fd, content);
        await fs.close(file.fd);

        const handler = await this.ensureConnected();
        await handler.uploadTo(tempFilePath, fullPath);
        await fs.unlink(tempFilePath);
      } catch (uploadError) {
        try {
          await fs.unlink(tempFilePath);
        } catch {
          // 忽略清理错误
        }
        const err = uploadError instanceof Error ? uploadError : new Error(String(uploadError));
        throw err;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `${config?.protocol || 'FTP'} write error: ${error.message}`);
      if (error instanceof StorageError) {
        throw error;
      }
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, error.message);
    }
  }

  /**
   * 检查文件是否存在
   */
  public async exists(path: string): Promise<boolean> {
    try {
      const handler = await this.ensureConnected();
      return await handler.exists(this.getFullPath(path));
    } catch (error) {
      if (error instanceof StorageError) {
        const err = error as StorageError;
        if (err.message && err.message.includes('File not found')) {
          return false;
        }
      }
      const err = error instanceof Error ? error : new Error(String(error));
      throw err;
    }
  }

  /**
   * 获取文件信息
   */
  public async getInfo(path: string): Promise<FileInfo> {
    try {
      const handler = await this.ensureConnected();
      const fullPath = this.getFullPath(path);
      const fileInfo = await handler.getFileInfo(fullPath);

      return {
        name: fileInfo.name,
        size: fileInfo.size,
        modifiedTime: fileInfo.modifiedTime,
        path: fullPath,
        type: fileInfo.isDirectory ? FileType.DIR : FileType.FILE,
        childrenCount: 0
      } as FileInfo;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `${this.config?.protocol || 'FTP'} get info error: ${error.message}`);
      if (error instanceof StorageError) {
        throw error;
      }
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, error.message);
    }
  }

  /**
   * 获取目录内容
   */
  public async listDir(path: string): Promise<Array<FileInfo>> {
    try {
      const handler = await this.ensureConnected();
      const fullPath = this.getFullPath(path);
      const files = await handler.listDir(fullPath);
      const result = new Array<FileInfo>();

      for (const file of files) {
        result.push({
          name: file.name,
          size: file.size,
          modifiedTime: file.modifiedTime,
          path: fullPath + (fullPath.endsWith('/') ? '' : '/') + file.name,
          type: file.isDirectory ? FileType.DIR : FileType.FILE,
          childrenCount: 0
        } as FileInfo);
      }

      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `${this.config?.protocol || 'FTP'} list dir error: ${error.message}`);
      if (error instanceof StorageError) {
        throw error;
      }
      throw new StorageError(StorageErrorCodes.NOT_IMPLEMENTED, error.message);
    }
  }

  /**
   * 关闭连接
   */
  public async close(): Promise<void> {
    if (this.handler) {
      await this.handler.close();
      this.handler = undefined;
    }
  }
}
