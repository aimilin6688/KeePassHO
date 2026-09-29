import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  HuaweiDriveClient,
  HuaweiDriveClientOptions,
  HuaweiDriveFile,
  HuaweiDriveAbout,
  HUAWEI_DRIVE_FOLDER_MIME_TYPE,
  ParentFolder,
  HttpResponse
} from './HuaweiDriveClient';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { HuaweiDrivePageConfig, HuaweiDriveStorageConfig } from './HuaweiDriveConfig';
import { OAuth2Config, OAuth2Provider, OAuth2Token, OAuth2TokenStorageService } from '../../common/oauth2';
import { HuaweiDriveOAuth2Config } from './HuaweiDriveOAuth2Provider';
import { ByteUtils } from 'kdbxweb';
import BuildProfile from 'BuildProfile';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDriveStorage';

/**
 * 路径→fileId 映射缓存上限，超过后清空重建，避免无限增长
 */
const PATH_ID_CACHE_LIMIT = 200;

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
   * 文件路径→fileId 映射缓存
   * listDir 时建立映射，read/getInfo/exists/delete 时优先查缓存命中 fileId，
   * 避免 findFileByPath 逐级 list 下钻带来的多次 API 调用
   */
  private pathIdCache: Map<string, string> = new Map();

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
    // 重新初始化可能切换了账号，清空路径→fileId 缓存，避免命中上一个账号的失效 fileId
    this.pathIdCache.clear();
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
   * 按文件路径或 fileId 查找华为云盘文件对象。
   * 查找顺序：
   * 1. 路径→fileId 缓存命中 → client.getInfo(fileId)（1次API，最高效）
   * 2. path 当 fileId 直接查询（兼容旧流程直接传 fileId 的场景）
   * 3. 逐级路径解析（list 下钻，兜底）
   * @param path 文件路径或 fileId
   * @returns Promise<HuaweiDriveFile | null> 找到返回文件对象，未找到返回 null
   */
  private async findFileByPath(path: string): Promise<HuaweiDriveFile | null> {
    if (!this.client) {
      return null;
    }
    // 规范化路径：去掉开头的 '/'
    const normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    if (!normalizedPath) {
      return null;
    }

    // 1. 优先查路径→fileId 缓存，命中则直接 getInfo(fileId)
    const cachedFileId = this.pathIdCache.get(path);
    if (cachedFileId) {
      try {
        const cachedResp = await this.client.getInfo(cachedFileId);
        if (cachedResp.success && cachedResp.body) {
          const jsonStr = ByteUtils.bytesToString(cachedResp.body);
          const data: Record<string, Object> = JSON.parse(jsonStr);
          const file = this.client.parseFile(data);
          if (file.id) {
            return file;
          }
        }
      } catch {
        // 缓存的 fileId 可能已失效，清除后继续走其他方式
        this.pathIdCache.delete(path);
      }
    }

    // 2. 尝试将 path 当作 fileId 直接查询
    try {
      const directResp = await this.client.getInfo(normalizedPath);
      if (directResp.success && directResp.body) {
        const jsonStr = ByteUtils.bytesToString(directResp.body);
        const data: Record<string, Object> = JSON.parse(jsonStr);
        const file = this.client.parseFile(data);
        if (file.id) {
          return file;
        }
      }
    } catch {
      // 不是有效的 fileId，继续走路径解析
    }

    // 3. 路径解析：逐级下钻
    const segments = normalizedPath.split('/').filter((s: string) => s.length > 0);
    if (segments.length === 0) {
      return null;
    }

    // 解析根目录真实 id（华为 API 中 "root" 是别名，文件 parentFolder 存的是真实 fileId）
    let currentParentId: string = await this.resolveRootFolderId();
    if (!currentParentId) {
      hilog.error(DOMAIN, TAG, 'findFileByPath: failed to resolve root folder id');
      return null;
    }

    // 逐级下钻：每层都 list(currentParentId) 获取该层子文件，再匹配当前段
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i];
      const isLast = i === segments.length - 1;
      const filesInFolder = await this.listFilesInFolder(currentParentId);
      let found: HuaweiDriveFile | null = null;
      for (const file of filesInFolder) {
        if (file.fileName === segment) {
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
      if (found.mimeType !== HUAWEI_DRIVE_FOLDER_MIME_TYPE) {
        return null;
      }
      currentParentId = found.id;
    }
    return null;
  }

  /**
   * 解析根目录真实 fileId
   * 先通过 list('root') 查找 parentFolder 为空的文件夹；找不到则通过 getInfo('root') 兜底
   * @returns Promise<string> 根目录 id，失败返回空字符串
   */
  private async resolveRootFolderId(): Promise<string> {
    if (!this.client) {
      return '';
    }
    const rootFiles = await this.listFilesInFolder('root');
    for (const file of rootFiles) {
      if (file.mimeType === HUAWEI_DRIVE_FOLDER_MIME_TYPE && file.parentFolder.length === 0) {
        return file.id;
      }
    }
    // 兜底：通过 getInfo('root') 获取真实 id
    const rootResp = await this.client.getInfo('root');
    if (rootResp.success && rootResp.body) {
      const rootJson = ByteUtils.bytesToString(rootResp.body);
      const rootData: Record<string, Object> = JSON.parse(rootJson);
      return this.client.parseFile(rootData).id;
    }
    return '';
  }

  /**
   * 列出指定文件夹下的所有文件（支持分页）
   * @param folderId 文件夹ID
   * @returns Promise<HuaweiDriveFile[]> 文件列表
   */
  private async listFilesInFolder(folderId: string): Promise<HuaweiDriveFile[]> {
    if (!this.client) {
      return [];
    }
    const allFiles: HuaweiDriveFile[] = [];
    let cursor: string = '';
    do {
      const result = await this.client.list(folderId, cursor || undefined);
      if (!result.success || !result.body) {
        hilog.error(DOMAIN, TAG, 'listFilesInFolder failed: status=%{public}d', result.statusCode);
        return allFiles;
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
    return allFiles;
  }

  /**
   * 逐级查找或创建文件夹路径，返回末级文件夹 id
   * 用于 write() 创建新文件时确保父目录存在
   * @param segments 文件夹路径段数组
   * @returns Promise<string> 末级文件夹 id
   */
  private async resolveOrCreateFolderPath(segments: string[]): Promise<string> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized');
    }
    let currentParentId: string = await this.resolveRootFolderId();
    if (!currentParentId) {
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, 'Failed to resolve root folder id');
    }
    for (const segment of segments) {
      const filesInFolder = await this.listFilesInFolder(currentParentId);
      let found: HuaweiDriveFile | null = null;
      for (const file of filesInFolder) {
        if (file.fileName === segment && file.mimeType === HUAWEI_DRIVE_FOLDER_MIME_TYPE) {
          found = file;
          break;
        }
      }
      if (found) {
        currentParentId = found.id;
      } else {
        // 文件夹不存在，创建
        const createResp = await this.client.createFolder(currentParentId, segment);
        if (!createResp.success || !createResp.body) {
          throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR,
            `Failed to create folder: ${segment}, ${createResp.message}`);
        }
        const jsonStr = ByteUtils.bytesToString(createResp.body);
        const data: Record<string, Object> = JSON.parse(jsonStr);
        const folder = this.client.parseFile(data);
        currentParentId = folder.id;
      }
    }
    return currentParentId;
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
        // 创建新文件：解析父目录路径，逐级查找/创建文件夹，再上传到末级目录
        const normalizedPath = path.startsWith('/') ? path.substring(1) : path;
        const segments = normalizedPath.split('/').filter((s: string) => s.length > 0);
        const fileName = segments.pop() || path;
        const parentFolderId = segments.length > 0
          ? await this.resolveOrCreateFolderPath(segments)
          : await this.resolveRootFolderId();
        if (!parentFolderId) {
          return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR,
            'Failed to resolve parent folder'));
        }
        result = await this.client.upload(parentFolderId, fileName, data);
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

    // 根目录：通过 getInfo('root') 验证连通性，成功即存在
    const normalizedForRoot = path.startsWith('/') ? path.substring(1) : path;
    if (!normalizedForRoot) {
      try {
        const rootResp = await this.client.getInfo('root');
        return rootResp.success;
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Huawei Drive exists root error: %{public}s', (error as Error).message);
        return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message));
      }
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
      // 根目录：直接通过 getInfo('root') 获取根文件夹信息
      const normalizedForRoot = path.startsWith('/') ? path.substring(1) : path;
      if (!normalizedForRoot) {
        const rootResp = await this.client.getInfo('root');
        if (!rootResp.success || !rootResp.body) {
          throw new Error(rootResp.message || `Failed to get root info`);
        }
        const rootJson = ByteUtils.bytesToString(rootResp.body);
        const rootData: Record<string, Object> = JSON.parse(rootJson);
        const rootFile = this.client.parseFile(rootData);
        return {
          name: rootFile.fileName || 'root',
          size: rootFile.size,
          modifiedTime: new Date(rootFile.editedTime).getTime(),
          path: rootFile.id || 'root',
          type: FileType.DIR,
          childrenCount: 0
        };
      }

      const file = await this.findFileByPath(path);
      if (!file) {
        throw new Error(`File not found: ${path}`);
      }
      return {
        name: file.fileName,
        size: file.size,
        modifiedTime: new Date(file.editedTime).getTime(),
        path: file.id,
        type: file.mimeType === HUAWEI_DRIVE_FOLDER_MIME_TYPE ? FileType.DIR : FileType.FILE,
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

    // 将路径解析为文件夹 fileId
    // 根目录直接用 'root'；非根目录先查缓存，缓存未命中则通过 findFileByPath 解析
    let folderId: string;
    if (!path || path === '/') {
      folderId = 'root';
    } else {
      const cachedId = this.pathIdCache.get(path);
      if (cachedId) {
        folderId = cachedId;
      } else {
        const folder = await this.findFileByPath(path);
        if (!folder) {
          throw new Error(`Directory not found: ${path}`);
        }
        folderId = folder.id;
      }
    }

    // 分页获取目录内容
    const allFiles: HuaweiDriveFile[] = [];
    let cursor: string = '';
    do {
      const result = await this.client.list(folderId, cursor || undefined);
      if (!result.success || !result.body) {
        throw new Error(result.message || 'Failed to list directory');
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

    hilog.info(DOMAIN, TAG, `listDir: path=${path}, folderId=${folderId}, files=${allFiles.length}`);

    const fileInfos: FileInfo[] = [];
    // 构造当前目录路径前缀，用于拼接子项的 path（保证 getFileName 能提取真实文件名）
    const basePath = path.endsWith('/') ? path : path + '/';
    for (const file of allFiles) {
      const itemPath = basePath + file.fileName;
      // 建立路径→fileId 映射缓存，供后续 read/getInfo/exists/delete 直接命中
      this.cachePathId(itemPath, file.id);
      fileInfos.push({
        name: file.fileName,
        size: file.size,
        modifiedTime: new Date(file.editedTime).getTime(),
        path: itemPath,
        type: file.mimeType === HUAWEI_DRIVE_FOLDER_MIME_TYPE ? FileType.DIR : FileType.FILE,
        childrenCount: 0
      });
    }

    return fileInfos;
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

  /**
   * 获取云盘汇总信息（用户显示名、总容量、已用容量）
   * @returns Promise<HuaweiDriveAbout> 汇总信息
   * @throws StorageError 如果获取失败则抛出异常
   */
  public async getAbout(): Promise<HuaweiDriveAbout> {
    if (!this.client) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive not init:%{public}s', JSON.stringify(this.config));
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized'));
    }

    // 检查令牌是否过期
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }

    try {
      const result = await this.client.getAbout();
      if (!result.success || !result.body) {
        throw new Error(result.message || 'Failed to get about info');
      }
      const jsonStr = ByteUtils.bytesToString(result.body);
      const data: Record<string, Object> = JSON.parse(jsonStr);
      return this.client.parseAbout(data);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive getAbout error: %{public}s', (error as Error).message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message));
    }
  }

  /**
   * 删除文件
   * @param path 文件路径
   * @throws StorageError 如果删除失败则抛出异常
   */
  public async delete(path: string): Promise<void> {
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
        return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, `File not found: ${path}`));
      }
      const result = await this.client.delete(file.id);
      if (!result.success) {
        return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, result.message));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive delete error: %{public}s', (error as Error).message);
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, (error as Error).message));
    }
  }

  /**
   * 缓存路径→fileId 映射，超过上限时清空最早的一半，避免无限增长
   * @param path 文件路径
   * @param fileId 华为云盘文件ID
   */
  private cachePathId(path: string, fileId: string): void {
    if (this.pathIdCache.size >= PATH_ID_CACHE_LIMIT) {
      // 简单淘汰：清空缓存重建（Map 保持插入顺序，这里不做精细 LRU）
      this.pathIdCache.clear();
    }
    this.pathIdCache.set(path, fileId);
  }

  /**
   * 关闭华为云盘存储连接，释放资源
   * 应在使用完毕后调用此方法以释放 axios 实例
   */
  public close(): void {
    if (this.client) {
      this.client.close();
      this.client = undefined;
    }
    this.config = undefined;
    this.pathIdCache.clear();
  }
}
