import { BaseFileStorage, FileInfo, FileType, PageConfig, WriteOption } from '../index';
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
export class FTPStorage extends BaseFileStorage {
  private config: FTPStorageConfig | undefined;
  private handler: IFTPHandler | undefined;
  private pendingClose: Promise<void> | undefined;
  private opQueue: Promise<void> = Promise.resolve();

  constructor(config?: FTPStorageConfig) {
    super();
    if (config) {
      this.init(config);
    }
  }

  public getPageConfig(): PageConfig {
    return FTPPageConfig;
  }

  public init(config: FTPStorageConfig): void {
    const newConfig = FTPStorage.parseConfig(config);
    // 同配置复用现有 handler，避免 FTPPage 每次操作（测试连接/选目录/保存）都重建 handler 导致控制连接泄漏
    if (this.handler && this.config && FTPStorage.configEqual(this.config, newConfig)) {
      this.config = newConfig;
      return;
    }
    this.config = newConfig;
    this.createHandler();
  }

  private static configEqual(a: FTPStorageConfig, b: FTPStorageConfig): boolean {
    // 比较"连接语义"是否一致。username/password 在 FTPStorageConfig 中是 SM4-CBC 加密存储
    // （随机 IV，非确定性），直接比密文永不相等 → 必须解密比明文，复用优化才真正生效。
    // 解密失败（密文损坏/资产密钥丢失）视为"不相等"走重建，保证 init() 不抛错。
    try {
      return a.host === b.host
        && a.port === b.port
        && a.protocol === b.protocol
        && a.secure === b.secure
        && (a.timeout ?? 0) === (b.timeout ?? 0)
        && a.getUserNameText() === b.getUserNameText()
        && a.getPasswordText() === b.getPasswordText();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'configEqual decrypt failed, treating as not equal: %{public}s', error.message);
      return false;
    }
  }

  public static parseConfig(config: FTPStorageConfig): FTPStorageConfig {
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

    // 旧 handler 不再使用（配置变更或重建），异步关闭避免控制连接泄漏
    //（createHandler 为同步，无法 await；close 触发后异步完成，旧 handler 不再被引用）
    if (this.handler) {
      const oldHandler = this.handler;
      this.pendingClose = oldHandler.close().catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'Failed to close previous handler: %{public}s', e.message);
      });
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

    // 旧连接（换配置场景）先关完再连新的，避免 socket close/connect 系统级并发（EINPROGRESS）
    if (this.pendingClose) {
      await this.pendingClose;
      this.pendingClose = undefined;
    }

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
    if(path === '/'){
      return path;
    }
    const filePath = path.startsWith('/') ? path : '/' + path;
    // 避免重复的斜杠: 如果rootPath以'/'结尾且path以'/'开头,去掉path的前导'/'
    if (filePath.endsWith('/')) {
      return filePath.substring(0, filePath.length - 1);
    }
    return filePath;
  }

  /**
   * 将操作排入串行队列。队列链通过双处理器派生 promise 吞掉前序 op 的失败
   * （失败语义由 op 自身返回的 Promise 传给其调用方），保证一个 op 失败不断链。
   * 调用方契约：xxxOnce 内不得再调用其他 serialize 方法（会自等待死锁）——
   * 当前 5 个 op 互不嵌套，外部链路（KdbxFileManager/CacheStorage/FTPPage）均为顺序 await。
   */
  private serialize<T>(op: () => Promise<T>): Promise<T> {
    const run: Promise<T> = this.opQueue.then(() => op());
    // 队列链只关心"前一个完成"，吞掉失败避免断链；失败语义由 op 自身的 Promise 传给调用方
    this.opQueue = run.then(() => {
    }, () => {
    });
    return run;
  }

  /**
   * 读取文件内容
   */
  public read(path: string): Promise<ArrayBuffer> {
    return this.serialize(() => this.readOnce(path));
  }

  private async readOnce(path: string): Promise<ArrayBuffer> {
    const config = this.config;
    try {
      const fullPath = this.getFullPath(path);
      const tempDir = CommonUtils.getCacheDir();
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
   * @param path 文件路径
   * @param content 文件内容
   * @param option 写入选项，传入 expectedVersion 时写前 stat 复核（SFTP stat / FTP MLSD）
   */
  public write(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void> {
    return this.serialize(() => this.writeOnce(path, content, option));
  }

  private async writeOnce(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void> {
    const config = this.config;
    try {
      const fullPath = this.getFullPath(path);
      const tempDir = CommonUtils.getCacheDir();
      const tempFilePath = tempDir + '/temp_upload_' + Date.now() + '.tmp';

      try {
        const file = await fs.open(tempFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        await fs.write(file.fd, content);
        await fs.close(file.fd);

        const handler = await this.ensureConnected();
        // 条件写入：写前复核远端版本（size|mtime 复合），不一致说明已被其他设备修改
        const expectedVersion: string | null = option?.expectedVersion ?? null;
        if (expectedVersion !== null) {
          const remoteInfo = await handler.getFileInfo(fullPath);
          const currentVersion = `${remoteInfo.size}|${remoteInfo.modifiedTime}`;
          if (currentVersion !== expectedVersion) {
            hilog.warn(DOMAIN, TAG, 'Version conflict, path: %{public}s, expected: %{public}s, current: %{public}s',
              fullPath, expectedVersion, currentVersion);
            throw new StorageError(StorageErrorCodes.VERSION_CONFLICT, 'Remote file version changed');
          }
        }
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
   * 流式下载到本地文件（FTP/SFTP socket 直写文件，不驻留整缓冲，修 P9）
   * 复用底层 handler.downloadFrom 的文件传输能力（basic-ftp 已具备）
   */
  public readToFile(path: string, destPath: string): Promise<FileInfo> {
    return this.serialize(() => this.readToFileOnce(path, destPath));
  }

  private async readToFileOnce(path: string, destPath: string): Promise<FileInfo> {
    try {
      const fullPath = this.getFullPath(path);
      const handler = await this.ensureConnected();
      await handler.downloadFrom(fullPath, destPath);
      // 直接调 getInfoOnce（已在 serialize 队列内，跳过二次排队避免死锁）
      return await this.getInfoOnce(path);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, `${this.config?.protocol || 'FTP'} readToFile error: ${err.message}`);
      if (error instanceof StorageError) {
        throw error;
      }
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, err.message);
    }
  }

  /**
   * 流式从本地文件上传（FTP/SFTP socket 直读文件，不驻留整缓冲）
   * 复用底层 handler.uploadFrom 的文件传输能力；条件写入复用 writeOnce 的版本复核逻辑
   */
  public writeFromFile(path: string, srcPath: string, option?: WriteOption): Promise<FileInfo> {
    return this.serialize(() => this.writeFromFileOnce(path, srcPath, option));
  }

  private async writeFromFileOnce(path: string, srcPath: string, option?: WriteOption): Promise<FileInfo> {
    const config = this.config;
    try {
      const fullPath = this.getFullPath(path);
      const handler = await this.ensureConnected();
      // 条件写入：写前复核远端版本（与 writeOnce 一致）
      const expectedVersion: string | null = option?.expectedVersion ?? null;
      if (expectedVersion !== null) {
        const remoteInfo = await handler.getFileInfo(fullPath);
        const currentVersion = `${remoteInfo.size}|${remoteInfo.modifiedTime}`;
        if (currentVersion !== expectedVersion) {
          hilog.warn(DOMAIN, TAG, 'Version conflict, path: %{public}s, expected: %{public}s, current: %{public}s',
            fullPath, expectedVersion, currentVersion);
          throw new StorageError(StorageErrorCodes.VERSION_CONFLICT, 'Remote file version changed');
        }
      }
      await handler.uploadTo(srcPath, fullPath);
      // 上传后取远端 FileInfo（直接调 getInfoOnce 避免二次排队死锁）
      return await this.getInfoOnce(path);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, `${config?.protocol || 'FTP'} writeFromFile error: ${err.message}`);
      if (error instanceof StorageError) {
        throw error;
      }
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, err.message);
    }
  }

  /**
   * 检查文件是否存在
   */
  public exists(path: string): Promise<boolean> {
    return this.serialize(() => this.existsOnce(path));
  }

  private async existsOnce(path: string): Promise<boolean> {
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
   * 获取文件信息；确定不存在时返回 null，无法判定（网络/权限等）时上抛。
   * FTP 走 "File not found" 消息标记；SFTP 标记缺失时以 exists 复核（handler 内部语义判定）
   */
  public getInfoOrNull(path: string): Promise<FileInfo | null> {
    return this.serialize(() => this.getInfoOrNullOnce(path));
  }

  private async getInfoOrNullOnce(path: string): Promise<FileInfo | null> {
    const handler = await this.ensureConnected();
    const fullPath = this.getFullPath(path);
    try {
      const fileInfo = await handler.getFileInfo(fullPath);
      const info: FileInfo = {
        name: fileInfo.name,
        size: fileInfo.size,
        modifiedTime: fileInfo.modifiedTime,
        path: fullPath,
        type: fileInfo.isDirectory ? FileType.DIR : FileType.FILE,
        childrenCount: 0,
        version: `${fileInfo.size}|${fileInfo.modifiedTime}`
      };
      return info;
    } catch (error) {
      if (FTPStorage.isFileNotFoundMarker(error)) {
        return null;
      }
      // SFTP 的 stat 错误不含 "File not found" 标记：以 exists 复核（内部按协议语义判定）
      try {
        const existed = await handler.exists(fullPath);
        if (!existed) {
          return null;
        }
      } catch {
        // 复核失败：按原始错误上抛
      }
      if (error instanceof StorageError) {
        throw error;
      }
      const err = error instanceof Error ? error : new Error(String(error));
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, err.message);
    }
  }

  private static isFileNotFoundMarker(error: Object): boolean {
    if (error instanceof StorageError) {
      return (error as StorageError).message.includes('File not found');
    }
    if (error instanceof Error) {
      return error.message.includes('File not found');
    }
    return false;
  }

  /**
   * 获取文件信息
   * 复用 getInfoOrNullOnce 单一探测（serialize 包裹保持连接串行；null 映射为 FILE_INFO_ERROR）
   */
  public getInfo(path: string): Promise<FileInfo> {
    return this.serialize(() => this.getInfoOnce(path));
  }

  /**
   * 获取文件信息（serialize 队列内直调版）：null 映射为 FILE_INFO_ERROR；
   * 连接失败等裸错误补包装为 FILE_INFO_ERROR（保持旧 getInfoOnce 契约，含 sftp 码标记）
   */
  private async getInfoOnce(path: string): Promise<FileInfo> {
    try {
      const info: FileInfo | null = await this.getInfoOrNullOnce(path);
      if (info === null) {
        throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, 'File not found: ' + path);
      }
      return info;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `${this.config?.protocol || 'FTP'} get info error: ${error.message}`);
      if (error instanceof StorageError) {
        throw error;
      }
      const err = error instanceof Error ? error : new Error(String(error));
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, err.message);
    }
  }

  /**
   * 获取目录内容
   */
  public listDir(path: string): Promise<Array<FileInfo>> {
    return this.serialize(() => this.listDirOnce(path));
  }

  private async listDirOnce(path: string): Promise<Array<FileInfo>> {
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
   * 关闭连接。close() 不走 serialize 队列（关闭是清理语义，允许插队）；
   * 若 handler.close() reject，this.handler 有意保留——isClosed() 为 true 时
   * ensureConnected 会丢弃重建（自愈），置 undefined 反而丢失该路径。
   */
  public async close(): Promise<void> {
    if (this.handler) {
      await this.handler.close();
      this.handler = undefined;
    }
  }
}
