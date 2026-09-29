import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HuaweiDriveClient, HuaweiDriveClientOptions, HuaweiDriveFile, ParentFolder, HttpResponse } from './HuaweiDriveClient';
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
    // API站点域名（需要加 /drive/v1 前缀）：
    // 全球域名：https://driveapis.cloud.huawei.com.cn/drive/v1
    // 中国站点：https://drive-drcn.cloud.dbankcloud.cn/drive/v1
    // 欧洲站点：https://drive-dre.cloud.dbankcloud.cn/drive/v1
    // 亚非拉站点：https://drive-dra.cloud.dbankcloud.cn/drive/v1
    // 俄罗斯站点：https://drive-drru.cloud.dbankcloud.cn/drive/v1
    const clientConfig: HuaweiDriveClientOptions = {
      apiBaseUrl: 'https://driveapis.cloud.huawei.com.cn/drive/v1',
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
   * 按文件路径查找华为云盘文件对象。
   * IFileStorage 契约传入的是文件路径（如 "test.kdbx" 或 "dir/sub/test.kdbx"），
   * 而华为云盘 API 需要 fileId。本方法通过 list 接口获取文件列表，本地按
   * fileName + parentFolder 逐级匹配，解析出目标文件的 fileId。
   * @param path 文件路径
   * @returns Promise<HuaweiDriveFile | null> 找到返回文件对象，未找到返回 null
   */
  private async findFileByPath(path: string): Promise<HuaweiDriveFile | null> {
    if (!this.client) {
      return null;
    }
    // 规范化路径：去掉开头的 '/'
    const normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    const segments = normalizedPath.split('/').filter((s: string) => s.length > 0);
    if (segments.length === 0) {
      return null;
    }

    // 分页获取全部文件（华为 API 每页最多返回若干条，需通过 nextCursor 翻页）
    const allFiles: HuaweiDriveFile[] = [];
    let cursor: string = '';
    do {
      const queryParam: string | undefined = cursor ? `cursor=${encodeURIComponent(cursor)}` : undefined;
      const result = await this.client.list('root', queryParam);
      if (!result.success || !result.body) {
        hilog.error(DOMAIN, TAG, 'findFileByPath list failed: status=%{public}d', result.statusCode);
        return null;
      }
      const jsonStr = ByteUtils.bytesToString(result.body);
      const data: Record<string, Object> = JSON.parse(jsonStr);
      const files: HuaweiDriveFile[] = this.client.parseFileList(data);
      for (const f of files) {
        allFiles.push(f);
      }
      const nextCursorVal = data['nextCursor'];
      cursor = (nextCursorVal && typeof nextCursorVal === 'string') ? nextCursorVal as string : '';
    } while (cursor);

    // 获取 root 文件夹的真实 id（华为 API 中 "root" 是别名，文件 parentFolder 存的是真实 fileId）
    let currentParentId: string = '';
    for (const file of allFiles) {
      if (file.mimeType === 'application/vnd.huawei-apps.folder' && file.parentFolder.length === 0) {
        currentParentId = file.id;
        break;
      }
    }
    if (!currentParentId) {
      // 兜底：通过 getInfo('root') 获取真实 id
      const rootResp = await this.client.getInfo('root');
      if (rootResp.success && rootResp.body) {
        const rootJson = ByteUtils.bytesToString(rootResp.body);
        const rootData: Record<string, Object> = JSON.parse(rootJson);
        currentParentId = this.client.parseFile(rootData).id;
      }
    }
    if (!currentParentId) {
      hilog.error(DOMAIN, TAG, 'findFileByPath: failed to resolve root folder id');
      return null;
    }
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i];
      const isLast = i === segments.length - 1;
      let found: HuaweiDriveFile | null = null;
      for (const file of allFiles) {
        if (file.fileName === segment && this.containsParent(file.parentFolder, currentParentId)) {
          found = file;
          break;
        }
      }
      if (!found) {
        return null;
      }
      if (isLast) {
        return found;
      }
      // 中间段必须是文件夹才能继续向下查找
      if (found.mimeType !== 'application/vnd.huawei-apps.folder') {
        return null;
      }
      currentParentId = found.id;
    }
    return null;
  }

  /**
   * 判断父文件夹列表中是否包含指定 parentId
   */
  private containsParent(parents: ParentFolder[], parentId: string): boolean {
    for (const p of parents) {
      if (p.id === parentId) {
        return true;
      }
    }
    return false;
  }

  /**
   * 读取文件内容
   * @param path 文件路径
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
      const file = await this.findFileByPath(path);
      if (!file) {
        return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, `File not found: ${path}`));
      }
      const result = await this.client.download(file.id);
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
   * @param path 文件路径
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
      // 按路径查找现有文件，找到则更新，找不到则创建
      const file = await this.findFileByPath(path);
      let result: HttpResponse;

      if (file) {
        // 更新现有文件
        result = await this.client.update(file.id, data);
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
   * @param path 文件路径
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

    try {
      const file = await this.findFileByPath(path);
      return file !== null;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive exists error: %{public}s', (error as Error).message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message));
    }
  }

  /**
   * 获取文件信息
   * @param path 文件路径
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

    try {
      const file = await this.findFileByPath(path);
      if (!file) {
        throw new Error(`File not found: ${path}`);
      }
      return {
        name: file.fileName,
        size: file.size,
        modifiedTime: new Date(file.editedTime).getTime(),
        path: file.id,
        type: file.mimeType === 'application/vnd.huawei.folder' ? FileType.DIR : FileType.FILE,
        childrenCount: 0
      };
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive getInfo error: %{public}s', (error as Error).message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message));
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
