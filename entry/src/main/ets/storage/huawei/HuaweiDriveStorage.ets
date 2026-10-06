import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig, WriteOption } from '../index';
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
import { HTTP_UPLOAD_MAX_BYTES, StorageError, StorageErrorCodes } from '../StorageError';
import { FileTransfer } from '../FileTransfer';
import { HuaweiDrivePageConfig, HuaweiDriveStorageConfig } from './HuaweiDriveConfig';
import { HuaweiDrivePathCacheData, HuaweiDrivePathCacheEntry, HuaweiDrivePathCacheStore } from './HuaweiDrivePathCacheStore';
import { OAuth2Config, OAuth2Provider, OAuth2Token, OAuth2TokenStorageService } from '../../common/oauth2';
import { HuaweiDriveOAuth2Config } from './HuaweiDriveOAuth2Provider';
import { ByteUtils } from 'kdbxweb';
import { BusinessError } from '@kit.BasicServicesKit';
import BuildProfile from 'BuildProfile';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDriveStorage';

/**
 * 路径→fileId 映射缓存上限，超过后清空重建，避免无限增长
 */
const PATH_ID_CACHE_LIMIT = 200;
/**
 * 持久化防抖延迟（毫秒）：合并短时间内的多次缓存变更，一次落盘
 */
const PATH_CACHE_PERSIST_DELAY = 500;

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
   * 文件路径→fileId 映射缓存（静态，跨实例共享）
   * listDir/findFileByPath 时建立映射，read/getInfo/exists/delete 时优先查缓存命中 fileId，
   * 避免 findFileByPath 逐级 list 下钻带来的多次 API 调用。
   * 工厂单例与文件浏览页的独立实例共享同一缓存，同一账号内避免重复解析同一路径；
   * 账号切换时在 init() 中按 cacheOwnerKey 统一清空。
   */
  private static pathIdCache: Map<string, string> = new Map();
  /**
   * 根目录真实 fileId 缓存（静态，跨实例共享）
   * 同一账号内根目录 id 不变，避免每次 findFileByPath 都 list('root')+getInfo('root')
   */
  private static rootFolderId: string = '';
  /**
   * 缓存所属账号指纹（refreshToken 明文，仅驻内存；落盘前经 SHA-256 截断）
   * init() 时与当前配置比对，不一致则清空 pathIdCache/rootFolderId，避免命中其他账号的失效 fileId
   */
  private static cacheOwnerKey: string = '';
  /**
   * 磁盘缓存是否已水合到内存（配合 hydratePromise 单飞，整个进程只加载一次）
   */
  private static cacheHydrated: boolean = false;
  /**
   * 进行中的水合 Promise（并发去重）
   */
  private static hydratePromise: Promise<void> | null = null;
  /**
   * 防抖落盘定时器 id（-1 表示无待写任务）
   */
  private static persistTimer: number = -1;
  /**
   * 正在进行的刷新 Promise（并发去重，避免多个操作同时刷新）
   * 刷新完成（成功或失败）后置空
   */
  private refreshingPromise: Promise<void> | null = null;

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
    // 账号切换时清空路径→fileId 缓存，避免命中上一个账号的失效 fileId；
    // 同一账号重复 init（每次 KdbxFileManager 构造都会触发）时保留缓存，避免重复的路径解析请求
    const ownerKey = this.config.getRefreshTokenText();
    if (HuaweiDriveStorage.cacheOwnerKey !== ownerKey) {
      HuaweiDriveStorage.cacheOwnerKey = ownerKey;
      HuaweiDriveStorage.pathIdCache.clear();
      HuaweiDriveStorage.rootFolderId = '';
      // 重置水合状态：下次解析前重新尝试从磁盘加载新账号的缓存
      // （磁盘若残留其他账号的数据，水合时按 owner 指纹比对后会被丢弃）
      HuaweiDriveStorage.cacheHydrated = false;
      HuaweiDriveStorage.hydratePromise = null;
      hilog.debug(DOMAIN, TAG, 'Account changed, path id cache cleared');
    }
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
   * 并发去重：多个操作同时触发刷新时复用同一个 Promise，避免并发刷新冲突
   * refresh_token 失效（400 + sub_error）时清理持久化 token 并抛 AUTH_EXPIRED
   * @returns Promise<void>
   * @throws StorageError AUTH_EXPIRED（需重新登录）/ CONNECT_ERROR（网络等）
   */
  private async refreshAccessToken(): Promise<void> {
    if (!this.client || !this.config) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized');
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
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized');
    }
    const config = this.config;
    const client = this.client;
    try {
      const currentRefreshToken = config.getRefreshTokenText();
      hilog.debug(DOMAIN, TAG, 'refreshAccessToken: current refreshToken length=%{public}d, expiresAt=%{public}s',
        currentRefreshToken.length, config.expiresAt?.toString());

      const token = await client.refreshToken(currentRefreshToken);
      config.setAccessToken(token.accessToken);
      // 华为刷新接口响应不返回新的 refresh_token，保留原有的避免被空值覆盖
      if (token.refreshToken && token.refreshToken.length > 0) {
        config.setRefreshToken(token.refreshToken);
      } else {
        token.refreshToken = currentRefreshToken;
      }
      // 刷新响应必含 expires_in，parseTokenResponse 已转为 expiresAt；若意外缺失则保留原值避免死循环
      if (token.expiresAt) {
        config.setExpiresAt(token.expiresAt);
      } else {
        token.expiresAt = config.expiresAt;
      }
      client.updateAccessToken(token.accessToken);

      // 发送令牌更新事件（token.refreshToken 与 expiresAt 已确保非空，避免持久化时覆盖原有值）
      await this.notifyTokenUpdated(token);

      hilog.info(DOMAIN, TAG, 'Access token refreshed successfully');
    } catch (error) {
      const errMsg = (error as Error).message || '';
      hilog.error(DOMAIN, TAG, 'Failed to refresh access token: %{public}s', errMsg);

      // 检测 refresh_token 失效（华为返回 400 + missing/invalid refresh_token 相关错误）
      // sub_error 12304=invalid client_secret, 20191=missing refresh_token, 12300=invalid grant
      const isRefreshTokenInvalid = errMsg.includes('400') &&
        (errMsg.includes('refresh_token') || errMsg.includes('invalid_grant') ||
          errMsg.includes('invalid client'));

      if (isRefreshTokenInvalid) {
        // refresh_token 已失效（超过180天或被撤销），清理持久化 token，提示重新登录
        hilog.error(DOMAIN, TAG, 'Refresh token invalid or expired, clearing stored token');
        try {
          await OAuth2TokenStorageService.getInstance().deleteToken({
            provider: OAuth2Provider.HUAWEI_DRIVE,
            encrypt: true
          });
        } catch (clearErr) {
          hilog.error(DOMAIN, TAG, 'Failed to clear expired token: %{public}s', (clearErr as Error).message);
        }
        // 令牌已失效（等效强制登出），同步清空路径→fileId 缓存（内存+磁盘）
        try {
          await HuaweiDriveStorage.clearPathCache();
        } catch (cacheErr) {
          hilog.warn(DOMAIN, TAG, 'Failed to clear path cache on auth expiry: %{public}s', (cacheErr as Error).message);
        }
        throw new StorageError(StorageErrorCodes.AUTH_EXPIRED,
          'Login expired, please re-authorize Huawei Drive');
      }

      throw new StorageError(StorageErrorCodes.CONNECT_ERROR, errMsg);
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
    // 确保磁盘持久化缓存已水合（单飞），冷启动首次解析即可命中
    await HuaweiDriveStorage.ensureHydrated();
    // 规范化路径：去掉开头的 '/'
    const normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    if (!normalizedPath) {
      return null;
    }

    // 1. 优先查路径→fileId 缓存，命中则直接 getInfo(fileId)
    const cachedFileId = HuaweiDriveStorage.pathIdCache.get(normalizedPath);
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
        HuaweiDriveStorage.pathIdCache.delete(normalizedPath);
        HuaweiDriveStorage.schedulePersist();
      }
    }

    // 2. 尝试将 path 当作 fileId 直接查询
    //（fileId 不含 '/'，含 '/' 的一定是路径，跳过探测避免必然失败的请求）
    if (!normalizedPath.includes('/')) {
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
      // 缓存本段路径→fileId（含中间目录与最终文件），后续同路径的 read/getInfo/exists 直接命中
      this.cachePathId(segments.slice(0, i + 1).join('/'), found.id);
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
   * 清空路径→fileId 缓存（内存 + 磁盘）
   * 退出登录 / refresh_token 失效强制登出时调用，避免残留上一个账号的映射数据
   */
  public static async clearPathCache(): Promise<void> {
    // 取消待写的防抖任务，避免清空后又被旧数据回写
    if (HuaweiDriveStorage.persistTimer >= 0) {
      clearTimeout(HuaweiDriveStorage.persistTimer);
      HuaweiDriveStorage.persistTimer = -1;
    }
    HuaweiDriveStorage.pathIdCache.clear();
    HuaweiDriveStorage.rootFolderId = '';
    HuaweiDriveStorage.cacheOwnerKey = '';
    HuaweiDriveStorage.hydratePromise = null;
    // 磁盘数据同步清除，标记已水合（无数据可加载），后续 init 账号比对会自行重置
    HuaweiDriveStorage.cacheHydrated = true;
    await HuaweiDrivePathCacheStore.clear();
    hilog.info(DOMAIN, TAG, 'Path id cache cleared (memory + disk)');
  }

  /**
   * 确保磁盘持久化缓存已水合到内存（单飞，整个进程只加载一次）
   * 在任何路径解析（findFileByPath/listDir）前调用，
   * 保证冷启动第一次解析即可命中持久化的 fileId，跳过逐级下钻
   */
  private static ensureHydrated(): Promise<void> {
    if (HuaweiDriveStorage.cacheHydrated) {
      return Promise.resolve();
    }
    if (HuaweiDriveStorage.hydratePromise) {
      return HuaweiDriveStorage.hydratePromise;
    }
    HuaweiDriveStorage.hydratePromise = HuaweiDriveStorage.doHydrate();
    return HuaweiDriveStorage.hydratePromise;
  }

  /**
   * 从磁盘加载缓存到静态成员
   * 仅在内存缓存为空且账号指纹匹配时水合；内存数据永远比磁盘新
   */
  private static async doHydrate(): Promise<void> {
    try {
      const ownerKey = HuaweiDriveStorage.cacheOwnerKey;
      // 无账号信息，或内存已有数据（如账号切换后已重新解析），跳过水合
      if (!ownerKey || HuaweiDriveStorage.pathIdCache.size > 0) {
        return;
      }
      const data = await HuaweiDrivePathCacheStore.load();
      if (!data) {
        return;
      }
      const currentHash = await HuaweiDrivePathCacheStore.ownerHash(ownerKey);
      if (data.owner !== currentHash) {
        hilog.info(DOMAIN, TAG, 'Persisted path cache owner mismatch, ignored');
        return;
      }
      for (const entry of data.entries) {
        if (HuaweiDriveStorage.pathIdCache.size >= PATH_ID_CACHE_LIMIT) {
          break;
        }
        HuaweiDriveStorage.pathIdCache.set(entry.p, entry.id);
      }
      if (!HuaweiDriveStorage.rootFolderId && data.rootId) {
        HuaweiDriveStorage.rootFolderId = data.rootId;
      }
      hilog.info(DOMAIN, TAG, 'Hydrated path cache from disk: %{public}d entries', data.entries.length);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Hydrate path cache failed: %{public}s', (error as Error).message);
    } finally {
      HuaweiDriveStorage.cacheHydrated = true;
      HuaweiDriveStorage.hydratePromise = null;
    }
  }

  /**
   * 防抖持久化：缓存变更点调用，500ms 内的多次变更合并为一次落盘
   * 避免浏览目录时（listDir 一次缓存 N 个子项）产生写放大
   */
  private static schedulePersist(): void {
    // 水合未完成前不落盘，避免用半空数据覆盖磁盘上的有效缓存
    if (!HuaweiDriveStorage.cacheHydrated) {
      return;
    }
    if (HuaweiDriveStorage.persistTimer >= 0) {
      return;
    }
    HuaweiDriveStorage.persistTimer = setTimeout(() => {
      HuaweiDriveStorage.persistTimer = -1;
      HuaweiDriveStorage.doPersist();
    }, PATH_CACHE_PERSIST_DELAY);
  }

  /**
   * 将静态缓存序列化落盘（fire-and-forget，失败仅告警）
   */
  private static doPersist(): void {
    const ownerKey = HuaweiDriveStorage.cacheOwnerKey;
    if (!ownerKey) {
      return;
    }
    const entries: HuaweiDrivePathCacheEntry[] = [];
    HuaweiDriveStorage.pathIdCache.forEach((fileId: string, path: string) => {
      entries.push({ p: path, id: fileId });
    });
    const data: HuaweiDrivePathCacheData = {
      owner: '',
      rootId: HuaweiDriveStorage.rootFolderId,
      entries: entries
    };
    HuaweiDrivePathCacheStore.ownerHash(ownerKey).then((hash: string) => {
      data.owner = hash;
      return HuaweiDrivePathCacheStore.save(data);
    }).catch((error: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'Persist path cache failed: %{public}s', error.message);
    });
  }

  /**
   * 解析根目录真实 fileId
   * 优先使用缓存（同一账号内根目录 id 不变）；未缓存时通过 list('root') 查找
   * parentFolder 为空的文件夹；找不到则通过 getInfo('root') 兜底，成功后写入缓存
   * @returns Promise<string> 根目录 id，失败返回空字符串
   */
  private async resolveRootFolderId(): Promise<string> {
    if (!this.client) {
      return '';
    }
    // 命中缓存直接返回，避免每次 findFileByPath 都 list('root')+getInfo('root')
    if (HuaweiDriveStorage.rootFolderId) {
      return HuaweiDriveStorage.rootFolderId;
    }
    const rootFiles = await this.listFilesInFolder('root');
    for (const file of rootFiles) {
      if (file.mimeType === HUAWEI_DRIVE_FOLDER_MIME_TYPE && file.parentFolder.length === 0) {
        HuaweiDriveStorage.rootFolderId = file.id;
        HuaweiDriveStorage.schedulePersist();
        return file.id;
      }
    }
    // 兜底：通过 getInfo('root') 获取真实 id
    const rootResp = await this.client.getInfo('root');
    if (rootResp.success && rootResp.body) {
      const rootJson = ByteUtils.bytesToString(rootResp.body);
      const rootData: Record<string, Object> = JSON.parse(rootJson);
      const rootId = this.client.parseFile(rootData).id;
      if (rootId) {
        HuaweiDriveStorage.rootFolderId = rootId;
        HuaweiDriveStorage.schedulePersist();
      }
      return rootId;
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
   * 流式分块下载到本地文件（S7：Range GET 循环 8MB 块直写盘，内存与文件大小解耦）
   */
  public async readToFile(path: string, destPath: string): Promise<FileInfo> {
    if (!this.client) {
      return Promise.reject(new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'Huawei Drive not initialized'));
    }
    if (this.config && this.config.isTokenExpired()) {
      await this.refreshAccessToken();
    }
    try {
      const file = await this.findFileByPath(path);
      if (!file) {
        return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, `File not found: ${path}`));
      }
      await this.client.downloadRangeToFile(file.id, destPath);
      return {
        name: file.fileName,
        size: file.size,
        modifiedTime: new Date(file.editedTime).getTime(),
        path: file.id,
        type: FileType.FILE,
        childrenCount: 0
      };
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive readToFile error: %{public}s', (error as Error).message);
      if (error instanceof StorageError) {
        return Promise.reject(error);
      }
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message));
    }
  }

  /**
   * 流式从本地文件上传（华为云盘断点续传为 S7 调研项，当前走默认整缓冲）
   */
  public async writeFromFile(path: string, srcPath: string, option?: WriteOption): Promise<FileInfo> {
    return FileTransfer.writeFromFileDefault(this, path, srcPath, option);
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
      if (error instanceof StorageError) {
        return Promise.reject(error);
      }
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

    // CP-UP：整缓冲上传超过 http 栈上限必然失败，提前拒绝并给出明确原因
    if (data.byteLength > HTTP_UPLOAD_MAX_BYTES) {
      throw new StorageError(StorageErrorCodes.UPLOAD_TOO_LARGE, `${data.byteLength} bytes`);
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
      if (error instanceof StorageError) {
        return Promise.reject(error);
      }
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
        if (error instanceof StorageError) {
          return Promise.reject(error);
        }
        return Promise.reject(new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message));
      }
    }

    try {
      const file = await this.findFileByPath(path);
      return file !== null;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive exists error: %{public}s', (error as Error).message);
      // 保留原始 StorageError（如 AUTH_EXPIRED），避免丢失错误码导致上层误判为文件不存在
      if (error instanceof StorageError) {
        return Promise.reject(error);
      }
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
      if (error instanceof StorageError) {
        return Promise.reject(error);
      }
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

    // 确保磁盘持久化缓存已水合（单飞），冷启动首次解析即可命中
    await HuaweiDriveStorage.ensureHydrated();

    // 将路径解析为文件夹 fileId
    // 根目录直接用 'root'；非根目录先查缓存，缓存未命中则通过 findFileByPath 解析
    let folderId: string;
    if (!path || path === '/') {
      folderId = 'root';
    } else {
      const cachedId = HuaweiDriveStorage.pathIdCache.get(path.startsWith('/') ? path.substring(1) : path);
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
      if (error instanceof StorageError) {
        return Promise.reject(error);
      }
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
      // 删除成功后同步移除路径→fileId 缓存，避免后续 exists/getInfo 命中已删除的 fileId
      const normalizedPath = path.startsWith('/') ? path.substring(1) : path;
      HuaweiDriveStorage.pathIdCache.delete(normalizedPath);
      HuaweiDriveStorage.schedulePersist();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Huawei Drive delete error: %{public}s', (error as Error).message);
      if (error instanceof StorageError) {
        return Promise.reject(error);
      }
      return Promise.reject(new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, (error as Error).message));
    }
  }

  /**
   * 缓存路径→fileId 映射，超过上限时清空最早的一半，避免无限增长
   * @param path 文件路径
   * @param fileId 华为云盘文件ID
   */
  private cachePathId(path: string, fileId: string): void {
    // 统一去掉开头的 '/'，保证写入与查询的 key 一致（findFileByPath 用 normalizedPath 查询）
    const key = path.startsWith('/') ? path.substring(1) : path;
    if (!key) {
      return;
    }
    if (HuaweiDriveStorage.pathIdCache.size >= PATH_ID_CACHE_LIMIT) {
      // 简单淘汰：清空缓存重建（Map 保持插入顺序，这里不做精细 LRU）
      HuaweiDriveStorage.pathIdCache.clear();
    }
    HuaweiDriveStorage.pathIdCache.set(key, fileId);
    // 防抖落盘（水合完成前内部会跳过）
    HuaweiDriveStorage.schedulePersist();
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
    // 不清空静态 pathIdCache/rootFolderId：它们按账号指纹（cacheOwnerKey）管理，
    // 且 fileId 失效时 findFileByPath 步骤1 会自动降级重新解析
  }
}
