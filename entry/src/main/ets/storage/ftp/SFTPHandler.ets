import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { DisconnectReason, Client as SSHClient, connect as sshConnect } from '@ohos-rs/ssh';
import { FileItemInfo, IFTPHandler } from './IFTPHandler';
import { util } from '@kit.ArkTS';
import { ByteUtils } from 'kdbxweb'

const DOMAIN = 0x0000;
const TAG = 'SFTPHandler';

/**
 * SFTP配置接口
 */
export interface SFTPConfig {
  host: string;
  port: number;
  username: string;
  password: string;
  timeout?: number;
}

/**
 * SFTP处理器，使用SSH执行SFTP命令
 */
export class SFTPHandler implements IFTPHandler {
  private client: SSHClient | undefined;
  private config: SFTPConfig;

  constructor(config: SFTPConfig) {
    this.config = config;
  }

  /**
   * 连接到SFTP服务器
   */
  public async connect(): Promise<void> {
    try {
      this.client = await sshConnect(`${this.config.host}:${this.config.port}`);
      const authenticated = await this.client.authenticatePassword(this.config.username, this.config.password);
      if (!authenticated) {
        throw new Error('SFTP authentication failed');
      }
      hilog.info(DOMAIN, TAG, 'SFTP connected successfully');
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, 'SFTP connection failed: ' + err.message);
      throw err;
    }
  }

  /**
   * 检查是否已关闭
   */
  public isClosed(): boolean {
    return !this.client || this.client.isClosed() === true;
  }

  /**
   * 关闭连接
   */
  public async close(): Promise<void> {
    if (this.client && !this.client.isClosed()) {
      await this.client.disconnect(DisconnectReason.ByApplication, 'Normal close', 'en');
    }
    this.client = undefined;
    hilog.info(DOMAIN, TAG, 'SFTP connection closed');
  }

  /**
   * 执行命令并返回输出
   */
  private async exec(command: string): Promise<string> {
    if (!this.client || this.client.isClosed()) {
      throw new Error('SFTP client is not connected');
    }
    const result = await this.client.exec(command);
    if (result.status !== 0) {
      throw new Error(`Command failed with status ${result.status}: ${command}`);
    }
    const uint8Array = new Uint8Array(result.output as ArrayBuffer);
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeWithStream(uint8Array);
  }

  /**
   * 检查文件或目录是否存在
   */
  public async exists(path: string): Promise<boolean> {
    try {
      await this.exec(`test -e "${path}"`);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * 检查是否是目录
   */
  private async isDirectory(path: string): Promise<boolean> {
    try {
      await this.exec(`test -d "${path}"`);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * 获取文件信息
   */
  public async getFileInfo(path: string): Promise<FileItemInfo> {
    try {
      const statOutput = await this.exec(`stat -c "%s %Y" "${path}"`);
      const parts = statOutput.trim().split(' ');
      const size = parseInt(parts[0]) || 0;
      const modifiedTime = parseInt(parts[1]) || 0;
      const isDirectory = await this.isDirectory(path);
      const name = path.substring(path.lastIndexOf('/') + 1);
      const fileInfo: FileItemInfo = {
        name,
        size,
        isDirectory,
        modifiedTime
      };
      return fileInfo;
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, `Failed to get file info for ${path}: ${err.message}`);
      throw new Error(`Failed to get file info for ${path}: ${err.message}`);
    }
  }

  /**
   * 列出目录内容
   */
  public async listDir(path: string): Promise<Array<FileItemInfo>> {
    try {
      const lsOutput = await this.exec(`ls -la --time-style="+%Y-%m-%d %H:%M:%S" "${path}"`);
      const lines = lsOutput.trim().split('\n');
      const result: FileItemInfo[] = [];

      for (const line of lines) {
        const trimmedLine = line.trim();
        // 跳过total行和 . / ..
        if (!trimmedLine || trimmedLine.startsWith('total')) {
          continue;
        }
        // 跳过 . 和 .. 目录
        const parts = trimmedLine.split(/\s+/);
        if (parts.length >= 8) {
          const name = parts.slice(7).join(' ');
          if (name === '.' || name === '..') {
            continue;
          }
          const isDirectory = parts[0].startsWith('d');
          const size = parseInt(parts[4]) || 0;
          // 时间格式: 2024-01-15 10:30:45，在 parts[5] 和 parts[6]
          const dateStr = parts[5] + ' ' + parts[6];
          const modifiedTime = this.parseDate(dateStr);
          const fileInfo: FileItemInfo = {
            name,
            size,
            isDirectory,
            modifiedTime
          };
          result.push(fileInfo);
        }
      }
      hilog.info(DOMAIN, TAG, `Listed ${result.length} items in ${path}`);
      return result;
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, `Failed to list directory ${path}: ${err.message}`);
      throw new Error(`Failed to list directory ${path}: ${err.message}`);
    }
  }

  /**
   * 解析日期字符串为时间戳
   * 格式: "YYYY-MM-DD HH:MM:SS"
   */
  private parseDate(dateStr: string): number {
    try {
      const parts = dateStr.split(' ');
      if (parts.length >= 2) {
        const datePart = parts[0];
        const timePart = parts[1];
        const dateParts = datePart.split('-');
        const timeParts = timePart.split(':');
        const year = parseInt(dateParts[0]) || 0;
        const month = parseInt(dateParts[1]) || 0;
        const day = parseInt(dateParts[2]) || 0;
        const hour = parseInt(timeParts[0]) || 0;
        const minute = parseInt(timeParts[1]) || 0;
        const second = parseInt(timeParts[2]) || 0;
        const date = new Date(year, month - 1, day, hour, minute, second, 0);
        return date.getTime();
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Failed to parse date: ${dateStr}`);
    }
    return 0;
  }

  /**
   * 下载文件到本地
   */
  public async downloadFrom(remotePath: string, localPath: string): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, `Downloading ${remotePath} to ${localPath}`);
      const output = await this.exec(`cat "${remotePath}" | base64`);
      const buffer = ByteUtils.base64ToBytes(output.trim()).buffer;
      const file = await fs.open(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      await fs.write(file.fd, buffer);
      await fs.close(file.fd);
      hilog.info(DOMAIN, TAG, `Download completed: ${remotePath}`);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, `Failed to download ${remotePath}: ${err.message}`);
      throw new Error(`Failed to download ${remotePath}: ${err.message}`);
    }
  }

  /**
   * 上传本地文件到远程
   */
  public async uploadTo(localPath: string, remotePath: string): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, `Uploading ${localPath} to ${remotePath}`);
      const file = await fs.open(localPath, fs.OpenMode.READ_ONLY);
      const fileInfo = await fs.stat(file.fd);
      const buffer = new ArrayBuffer(fileInfo.size);
      await fs.read(file.fd, buffer);
      await fs.close(file.fd);

      const base64Content = ByteUtils.bytesToBase64(buffer);
      await this.exec(`echo "${base64Content}" | base64 -d > "${remotePath}"`);
      hilog.info(DOMAIN, TAG, `Upload completed: ${remotePath}`);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, `Failed to upload ${localPath}: ${err.message}`);
      throw new Error(`Failed to upload ${localPath}: ${err.message}`);
    }
  }
}
