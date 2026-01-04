import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OneDriveClient, OneDriveClientOptions } from './OneDriveClient';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { OneDrivePageConfig, OneDriveStorageConfig } from './OneDriveConfig';
import { OAuth2Config } from '../../common/oauth2';
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
      oneDriveConfig.getAccessTokenText(),
      oneDriveConfig.getRefreshTokenText(),
      oneDriveConfig.timeout,
      oneDriveConfig.expiresAt
    );
  }

  /**
   * 刷新访问令牌
   * @returns Promise<void>
   * @throws 如果刷新失败则抛出异常
   */
  private async refreshAccessToken(): Promise<void> {
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
      hilog.info(DOMAIN, TAG, 'Access token refreshed successfully');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to refresh access token: %{public}s', (error as Error).message);
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message);
    }
  }

  /**
   * 读取文件内容
   * @param path 文件路径
   * @returns Promise<ArrayBuffer> 文件内容
   * @throws 如果读取失败则抛出异常
   */
  public async read(path: string): Promise<ArrayBuffer> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

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
   * @returns Promise<void>
   * @throws 如果写入失败则抛出异常
   */
  public async write(path: string, data: ArrayBuffer): Promise<void> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

    try {
      await this.client.upload(path, data);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'OneDrive writeFile error:%{public}s', (error as Error).message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, (error as Error).message));
    }
  }

  /**
   * 检查文件是否存在
   * @param path 文件路径
   * @returns Promise<boolean> 文件是否存在
   */
  public async exists(path: string): Promise<boolean> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

    const result = await this.client.getInfo(path);
    return result.success;
  }

  /**
   * 获取文件信息
   * @param path 文件路径
   * @returns Promise<FileInfo> 文件信息
   * @throws 如果获取失败则抛出异常
   */
  public async getInfo(path: string): Promise<FileInfo> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

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
        childrenCount: resource.childrenCount || 0
      };
    } else {
      throw new Error(result.message);
    }
  }

  /**
   * 获取目录内容
   * @param path 目录路径
   * @returns Promise<Array<FileInfo>> 目录内容
   * @throws 如果获取失败则抛出异常
   */
  public async listDir(path: string): Promise<Array<FileInfo>> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'OneDrive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'OneDrive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

    const result = await this.client.list(path, 0);
    if (result.success && result.body) {
      const jsonStr = ByteUtils.bytesToString(result.body);
      const data: Record<string, Object> = JSON.parse(jsonStr);
      const files: FileInfo[] = [];

      const value = data['value'];
      if (value && Array.isArray(value)) {
        for (const item of value as Array<Object>) {
          const itemData = item as Record<string, Object>;
          const resource = this.client.parseResource(itemData);
          files.push({
            name: resource.name,
            size: resource.size,
            modifiedTime: new Date(resource.lastModified).getTime(),
            path: resource.path,
            type: resource.type === 'folder' ? FileType.DIR : FileType.FILE,
            childrenCount: resource.childrenCount || 0
          });
        }
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
