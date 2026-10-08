import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig, WriteOption } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OneDriveClient, OneDriveClientOptions } from './OneDriveClient';
import { HTTP_UPLOAD_MAX_BYTES, StorageError, StorageErrorCodes } from '../StorageError';
import { FileTransfer } from '../FileTransfer';
import { OneDrivePageConfig, OneDriveStorageConfig } from './OneDriveConfig';
import { OAuth2Config, OAuth2Provider, OAuth2Token, OAuth2TokenStorageService } from '../../common/oauth2';
import { OneDriveOAuth2Config } from './OneDriveOAuth2Provider';
import { ByteUtils } from 'kdbxweb';
import BuildProfile from 'BuildProfile';

const DOMAIN = 0x0000;
const TAG = 'OneDriveStorage';

/**
 * OneDrive存储实现类
 * 实现IFileStorage接口，提供OneDrive文件存储服务
 */
export class OneDriveStorage implements IFileStorage {
  /**
   * 存储配置
   */
  private config: OneDriveStorageConfig | undefined;
  /**
   * OneDrive客户端
   */
  private client: OneDriveClient | undefined;
  /**
   * OAuth2配置
   */
  private oauth2Config: OAuth2Config | undefined;

  /**
   * 进行中的刷新 Promise（并发去重，避免多个操作同时刷新）
   * 刷新完成（成功或失败）后置空
   */
  private refreshingPromise: Promise<void> | null = null;

  /**
   * 构造函数
   * @param config OneDrive存储配置
   */
  constructor(config?: OneDriveStorageConfig) {
    if (config) {
      this.init(config);
    }
  }

  /**
   * 获取页面配置
   * @returns PageConfig 页面配置
   */
  public getPageConfig(): PageConfig {
    return OneDrivePageConfig;
  }

  /**
   * 初始化存储配置
   * @param config OneDrive存储配置
   */
  public init(config: StorageConfig): void {
    this.config = this.parseConfig(config);
    hilog.debug(DOMAIN, TAG, `OneDriveStorage init: accessToken length=${this.config.getAccessTokenText().length}`);
    if (this.client) {
      this.client.close();
    }

    // 创建OAuth2配置
    const authConfig: OneDriveOAuth2Config = {
      clientId: BuildProfile.ONE_DRIVE_CLIENT_ID,
      clientSecret: BuildProfile.ONE_DRIVE_CLIENT_SECRET,
      authorizationEndpoint: `https://login.microsoftonline.com/${BuildProfile.ONE_DRIVE_TENANT_ID}/oauth2/v2.0/authorize`,
      tokenEndpoint: `https://login.microsoftonline.com/${BuildProfile.ONE_DRIVE_TENANT_ID}/oauth2/v2.0/token`,
      redirectUri:  BuildProfile.ONE_DRIVE_REDIRECT_URI,
      scope: 'Files.ReadWrite User.Read offline_access'
    };
    this.oauth2Config = authConfig;

    // 创建OneDrive客户端
    const clientConfig: OneDriveClientOptions = {
      apiBaseUrl: 'https://graph.microsoft.com/v1.0',
      accessToken: this.config!.getAccessTokenText(),
      timeout: this.config!.timeout
    };
    hilog.info(DOMAIN, TAG, `Creating OneDriveClient with accessToken length=${clientConfig.accessToken.length}`);
    this.client = new OneDriveClient(clientConfig, this.oauth2Config);
  }

  /**
   * 解析配置
   * @param config 配置对象
   * @returns OneDriveStorageConfig OneDrive存储配置
   */
  private parseConfig(config: StorageConfig): OneDriveStorageConfig {
    if (config instanceof OneDriveStorageConfig) {
      return config;
    }
    const oneDriveConfig = config as OneDriveStorageConfig;
    return new OneDriveStorageConfig(
      oneDriveConfig.accessToken,
      oneDriveConfig.refreshToken,
      oneDriveConfig.expiresAt,
      {
        timeout: oneDriveConfig.timeout,
        tokenType: oneDriveConfig.tokenType,
        scope: oneDriveConfig.scope
      }
    );
  }

  /**
   * 确保访问令牌有效（令牌生命周期归共享 token store 管理，不依赖单次操作的配置快照）
   * 1. 配置快照内 token 仍有效：直接返回（零开销）
   * 2. 快照已过期：先读共享 token store（文件后端，Worker 内同样可用，承载上次刷新落盘的新 token），
   *    账号一致（refreshToken 相同）且未过期 → 应用到当前实例，免刷新
   * 3. store 也无可用 token：真正刷新（单飞）→ 成功后经 notifyTokenUpdated 持久化回 store
   * 注意：OneDrive 刷新可能轮换 refresh_token，store 内 token 与配置快照的 refreshToken 不一致时
   * 视为账号变化/轮换失配，仍走配置快照刷新（与既有行为一致，不降低安全性）
   */
  private async ensureValidToken(): Promise<void> {
    if (!this.client || !this.config) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized');
    }
    if (!this.config.isTokenExpired()) {
      return;
    }
    const config = this.config;
    const client = this.client;
    try {
      const stored: OAuth2Token | null = await OAuth2TokenStorageService.getInstance()
        .loadToken({ provider: OAuth2Provider.ONEDRIVE, encrypt: true });
      if (stored && stored.accessToken && stored.expiresAt
        && stored.refreshToken === config.getRefreshTokenText()
        && stored.expiresAt > Date.now() + 5 * 60 * 1000) {
        config.setAccessToken(stored.accessToken);
        if (stored.refreshToken) {
          config.setRefreshToken(stored.refreshToken);
        }
        config.setExpiresAt(stored.expiresAt);
        client.updateAccessToken(stored.accessToken);
        hilog.info(DOMAIN, TAG, 'Applied stored access token, expires at: %{public}s',
          stored.expiresAt?.toString());
        return;
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Load stored token failed, fallback to refresh: %{public}s',
        (error as Error).message);
    }
    await this.refreshAccessToken();
  }

  /**
   * 刷新访问令牌（并发去重：多个操作同时触发刷新时复用同一个 Promise）
   * @returns Promise<void>
   * @throws StorageError
   */
  private async refreshAccessToken(): Promise<void> {
    if (!this.client || !this.config) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized');
    }

    // 并发去重：已有刷新在进行中，复用该 Promise
    if (this.refreshingPromise) {
      hilog.debug(DOMAIN, TAG, 'refreshAccessToken: another refresh in progress, waiting for it');
      return this.refreshingPromise;
    }

    this.refreshingPromise = this.doRefreshAccessToken();
    try {
      await this.refreshingPromise;
    } finally {
      this.refreshingPromise = null;
    }
  }

  /**
   * 实际执行刷新逻辑
   */
  private async doRefreshAccessToken(): Promise<void> {
    if (!this.client || !this.config) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized');
    }
    try {
      const token = await this.client.refreshToken(this.config.getRefreshTokenText());
      this.config.setAccessToken(token.accessToken);
      if (token.refreshToken) {
        this.config.setRefreshToken(token.refreshToken);
      }
      if (token.expiresAt) {
        this.config.setExpiresAt(token.expiresAt);
      }
      this.client.updateAccessToken(token.accessToken);

      // 发送令牌更新事件
      await this.notifyTokenUpdated(token);

      hilog.info(DOMAIN, TAG, 'Access token refreshed successfully');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to refresh access token: %{public}s', (error as Error).message);
      throw new StorageError(StorageErrorCodes.CONNECT_ERROR, (error as Error).message);
    }
  }

  /**
   * 通知令牌已更新
   * @param token 更新后的令牌
   */
  private async notifyTokenUpdated(token: OAuth2Token): Promise<void> {
    try {
      // 保存到首选项
      const storageService = OAuth2TokenStorageService.getInstance();
      await storageService.updateToken(token, {
        provider: OAuth2Provider.ONEDRIVE,
        encrypt: true
      });
      
      hilog.info(DOMAIN, TAG, 'Token updated in preferences');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update token in preferences: %{public}s', (error as Error).message);
    }
  }

  /**
   * 流式下载到本地文件（OneDrive 当前走默认整缓冲；requestInStream 流式下载为 S7 调研项）
   */
  public async readToFile(path: string, destPath: string): Promise<FileInfo> {
    return FileTransfer.readToFileDefault(this, path, destPath);
  }

  /**
   * 流式从本地文件上传（S7-a：Graph upload session 分片上传）
   * 小文件（<4MB）简单 PUT；大文件创建会话后按 5MB 分片从源文件区域读取 PUT，
   * 内存窗口 = 单分片，与文件大小解耦；CP-UP 仅约束整缓冲 write 路径，此路径豁免。
   * 条件写入：传入 expectedVersion 时写前复核远端 eTag 版本，不一致抛出版本冲突
   * @throws StorageError(VERSION_CONFLICT) 远端版本与期望不一致
   * @throws StorageError(FILE_WRITE_ERROR) 上传失败（含会话过期）
   */
  public async writeFromFile(path: string, srcPath: string, option?: WriteOption): Promise<FileInfo> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // 检查令牌是否过期
    await this.ensureValidToken();

    try {
      const expectedVersion: string | null = option?.expectedVersion ?? null;
      if (expectedVersion !== null) {
        await this.checkVersionUnchanged(path, expectedVersion);
      }
      const result = await this.client.uploadFromFile(path, srcPath);
      if (!result.success) {
        return Promise.reject(new Error(result.message));
      }
    } catch (error) {
      // 版本冲突直接透传，保持错误码不被改写
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      hilog.error(DOMAIN, TAG, 'OneDrive writeFromFile error:%{public}s', (error as Error).message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, (error as Error).message));
    }
    return await this.getInfo(path);
  }

  /**
   * 条件写入：写前复核远端版本（Graph eTag 复合串），不一致抛出版本冲突
   * 远端不存在（新库首存）或探测失败时放行，由后续上传环节自行报错（对齐 S3 语义）
   * @param path 文件路径
   * @param expectedVersion 期望的远端版本
   * @throws StorageError(VERSION_CONFLICT) 版本不一致时抛出
   */
  private async checkVersionUnchanged(path: string, expectedVersion: string): Promise<void> {
    try {
      const currentInfo: FileInfo = await this.getInfo(path);
      const currentVersion: string | null = currentInfo.version ?? null;
      if (currentVersion !== expectedVersion) {
        hilog.warn(DOMAIN, TAG, 'OneDrive version conflict, path: %{public}s, expected: %{public}s, current: %{public}s',
          path, expectedVersion, currentVersion);
        throw new StorageError(StorageErrorCodes.VERSION_CONFLICT, 'OneDrive file version changed');
      }
    } catch (error) {
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      // 远端不存在或探测失败：放行（fail-open），由上传环节自行报错
    }
  }

  /**
   * 构建不透明版本标识：Graph eTag 与 Last-Modified 复合串
   * 两者皆空返回 null（由上层内容哈希兜底）
   * @param eTag Graph driveItem eTag
   * @param lastModified 最后修改时间字符串
   */
  private static buildVersion(eTag: string | undefined, lastModified: string): string | null {
    const normalizedEtag: string = eTag ?? '';
    if (!normalizedEtag && !lastModified) {
      return null;
    }
    return `${normalizedEtag}|${lastModified}`;
  }

  /**
   * 读取文件内容
   * @param path 文件路径
   * @returns Promise<ArrayBuffer> 文件内容
   * @throws StorageError
   */
  public async read(path: string): Promise<ArrayBuffer> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // 检查令牌是否过期
    await this.ensureValidToken();

    try {
      const result = await this.client.get(path);
      if (result.success && result.body) {
        return Promise.resolve(result.body);
      }
      return Promise.reject(new Error(result.message));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'OneDrive readFile error:%{public}s', (error as Error).message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message));
    }
  }

  /**
   * 写入文件内容
   * @param path 文件路径
   * @param data 文件内容
   * @param option 写入选项，传入 expectedVersion 时写前复核远端 eTag 版本（条件写入）
   * @returns Promise<void>
   * @throws StorageError 如果写入失败
   */
  public async write(path: string, data: ArrayBuffer, option?: WriteOption): Promise<void> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // CP-UP：整缓冲上传超过 http 栈上限必然失败，提前拒绝并给出明确原因
    if (data.byteLength > HTTP_UPLOAD_MAX_BYTES) {
      throw new StorageError(StorageErrorCodes.UPLOAD_TOO_LARGE, `${data.byteLength} bytes`);
    }

    // 检查令牌是否过期
    await this.ensureValidToken();

    try {
      // 条件写入：写前复核远端版本，不一致抛出版本冲突由上层重试/合并兜底
      const expectedVersion: string | null = option?.expectedVersion ?? null;
      if (expectedVersion !== null) {
        await this.checkVersionUnchanged(path, expectedVersion);
      }
      const result = await this.client.upload(path, data);
      if (!result.success) {
        return Promise.reject(new Error(result.message));
      }
    } catch (error) {
      // 版本冲突直接透传，保持错误码不被改写
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      hilog.error(DOMAIN, TAG, 'OneDrive writeFile error:%{public}s', (error as Error).message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, (error as Error).message));
    }
  }

  /**
   * 获取文件信息；404 返回 null，其他错误上抛（无法判定）
   * @param path 文件路径
   * @returns Promise<FileInfo | null> 文件信息，确定不存在时为 null
   * @throws StorageError 如果检查失败则抛出异常
   */
  public async getInfoOrNull(path: string): Promise<FileInfo | null> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // 检查令牌是否过期
    await this.ensureValidToken();

    const result = await this.client.getInfo(path);
    if (result.success && result.body) {
      const jsonStr = ByteUtils.bytesToString(result.body);
      const data: Record<string, Object> = JSON.parse(jsonStr);
      const resource = this.client.parseResource(data);
      const info: FileInfo = {
        name: resource.name,
        size: resource.size,
        modifiedTime: new Date(resource.lastModified).getTime(),
        path: resource.path,
        type: resource.type === 'folder' ? FileType.DIR : FileType.FILE,
        childrenCount: resource.childrenCount || 0,
        version: OneDriveStorage.buildVersion(resource.eTag, resource.lastModified)
      };
      return info;
    }
    // 状态码 404：文件不存在
    if (result.statusCode === 404) {
      return null;
    }
    // 其他错误，抛出异常
    hilog.error(DOMAIN, TAG, 'OneDrive getInfoOrNull error: status=%{public}d, message=%{public}s', result.statusCode, result.message);
    return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, result.message));
  }

  /**
   * 检查文件是否存在
   * @param path 文件路径
   * @returns Promise<boolean> 文件是否存在
   * @throws StorageError 如果检查失败则抛出异常
   */
  public async exists(path: string): Promise<boolean> {
    return (await this.getInfoOrNull(path)) !== null;
  }

  /**
   * 获取文件信息
   * @param path 文件路径
   * @returns Promise<FileInfo> 文件信息
   * @throws StorageError 如果获取失败则抛出异常
   */
  public async getInfo(path: string): Promise<FileInfo> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // 检查令牌是否过期
    await this.ensureValidToken();

    const result = await this.client.getInfo(path);
    if (result.success && result.body) {
      const jsonStr = ByteUtils.bytesToString(result.body);
      const data: Record<string, Object> = JSON.parse(jsonStr);
      const resource = this.client.parseResource(data);
      return {
        name: resource.name,
        size: resource.size,
        modifiedTime: new Date(resource.lastModified).getTime(),
        path: resource.path,
        type: resource.type === 'folder' ? FileType.DIR : FileType.FILE,
        childrenCount: resource.childrenCount || 0,
        version: OneDriveStorage.buildVersion(resource.eTag, resource.lastModified)
      };
    } else {
      throw new Error(result.message);
    }
  }

  /**
   * 获取目录内容
   * @param path 目录路径
   * @returns Promise<Array<FileInfo>> 目录内容
   * @throws StorageError 如果获取失败则抛出异常
   */
  public async listDir(path: string): Promise<Array<FileInfo>> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // 检查令牌是否过期
    await this.ensureValidToken();

    const result = await this.client.list(path, 0);
    if (result.success && result.body) {
      const jsonStr = ByteUtils.bytesToString(result.body);
      const data: Record<string, Object> = JSON.parse(jsonStr);

      hilog.info(DOMAIN, TAG, `listDir response keys: ${Object.keys(data).join(', ')}`);

      const resources = this.client.parseResourceList(data);
      hilog.info(DOMAIN, TAG, `Parsed ${resources.length} resources`);

      const files: FileInfo[] = [];
      for (const resource of resources) {
        files.push({
          name: resource.name,
          size: resource.size,
          modifiedTime: new Date(resource.lastModified).getTime(),
          path: resource.path,
          type: resource.type === 'folder' ? FileType.DIR : FileType.FILE,
          childrenCount: resource.childrenCount || 0,
          version: OneDriveStorage.buildVersion(resource.eTag, resource.lastModified)
        });
      }

      return files;
    } else {
      throw new Error(result.message);
    }
  }

  /**
   * 更新存储配置
   * @param config OneDrive存储配置
   */
  public updateConfig(config: OneDriveStorageConfig): void {
    this.config = config;
    this.init(config);
  }

  /**
   * 获取当前配置
   * @returns OneDriveStorageConfig 存储配置
   */
  public getConfig(): OneDriveStorageConfig | undefined {
    return this.config;
  }
}
