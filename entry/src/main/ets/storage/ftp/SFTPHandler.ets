import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { DisconnectReason, Client as SSHClient, connect as sshConnect } from '@ohos-rs/ssh';
import { FileItemInfo, IFTPHandler } from './IFTPHandler';
import { util } from '@kit.ArkTS';
import { ByteUtils } from 'kdbxweb';
import { CommonUtils } from '../../common/utils';

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
  // 上传分块大小：64KB，更小的块以避免连接超时
  private static readonly UPLOAD_CHUNK_SIZE = 64 * 1024; // 64KB
  // 下载分块大小：256KB
  private static readonly DOWNLOAD_CHUNK_SIZE = 256 * 1024; // 256KB

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
   * 下载文件到本地（支持大文件分块下载）
   */
  public async downloadFrom(remotePath: string, localPath: string): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, `Starting download: ${remotePath} -> ${localPath}`);

      // 获取文件大小
      const fileInfo = await this.getFileInfo(remotePath);
      const fileSize = fileInfo.size;

      hilog.info(DOMAIN, TAG, `Remote file size: ${fileSize} bytes`);

      // 对于大文件，使用分块读取
      if (fileSize > SFTPHandler.DOWNLOAD_CHUNK_SIZE) {
        await this.downloadInChunks(remotePath, localPath, fileSize);
      } else {
        // 小文件使用单次读取
        // 使用base64 -w 0避免在输出中添加换行符
        const output = await this.exec(`cat "${remotePath}" | base64 -w 0`);
        const buffer = ByteUtils.base64ToBytes(output.trim()).buffer;
        const file = await fs.open(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        await fs.write(file.fd, buffer);
        await fs.close(file.fd);
      }

      // 验证下载的文件大小
      const localFile = await fs.open(localPath, fs.OpenMode.READ_ONLY);
      const localStat = await fs.stat(localFile.fd);
      await fs.close(localFile.fd);

      if (localStat.size !== fileSize) {
        throw new Error(`Download verification failed: expected ${fileSize} bytes, got ${localStat.size} bytes`);
      }

      hilog.info(DOMAIN, TAG, `Download completed: ${remotePath} (${localStat.size} bytes)`);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, `Failed to download ${remotePath}: ${err.message}`);
      throw new Error(`Failed to download ${remotePath}: ${err.message}`);
    }
  }

  /**
   * 分块下载大文件
   */
  private async downloadInChunks(remotePath: string, localPath: string, totalSize: number): Promise<void> {
    const localFile = await fs.open(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    let offset = 0;
    let chunkCount = 0;
    const totalChunks = Math.ceil(totalSize / SFTPHandler.DOWNLOAD_CHUNK_SIZE);

    try {
      while (offset < totalSize) {
        const remainingBytes = totalSize - offset;
        const currentChunkSize = Math.min(SFTPHandler.DOWNLOAD_CHUNK_SIZE, remainingBytes);
        chunkCount++;

        hilog.info(DOMAIN, TAG, `Downloading chunk ${chunkCount}/${totalChunks}: offset=${offset}, size=${currentChunkSize}`);

        // 使用dd命令分块读取并base64编码
        // 使用base64 -w 0避免在输出中添加换行符
        const base64Chunk = await this.exec(
          `dd if="${remotePath}" bs=1 skip=${offset} count=${currentChunkSize} 2>/dev/null | base64 -w 0`
        );

        const buffer = ByteUtils.base64ToBytes(base64Chunk.trim()).buffer;
        await fs.write(localFile.fd, buffer);

        offset += currentChunkSize;
      }
    } finally {
      await fs.close(localFile.fd);
    }
  }

  /**
   * 上传本地文件到远程（支持大文件分块上传）
   */
  public async uploadTo(localPath: string, remotePath: string): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, `Starting upload: ${localPath} -> ${remotePath}`);

      // 读取本地文件信息
      const file = await fs.open(localPath, fs.OpenMode.READ_ONLY);
      const fileInfo = await fs.stat(file.fd);
      const fileSize = fileInfo.size;

      hilog.info(DOMAIN, TAG, `Local file size: ${fileSize} bytes`);

      // 对于大文件，使用分块上传
      if (fileSize > SFTPHandler.UPLOAD_CHUNK_SIZE) {
        await this.uploadInChunks(localPath, remotePath, fileSize);
      } else {
        // 小文件使用单次上传
        const buffer = new ArrayBuffer(fileInfo.size);
        await fs.read(file.fd, buffer);
        await fs.close(file.fd);

        const base64Content = ByteUtils.bytesToBase64(buffer);
        // 使用printf避免echo的换行符问题
        // 转义单引号以避免shell解析问题
        const escapedContent = base64Content.replace(/'/g, "'\\''");
        const command = `printf '%s' '${escapedContent}' | base64 -d > "${remotePath}"`;
        await this.exec(command);
      }

      // 验证上传的文件大小
      const remoteFileInfo = await this.getFileInfo(remotePath);
      if (remoteFileInfo.size !== fileSize) {
        throw new Error(`Upload verification failed: expected ${fileSize} bytes, got ${remoteFileInfo.size} bytes`);
      }

      hilog.info(DOMAIN, TAG, `Upload completed: ${remotePath} (${fileSize} bytes)`);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, `Failed to upload ${localPath}: ${err.message}`);
      throw new Error(`Failed to upload ${localPath}: ${err.message}`);
    }
  }

  /**
   * 分块上传大文件 - 使用更保守的64KB块大小
   */
  private async uploadInChunks(localPath: string, remotePath: string, totalSize: number): Promise<void> {
    const file = await fs.open(localPath, fs.OpenMode.READ_ONLY);
    let offset = 0;
    let chunkCount = 0;
    const totalChunks = Math.ceil(totalSize / SFTPHandler.UPLOAD_CHUNK_SIZE);

    try {
      // 使用远程临时文件
      const tempRemotePath = `/tmp/sftp_upload_${Date.now()}_${Math.random().toString(36).substr(2, 9)}.tmp`;

      // 确保临时文件为空
      try {
        await this.exec(`: > "${tempRemotePath}"`);
      } catch {
        // 忽略创建失败
      }

      while (offset < totalSize) {
        const remainingBytes = totalSize - offset;
        const currentChunkSize = Math.min(SFTPHandler.UPLOAD_CHUNK_SIZE, remainingBytes);
        chunkCount++;

        hilog.info(DOMAIN, TAG, `Uploading chunk ${chunkCount}/${totalChunks}: offset=${offset}, size=${currentChunkSize}`);

        const buffer = new ArrayBuffer(currentChunkSize);
        const readLen = await fs.read(file.fd, buffer, { offset: offset });

        if (readLen === 0) {
          break;
        }

        // 调整buffer大小为实际读取的字节数
        const actualBuffer = buffer.slice(0, readLen);
        const base64Chunk = ByteUtils.bytesToBase64(actualBuffer);

        // 使用printf输出，避免heredoc的问题
        // 转义单引号
        const escapedChunk = base64Chunk.replace(/'/g, "'\\''");
        const command = `printf '%s' '${escapedChunk}' >> "${tempRemotePath}"`;
        await this.exec(command);

        offset += readLen;
      }

      // 将base64临时文件解码到目标位置
      hilog.info(DOMAIN, TAG, `Decoding uploaded chunks to ${remotePath}`);
      // 先检查临时文件大小
      const tempSizeOutput = await this.exec(`wc -c < "${tempRemotePath}"`);
      hilog.info(DOMAIN, TAG, `Temp base64 file size: ${tempSizeOutput.trim()} bytes`);

      await this.exec(`base64 -d < "${tempRemotePath}" > "${remotePath}"`);

      // 清理临时文件
      try {
        await this.exec(`rm -f "${tempRemotePath}"`);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `Failed to clean temp file: ${e}`);
      }
    } finally {
      await fs.close(file.fd);
    }
  }
}
