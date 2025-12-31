import { hilog } from '@kit.PerformanceAnalysisKit';
import { Client as FTPClient } from '@ohos/basic-ftp';
import { CommonUtils } from '../../common/utils';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { FileItemInfo, IFTPHandler } from './IFTPHandler';

const DOMAIN = 0x0000;
const TAG = 'FTPHandler';

/**
 * FTP配置接口
 */
export interface FTPConfig {
  host: string;
  port: number;
  username: string;
  password: string;
  secure?: boolean | "implicit";
  timeout?: number;
}

/**
 * FTP处理器
 */
export class FTPHandler implements IFTPHandler {
  private client: FTPClient | undefined;
  private config: FTPConfig;

  constructor(config: FTPConfig) {
    this.config = config;
  }

  /**
   * 连接到FTP服务器
   */
  public async connect(): Promise<void> {
    try {
      if (!this.client) {
        this.client = new FTPClient(CommonUtils.getContext(), this.config.timeout);
      }
      await this.client.access({
        host: this.config.host,
        port: this.config.port,
        user: this.config.username,
        password: this.config.password,
        secure: this.config.secure
      });
      // 连接成功后设置为二进制传输模式
      // TYPE I: 设置数据传输模式为二进制(图片、视频、压缩文件等)
      await this.client.send("TYPE I");
      hilog.info(DOMAIN, TAG, 'FTP connected successfully (binary transfer mode, UTF-8 control encoding)');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'FTP connection failed: ' + error.message);
      throw new StorageError(StorageErrorCodes.CONNECT_ERROR, error.message);
    }
  }

  /**
   * 检查是否已关闭
   */
  public isClosed(): boolean {
    return !this.client;
  }

  /**
   * 关闭连接
   */
  public async close(): Promise<void> {
    if (this.client) {
      this.client.close();
      this.client = undefined;
      hilog.info(DOMAIN, TAG, 'FTP connection closed');
    }
  }

  /**
   * 下载文件到本地
   */
  public async downloadFrom(remotePath: string, localPath: string): Promise<void> {
    if (!this.client) {
      throw new Error('FTP client is not connected');
    }
    hilog.info(DOMAIN, TAG, `Downloading ${remotePath} to ${localPath}`);
    await this.client.downloadTo(localPath, remotePath);
    hilog.info(DOMAIN, TAG, `Download completed: ${remotePath}`);
  }

  /**
   * 上传本地文件到远程
   */
  public async uploadTo(localPath: string, remotePath: string): Promise<void> {
    if (!this.client) {
      throw new Error('FTP client is not connected');
    }
    hilog.info(DOMAIN, TAG, `Uploading ${localPath} to ${remotePath}`);
    await this.client.uploadFrom(remotePath, localPath);
    hilog.info(DOMAIN, TAG, `Upload completed: ${remotePath}`);
  }

  /**
   * 检查文件或目录是否存在
   */
  public async exists(path: string): Promise<boolean> {
    try {
      const fileInfo = await this.getFileInfo(path);
      return fileInfo != null;
    } catch (error) {
      if (error instanceof Error && error.message && error.message.includes('File not found')) {
        return false;
      }
      throw new Error('Failed to check if file exists');
    }
  }

  /**
   * 获取文件信息
   */
  public async getFileInfo(path: string): Promise<FileItemInfo> {
    if (!this.client) {
      throw new Error('FTP client is not connected');
    }

    // 特殊处理根路径
    if (path === '/' || path === '') {
      return {
        name: '/',
        size: 0,
        isDirectory: true,
        modifiedTime: 0
      };
    }

    // 获取文件所在目录的信息
    const dirPath = path.substring(0, path.lastIndexOf('/'));
    const fileName = path.substring(path.lastIndexOf('/') + 1);

    const files = await this.client.list(dirPath);
    let foundIndex: number = -1;
    for (let i = 0; i < files.length; i++) {
      if (files[i].name === fileName) {
        foundIndex = i;
        break;
      }
    }

    if (foundIndex === -1) {
      throw new Error('File not found: ' + path);
    }

    const targetFile = files[foundIndex];
    const fileInfo: FileItemInfo = {
      name: targetFile.name,
      size: targetFile.size,
      isDirectory: targetFile.isDirectory,
      modifiedTime: targetFile.modifiedAt ? targetFile.modifiedAt.getTime() : 0
    };
    return fileInfo;
  }

  /**
   * 列出目录内容
   */
  public async listDir(path: string): Promise<Array<FileItemInfo>> {
    if (!this.client) {
      throw new Error('FTP client is not connected');
    }

    const files = await this.client.list(path);
    const result: FileItemInfo[] = [];

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const fileInfo: FileItemInfo = {
        name: file.name,
        size: file.size,
        isDirectory: file.isDirectory,
        modifiedTime: file.modifiedAt ? file.modifiedAt.getTime() : 0
      };
      result.push(fileInfo);
    }

    hilog.info(DOMAIN, TAG, `Listed ${result.length} items in ${path}`);
    return result;
  }
}
