import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { SshClient } from 'sftp-ohos';
import { TransferProgressCallback } from '../IFileStorage';
import { FileItemInfo, IFTPHandler } from './IFTPHandler';

const DOMAIN = 0x0000;
const TAG = 'SFTPHandler';

/** 默认连接超时（毫秒） */
const DEFAULT_TIMEOUT_MS = 30000;
/** 流式传输分块大小（原生层按 SFTP 数据包上限自动裁剪） */
const TRANSFER_CHUNK_SIZE = 256 * 1024; // 256KB

/**
 * SFTP 错误码（与 libs/sftp-ohos/src/error.rs 保持一致）
 */
export enum SftpErrorCode {
  UNKNOWN = 0,
  NETWORK_ERROR = 1,
  TIMEOUT = 2,
  AUTH_FAILED = 3,
  HANDSHAKE_FAILED = 4,
  CHANNEL_ERROR = 5,
  SFTP_ERROR = 6,
  NO_SUCH_FILE = 7,
  DISPOSED = 8,
  NOT_CONNECTED = 9,
  BAD_HANDLE = 10
}

/** 错误码映射表：数值 → 枚举 */
const SFTP_CODE_MAP: Map<number, SftpErrorCode> = new Map([
  [0, SftpErrorCode.UNKNOWN],
  [1, SftpErrorCode.NETWORK_ERROR],
  [2, SftpErrorCode.TIMEOUT],
  [3, SftpErrorCode.AUTH_FAILED],
  [4, SftpErrorCode.HANDSHAKE_FAILED],
  [5, SftpErrorCode.CHANNEL_ERROR],
  [6, SftpErrorCode.SFTP_ERROR],
  [7, SftpErrorCode.NO_SUCH_FILE],
  [8, SftpErrorCode.DISPOSED],
  [9, SftpErrorCode.NOT_CONNECTED],
  [10, SftpErrorCode.BAD_HANDLE]
]);

/**
 * 从错误信息中解析 SFTP 错误码。
 * 原生层错误消息编码格式为 `[sftp:{code}] {detail}`。
 */
export function parseSftpErrorCode(message: string): SftpErrorCode {
  const match = message.match(/\[sftp:(\d+)\]/);
  if (match !== null && match.length > 1) {
    const code = parseInt(match[1]);
    const mapped = SFTP_CODE_MAP.get(code);
    if (mapped !== undefined) {
      return mapped;
    }
  }
  return SftpErrorCode.UNKNOWN;
}

/**
 * 携带错误码的 SFTP 异常
 */
export class SftpError extends Error {
  readonly code: SftpErrorCode;

  constructor(code: SftpErrorCode, message: string) {
    super(message);
    this.name = 'SftpError';
    this.code = code;
  }
}

/**
 * SFTP配置接口
 */
export interface SFTPConfig {
  host: string;
  port: number;
  username: string;
  password: string;
  /** 连接超时（毫秒），默认 30000 */
  timeout?: number;
  /** keepalive 心跳间隔（秒），默认 30；0 禁用 */
  keepaliveSec?: number;
}

/**
 * SFTP处理器，基于原生 sftp-ohos（russh + russh-sftp）协议级实现。
 *
 * 与旧 exec 方案的本质差异：`exists` 仅在服务器明确报告"文件不存在"时
 * 返回 false，网络/超时等错误一律上抛，避免"最近文件"记录被误删。
 */
export class SFTPHandler implements IFTPHandler {
  private client: SshClient | undefined;
  private config: SFTPConfig;

  constructor(config: SFTPConfig) {
    this.config = config;
  }

  /**
   * 连接并完成认证 + SFTP 子系统初始化
   */
  public async connect(): Promise<void> {
    const client = new SshClient();
    try {
      // 重连场景：先释放旧实例
      this.releaseClient();

      const timeoutMs = this.config.timeout && this.config.timeout > 0 ? this.config.timeout : DEFAULT_TIMEOUT_MS;
      await client.connect({
        host: this.config.host,
        port: this.config.port,
        timeoutSec: Math.ceil(timeoutMs / 1000),
        keepaliveSec: this.config.keepaliveSec
      });

      const authenticated = await client.authenticatePassword(this.config.username, this.config.password);
      if (!authenticated) {
        throw new SftpError(SftpErrorCode.AUTH_FAILED, 'SFTP authentication failed');
      }

      await client.sftpInit();
      this.client = client;
      hilog.info(DOMAIN, TAG, 'SFTP connected successfully');
    } catch (error) {
      // 失败清理：断开半开连接并释放原生资源，不依赖 GC 兜底
      try {
        await client.disconnect();
      } catch {
        // 忽略断开异常
      }
      client.dispose();
      const err = SFTPHandler.wrapError(error, 'SFTP connection failed');
      hilog.error(DOMAIN, TAG, err.message);
      throw err;
    }
  }

  /**
   * 检查是否已关闭（含断线感知：服务器掐断 / keepalive 超时）
   */
  public isClosed(): boolean {
    return this.client === undefined || this.client.isClosed();
  }

  /**
   * 关闭连接并释放原生资源
   */
  public async close(): Promise<void> {
    const client = this.client;
    this.client = undefined;
    if (client === undefined) {
      return;
    }
    try {
      await client.sftpShutdown();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `sftpShutdown warning: ${String(error)}`);
    }
    try {
      await client.disconnect();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `disconnect warning: ${String(error)}`);
    }
    client.dispose();
    hilog.info(DOMAIN, TAG, 'SFTP connection closed');
  }

  /**
   * 检查文件或目录是否存在。
   * 仅"明确不存在"返回 false，网络/超时/权限等错误上抛。
   */
  public async exists(path: string): Promise<boolean> {
    try {
      return await this.requireClient().sftpExists(path);
    } catch (error) {
      const err = SFTPHandler.wrapError(error, `Failed to check existence of ${path}`);
      hilog.error(DOMAIN, TAG, err.message);
      throw err;
    }
  }

  /**
   * 获取文件信息
   */
  public async getFileInfo(path: string): Promise<FileItemInfo> {
    // 特殊处理根路径
    if (path === '/' || path === '') {
      const rootInfo: FileItemInfo = {
        name: '/',
        size: 0,
        isDirectory: true,
        modifiedTime: 0
      };
      return rootInfo;
    }

    try {
      const stat = await this.requireClient().sftpStat(path);
      const fallbackName = path.substring(path.lastIndexOf('/') + 1);
      const info: FileItemInfo = {
        name: stat.name.length > 0 ? stat.name : fallbackName,
        size: stat.size,
        isDirectory: stat.isDir,
        modifiedTime: stat.mtime * 1000
      };
      return info;
    } catch (error) {
      const err = SFTPHandler.wrapError(error, `Failed to get file info for ${path}`);
      hilog.error(DOMAIN, TAG, err.message);
      throw err;
    }
  }

  /**
   * 列出目录内容（跳过 . 与 ..）
   */
  public async listDir(path: string): Promise<Array<FileItemInfo>> {
    try {
      const entries = await this.requireClient().sftpListDir(path);
      const result: Array<FileItemInfo> = [];
      for (const entry of entries) {
        const info: FileItemInfo = {
          name: entry.name,
          size: entry.size,
          isDirectory: entry.isDir,
          modifiedTime: entry.mtime * 1000
        };
        result.push(info);
      }
      hilog.info(DOMAIN, TAG, `Listed ${result.length} items in ${path}`);
      return result;
    } catch (error) {
      const err = SFTPHandler.wrapError(error, `Failed to list directory ${path}`);
      hilog.error(DOMAIN, TAG, err.message);
      throw err;
    }
  }

  /**
   * 下载远程文件到本地（SFTP 流式读取 + 大小校验）
   * @param onProgress 下载进度回调（可选）：每分块落盘后上报（已接收字节 / 远端 stat 总字节）
   */
  public async downloadFrom(remotePath: string, localPath: string,
    onProgress?: TransferProgressCallback): Promise<void> {
    let client: SshClient | undefined = undefined;
    let handle = -1;
    try {
      client = this.requireClient();
      const stat = await client.sftpStat(remotePath);
      const fileSize = stat.size;
      hilog.debug(DOMAIN, TAG, `Downloading ${remotePath} (${fileSize} bytes) -> ${localPath}`);

      handle = await client.sftpOpenRead(remotePath);
      const file = await fs.open(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < fileSize) {
          const chunk = await client.sftpRead(handle, TRANSFER_CHUNK_SIZE);
          if (chunk.byteLength === 0) {
            break; // 远端提前 EOF
          }
          await fs.write(file.fd, chunk, { offset: offset });
          offset += chunk.byteLength;
          if (onProgress) {
            onProgress(offset, fileSize);
          }
        }
      } finally {
        try {
          await fs.close(file.fd);
        } catch (error) {
          hilog.warn(DOMAIN, TAG, `Failed to close local file: ${String(error)}`);
        }
      }

      // 校验下载完整性
      const localFile = await fs.open(localPath, fs.OpenMode.READ_ONLY);
      const localStat = await fs.stat(localFile.fd);
      await fs.close(localFile.fd);
      if (localStat.size !== fileSize) {
        throw new SftpError(SftpErrorCode.SFTP_ERROR,
          `Download verification failed: expected ${fileSize} bytes, got ${localStat.size} bytes`);
      }
      hilog.debug(DOMAIN, TAG, `Download completed: ${remotePath} (${fileSize} bytes)`);
    } catch (error) {
      const err = SFTPHandler.wrapError(error, `Failed to download ${remotePath}`);
      hilog.error(DOMAIN, TAG, err.message);
      throw err;
    } finally {
      await SFTPHandler.closeHandleQuietly(client, handle);
    }
  }

  /**
   * 上传本地文件到远程（SFTP 流式写入 + 大小校验）
   * @param onProgress 上传进度回调（可选）：每分块 sftpWrite 确认后上报（已发送字节 / 本地 stat 总字节）
   */
  public async uploadTo(localPath: string, remotePath: string,
    onProgress?: TransferProgressCallback): Promise<void> {
    let client: SshClient | undefined = undefined;
    let handle = -1;
    const file = await fs.open(localPath, fs.OpenMode.READ_ONLY);
    try {
      const localStat = await fs.stat(file.fd);
      const fileSize = localStat.size;
      hilog.debug(DOMAIN, TAG, `Uploading ${localPath} (${fileSize} bytes) -> ${remotePath}`);

      client = this.requireClient();
      handle = await client.sftpOpenWrite(remotePath);

      let offset = 0;
      while (offset < fileSize) {
        const chunkSize = Math.min(TRANSFER_CHUNK_SIZE, fileSize - offset);
        const buffer = new ArrayBuffer(chunkSize);
        const readLen = await fs.read(file.fd, buffer, { offset: offset });
        if (readLen === 0) {
          break; // 本地文件提前 EOF
        }
        const data = readLen === chunkSize ? buffer : buffer.slice(0, readLen);
        await client.sftpWrite(handle, data);
        offset += readLen;
        if (onProgress) {
          onProgress(offset, fileSize);
        }
      }
    } catch (error) {
      const err = SFTPHandler.wrapError(error, `Failed to upload ${localPath}`);
      hilog.error(DOMAIN, TAG, err.message);
      throw err;
    } finally {
      try {
        await fs.close(file.fd);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, `Failed to close local file: ${String(error)}`);
      }
      await SFTPHandler.closeHandleQuietly(client, handle);
    }

    // 校验上传完整性（句柄关闭后远端大小才是最终值）
    if (client !== undefined) {
      const remoteStat = await client.sftpStat(remotePath);
      const localStat = await fs.stat(localPath);
      if (remoteStat.size !== localStat.size) {
        const err = new SftpError(SftpErrorCode.SFTP_ERROR,
          `Upload verification failed: expected ${localStat.size} bytes, got ${remoteStat.size} bytes`);
        hilog.error(DOMAIN, TAG, err.message);
        throw err;
      }
      hilog.debug(DOMAIN, TAG, `Upload completed: ${remotePath} (${remoteStat.size} bytes)`);
    }
  }

  /**
   * 获取已连接的客户端，未连接时抛出 NOT_CONNECTED
   */
  private requireClient(): SshClient {
    if (this.client === undefined || this.client.isClosed()) {
      throw new SftpError(SftpErrorCode.NOT_CONNECTED, 'SFTP client is not connected');
    }
    return this.client;
  }

  /**
   * 释放旧客户端实例（重连前清理）
   */
  private releaseClient(): void {
    const client = this.client;
    this.client = undefined;
    client?.dispose();
  }

  /**
   * 静默关闭远端文件句柄
   */
  private static async closeHandleQuietly(client: SshClient | undefined, handle: number): Promise<void> {
    if (client === undefined || handle < 0) {
      return;
    }
    try {
      await client.sftpClose(handle);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Failed to close sftp handle: ${String(error)}`);
    }
  }

  /**
   * 将任意异常转换为 SftpError（保留原生错误码与消息）
   */
  private static wrapError(error: Object, context: string): SftpError {
    if (error instanceof SftpError) {
      return error;
    }
    const raw = error instanceof Error ? error.message : String(error);
    return new SftpError(parseSftpErrorCode(raw), `${context}: ${raw}`);
  }
}
