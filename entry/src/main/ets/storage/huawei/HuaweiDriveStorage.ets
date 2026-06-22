import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HuaweiDriveClient, HuaweiDriveClientOptions, HttpResponse } from './HuaweiDriveClient';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { HuaweiDrivePageConfig, HuaweiDriveStorageConfig } from './HuaweiDriveConfig';
import { OAuth2Config, OAuth2Provider, OAuth2Token, OAuth2TokenStorageService } from '../../common/oauth2';
import { HuaweiDriveOAuth2Config } from './HuaweiDriveOAuth2Provider';
import { ByteUtils } from 'kdbxweb';
import BuildProfile from 'BuildProfile';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDriveStorage';

/**
 * 华为云盘存储实现类
 * 实现IFileStorage接口，提供华为云盘文件存储服务
 */
export class HuaweiDriveStorage implements IFileStorage {
  /**
   * 存储配置
   */
  private config: HuaweiDriveStorageConfig | undefined;
  /**
   * 华为云盘客户端
   */
  private client: HuaweiDriveClient | undefined;
  /**
   * OAuth2配置
   */
  private oauth2Config: OAuth2Config | undefined;

  /**
   * 构造函数
   * @param config 华为云盘存储配置
   */
  constructor(config?: HuaweiDriveStorageConfig) {
    if (config) {
      this.init(config);
    }
  }

  /**
   * 获取页面配置
   * @returns PageConfig 页面配置
   */
  public getPageConfig(): PageConfig {
    return HuaweiDrivePageConfig;
  }

  /**
   * 初始化存储配置
   * @param config 华为云盘存储配置
   */
  public init(config: StorageConfig): void {
    this.config = this.parseConfig(config);
    hilog.debug(DOMAIN, TAG, `HuaweiDriveStorage init: accessToken length=${this.config.getAccessTokenText().length}`);
    if (this.client) {
      this.client.close();
    }

    // 创建OAuth2配置
    const authConfig: HuaweiDriveOAuth2Config = {
      clientId: BuildProfile.HUAWEI_DRIVE_CLIENT_ID,
      clientSecret: BuildProfile.HUAWEI_DRIVE_CLIENT_SECRET,
      authorizationEndpoint: 'https://oauth-login.cloud.huawei.com/oauth2/v3/authorize',
      tokenEndpoint: 'https://oauth-login.cloud.huawei.com/oauth2/v3/token',
      redirectUri: BuildProfile.HUAWEI_DRIVE_REDIRECT_URI,
      scope: this.config.scope || 'https://www.huawei.com/auth/drive',
      provider: OAuth2Provider.HUAWEI_DRIVE
    };
    this.oauth2Config = authConfig;

    // 创建华为云盘客户端
    const clientConfig: HuaweiDriveClientOptions = {
      apiBaseUrl: 'https://drive.cloud.huawei.com/drive/v1',
      accessToken: this.config!.getAccessTokenText(),
      timeout: this.config!.timeout
    };
    hilog.info(DOMAIN, TAG, `Creating HuaweiDriveClient with accessToken length=${clientConfig.accessToken.length}`);
    this.client = new HuaweiDriveClient(clientConfig, this.oauth2Config);
  }

  /**
   * 解析配置
   * @param config 配置对象
   * @returns HuaweiDriveStorageConfig 华为云盘存储配置
   */
  private parseConfig(config: StorageConfig): HuaweiDriveStorageConfig {
    if (config instanceof HuaweiDriveStorageConfig) {
      return config;
    }
    const huaweiDriveConfig = config as HuaweiDriveStorageConfig;
    return new HuaweiDriveStorageConfig(
      huaweiDriveConfig.accessToken,
      huaweiDriveConfig.refreshToken,
      huaweiDriveConfig.expiresAt,
      {
        timeout: huaweiDriveConfig.timeout,
        tokenType: huaweiDriveConfig.tokenType,
        scope: huaweiDriveConfig.scope
      }
    );
  }

  /**
   * 刷新访问令牌
   * @returns Promise<void>
   * @throws StorageError
   */
  private async refreshAccessToken(): Promise<void> {
    if (!this.client || !this.config) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized');
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
        provider: OAuth2Provider.HUAWEI_DRIVE,
        encrypt: true
      });

      hilog.info(DOMAIN, TAG, 'Token updated in preferences');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update token in preferences: %{public}s', (error as Error).message);
    }
  }

  /**
   * 读取文件内容
   * @param path 文件路径（华为云盘使用文件ID作为路径）
   * @returns Promise<ArrayBuffer> 文件内容
   * @throws StorageError
   */
  public async read(path: string): Promise<ArrayBuffer> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

    try {
      const result = await this.client.download(path);
      if (result.success && result.body) {
        return Promise.resolve(result.body);
      }
      return Promise.reject(new Error(result.message));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive readFile error:%{public}s', (error as Error).message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message));
    }
  }

  /**
   * 写入文件内容
   * @param path 文件路径（华为云盘使用文件ID作为路径）
   * @param data 文件内容
   * @returns Promise<void>
   * @throws StorageError 如果写入失败
   */
  public async write(path: string, data: ArrayBuffer): Promise<void> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

    try {
      // 检查文件是否存在
      const fileExists = await this.exists(path);
      let result: HttpResponse;

      if (fileExists) {
        // 更新现有文件
        result = await this.client.update(path, data);
      } else {
        // 创建新文件（在根目录）
        const fileName = path.split('/').pop() || path;
        result = await this.client.upload('root', fileName, data);
      }

      if (!result.success) {
        return Promise.reject(new Error(result.message));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive writeFile error:%{public}s', (error as Error).message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, (error as Error).message));
    }
  }

  /**
   * 检查文件是否存在
   * @param path 文件路径（华为云盘使用文件ID作为路径）
   * @returns Promise<boolean> 文件是否存在
   * @throws StorageError 如果检查失败则抛出异常
   */
  public async exists(path: string): Promise<boolean> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

    const result = await this.client.getInfo(path);
    // 如果成功，文件存在
    if (result.success) {
      return true;
    }
    // 如果失败但状态码是404，文件不存在
    if (result.statusCode === 404) {
      return false;
    }
    // 其他错误，抛出异常
    hilog.error(DOMAIN, TAG, 'Huawei Drive exists error: status=%{public}d, message=%{public}s', result.statusCode, result.message);
    return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, result.message));
  }

  /**
   * 获取文件信息
   * @param path 文件路径（华为云盘使用文件ID作为路径）
   * @returns Promise<FileInfo> 文件信息
   * @throws StorageError 如果获取失败则抛出异常
   */
  public async getInfo(path: string): Promise<FileInfo> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

    const result = await this.client.getInfo(path);
    if (result.success && result.body) {
      const jsonStr = ByteUtils.bytesToString(result.body);
      const data: Record<string, Object> = JSON.parse(jsonStr);
      const file = this.client.parseFile(data);
      return {
        name: file.fileName,
        size: file.size,
        modifiedTime: new Date(file.editedTime).getTime(),
        path: file.id,
        type: file.mimeType === 'application/vnd.huawei.folder' ? FileType.DIR : FileType.FILE,
        childrenCount: 0
      };
    } else {
      throw new Error(result.message);
    }
  }

  /**
   * 获取目录内容
   * @param path 目录路径（华为云盘使用文件夹ID作为路径）
   * @returns Promise<Array<FileInfo>> 目录内容
   * @throws StorageError 如果获取失败则抛出异常
   */
  public async listDir(path: string): Promise<Array<FileInfo>> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

    // 如果路径为空或为根目录，使用 'root'
    const folderId = path && path !== '/' ? path : 'root';
    const result = await this.client.list(folderId);
    if (result.success && result.body) {
      const jsonStr = ByteUtils.bytesToString(result.body);
      const data: Record<string, Object> = JSON.parse(jsonStr);

      hilog.info(DOMAIN, TAG, `listDir response keys: ${Object.keys(data).join(', ')}`);

      const files = this.client.parseFileList(data);
      hilog.info(DOMAIN, TAG, `Parsed ${files.length} files`);

      const fileInfos: FileInfo[] = [];
      for (const file of files) {
        fileInfos.push({
          name: file.fileName,
          size: file.size,
          modifiedTime: new Date(file.editedTime).getTime(),
          path: file.id,
          type: file.mimeType === 'application/vnd.huawei.folder' ? FileType.DIR : FileType.FILE,
          childrenCount: 0
        });
      }

      return fileInfos;
    } else {
      throw new Error(result.message);
    }
  }

  /**
   * 更新存储配置
   * @param config 华为云盘存储配置
   */
  public updateConfig(config: HuaweiDriveStorageConfig): void {
    this.config = config;
    this.init(config);
  }

  /**
   * 获取当前配置
   * @returns HuaweiDriveStorageConfig 存储配置
   */
  public getConfig(): HuaweiDriveStorageConfig | undefined {
    return this.config;
  }
}
