import { BaseFileStorage, FileInfo, FileType, PageConfig, StorageConfig, TransferProgressCallback, WriteOption } from '../index';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BaiduNetdiskClient, BaiduUploadIdExpiredError } from './BaiduNetdiskClient';
import { HTTP_UPLOAD_MAX_BYTES, StorageError, StorageErrorCodes } from '../StorageError';
import { BaiduNetdiskPageConfig, BaiduNetdiskStorageConfig } from './BaiduNetdiskConfig';
import { OAuth2Error, OAuth2Provider, OAuth2RefreshRequest, OAuth2Token, OAuth2TokenStorageService } from '../../common/oauth2';
import { BaiduNetdiskOAuth2Provider, createBaiduNetdiskOAuth2Config } from './BaiduNetdiskOAuth2Provider';
import { BaiduFileMeta, BaiduNetdiskConstants, BaiduNetdiskParser, isBaiduNotFoundError } from './BaiduNetdiskTypes';
import { HashUtils } from '../../common/utils/HashUtils';
import BuildProfile from 'BuildProfile';

const DOMAIN = 0x0000;
const TAG = 'BaiduNetdiskStorage';

/**
 * precreate return_type：2 = 秒传成功（precreate 已完成文件创建）
 */
const RAPID_UPLOAD_RETURN_TYPE: number = 2;

class BaiduUploadInfoCache {
  path: string;
  info: FileInfo;

  constructor(path: string, info: FileInfo) {
    this.path = path;
    this.info = info;
  }
}

/**
 * 百度网盘存储实现类（设计文档 D1-D11）
 * 上传链路：precreate（md5 三元组秒传检测）→ superfile2 分片上传 → create；
 * 下载链路：list 父目录解析 fs_id → filemetas 取 dlink → 固定 UA 下载；
 * 版本标识：decryptBaiduMd5 还原的内容 md5（无法解出时 null，内容哈希兜底）
 */
export class BaiduNetdiskStorage extends BaseFileStorage {
  /**
   * 存储配置
   */
  private config: BaiduNetdiskStorageConfig | undefined;
  /**
   * 百度网盘客户端
   */
  private client: BaiduNetdiskClient | undefined;
  /**
   * OAuth2 提供者（token 端点 GET 风格，刷新不经过 client，无递归）
   */
  private oauth2Provider: BaiduNetdiskOAuth2Provider | undefined;

  /**
   * 进行中的刷新 Promise（并发去重，避免多个操作同时刷新）
   * 刷新完成（成功或失败）后置空
   */
  private refreshingPromise: Promise<void> | null = null;

  /**
   * 上传结果缓存条目：write() 完成后以本地已知事实（version=contentMd5）缓存 FileInfo，
   * 后续 getInfoOrNull 命中时免网络请求，消除 postSuccess 额外解析延迟
   * 一次消费：getInfoOrNull 取出后清空
   */
  private cachedUploadInfo: BaiduUploadInfoCache | null = null;

  /**
   * 构造函数
   * @param config 百度网盘存储配置
   */
  constructor(config?: BaiduNetdiskStorageConfig) {
    super();
    if (config) {
      this.init(config);
    }
  }

  /**
   * 获取页面配置
   * @returns PageConfig 页面配置
   */
  public getPageConfig(): PageConfig {
    return BaiduNetdiskPageConfig;
  }

  /**
   * 初始化存储配置
   * @param config 百度网盘存储配置
   */
  public init(config: StorageConfig): void {
    this.config = this.parseConfig(config);
    this.oauth2Provider = new BaiduNetdiskOAuth2Provider(createBaiduNetdiskOAuth2Config(
      BuildProfile.BAIDU_NETDISK_CLIENT_ID,
      BuildProfile.BAIDU_NETDISK_CLIENT_SECRET,
      BuildProfile.BAIDU_NETDISK_REDIRECT_URI
    ));
    this.client = new BaiduNetdiskClient(this.config.getAccessTokenText(),
      (): Promise<string> => this.refreshTokenForClient());
    hilog.debug(DOMAIN, TAG, `BaiduNetdiskStorage init: accessToken length=${this.config.getAccessTokenText().length}`);
  }

  /**
   * 解析配置
   * @param config 配置对象
   * @returns BaiduNetdiskStorageConfig 百度网盘存储配置
   */
  private parseConfig(config: StorageConfig): BaiduNetdiskStorageConfig {
    if (config instanceof BaiduNetdiskStorageConfig) {
      return config;
    }
    const baiduConfig = config as BaiduNetdiskStorageConfig;
    return new BaiduNetdiskStorageConfig(
      baiduConfig.accessToken,
      baiduConfig.refreshToken,
      baiduConfig.expiresAt,
      {
        timeout: baiduConfig.timeout,
        tokenType: baiduConfig.tokenType,
        scope: baiduConfig.scope
      }
    );
  }

  /**
   * 获取客户端（未初始化抛出异常）
   */
  private requireClient(): BaiduNetdiskClient {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'BaiduNetdisk not initialized');
    }
    return this.client;
  }

  /**
   * 确保访问令牌有效（令牌生命周期归共享 token store 管理，不依赖单次操作的配置快照）
   * 1. 配置快照内 token 仍有效：直接返回（零开销）
   * 2. 快照已过期：先读共享 token store（文件后端，Worker 内同样可用，承载上次刷新落盘的新 token），
   *    账号一致（refreshToken 相同）且未过期 → 应用到当前实例，免刷新
   * 3. store 也无可用 token：真正刷新（单飞）→ 成功后经 notifyTokenUpdated 持久化回 store
   */
  private async ensureValidToken(): Promise<void> {
    const config = this.config;
    if (!config || !this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'BaiduNetdisk not initialized');
    }
    if (!config.isTokenExpired()) {
      return;
    }
    try {
      const stored: OAuth2Token | null = await OAuth2TokenStorageService.getInstance()
        .loadToken({ provider: OAuth2Provider.BAIDU_NETDISK, encrypt: true });
      if (stored && stored.accessToken && stored.expiresAt
        && stored.refreshToken === config.getRefreshTokenText()
        && stored.expiresAt > Date.now() + 5 * 60 * 1000) {
        config.setAccessToken(stored.accessToken);
        if (stored.refreshToken) {
          config.setRefreshToken(stored.refreshToken);
        }
        config.setExpiresAt(stored.expiresAt);
        this.client.updateAccessToken(stored.accessToken);
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
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'BaiduNetdisk not initialized');
    }
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
   * client 令牌刷新回调（client 检测到 token 失效 errno 时经此回调刷新并取回新 token）
   */
  private async refreshTokenForClient(): Promise<string> {
    await this.refreshAccessToken();
    const config = this.config;
    if (!config) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'BaiduNetdisk not initialized');
    }
    return config.getAccessTokenText();
  }

  /**
   * 实际执行刷新逻辑（经 OAuth2 提供者 GET token 端点，不经过 client，无递归）
   * 百度每次刷新返回新的 refresh_token，成功后一并落配置与 token store
   */
  private async doRefreshAccessToken(): Promise<void> {
    const config = this.config;
    const client = this.client;
    const provider = this.oauth2Provider;
    if (!config || !client || !provider) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'BaiduNetdisk not initialized');
    }
    try {
      const refreshRequest: OAuth2RefreshRequest = { refreshToken: config.getRefreshTokenText() };
      const token: OAuth2Token = await provider.refreshToken(refreshRequest);
      config.setAccessToken(token.accessToken);
      if (token.refreshToken) {
        config.setRefreshToken(token.refreshToken);
      }
      if (token.expiresAt) {
        config.setExpiresAt(token.expiresAt);
      }
      client.updateAccessToken(token.accessToken);
      await this.notifyTokenUpdated(token);
      hilog.info(DOMAIN, TAG, 'Access token refreshed successfully');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to refresh access token: %{public}s', (error as Error).message);
      // refresh_token 失效/被撤销：需重新登录授权
      if (error instanceof OAuth2Error) {
        throw new StorageError(StorageErrorCodes.AUTH_EXPIRED, (error as Error).message);
      }
      throw new StorageError(StorageErrorCodes.CONNECT_ERROR, (error as Error).message);
    }
  }

  /**
   * 通知令牌已更新（持久化到共享 token store）
   * @param token 更新后的令牌
   */
  private async notifyTokenUpdated(token: OAuth2Token): Promise<void> {
    try {
      const storageService = OAuth2TokenStorageService.getInstance();
      await storageService.updateToken(token, {
        provider: OAuth2Provider.BAIDU_NETDISK,
        encrypt: true
      });
      hilog.info(DOMAIN, TAG, 'Token updated in token store');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update token in token store: %{public}s', (error as Error).message);
    }
  }

  /**
   * 读取文件内容（整缓冲）
   * 链路：list 父目录解析 fs_id → filemetas 取 dlink → 固定 UA 下载
   * @param path 远端文件路径
   * @returns Promise<ArrayBuffer> 文件内容
   * @throws StorageError
   */
  public async read(path: string): Promise<ArrayBuffer> {
    const normalizedPath = BaiduNetdiskClient.normalizePath(path);
    await this.ensureValidToken();
    try {
      const client = this.requireClient();
      const meta: BaiduFileMeta = await this.resolveExistingFile(normalizedPath);
      const fullMeta: BaiduFileMeta = await client.getFileMetaWithDlink(meta.fsId);
      return await client.download(fullMeta.dlink);
    } catch (error) {
      if (error instanceof StorageError) {
        throw error;
      }
      hilog.error(DOMAIN, TAG, 'BaiduNetdisk read error: %{public}s', (error as Error).message);
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message);
    }
  }

  /**
   * 流式下载到本地文件（filemetas dlink + rcp.downloadToFile，响应体不驻留内存）
   * @param path 远端文件路径
   * @param destPath 本地目标文件路径
   * @param onProgress 下载进度回调（可选）：rcp onDownloadProgress 字节级透传
   * @return Promise<FileInfo> 远端文件信息（含 version）
   */
  public async readToFile(path: string, destPath: string,
    onProgress?: TransferProgressCallback): Promise<FileInfo> {
    const normalizedPath = BaiduNetdiskClient.normalizePath(path);
    await this.ensureValidToken();
    try {
      const client = this.requireClient();
      const meta: BaiduFileMeta = await this.resolveExistingFile(normalizedPath);
      const fullMeta: BaiduFileMeta = await client.getFileMetaWithDlink(meta.fsId);
      const progressAdapter: ((totalSize: number, transferredSize: number) => void) | undefined =
        onProgress ? (totalSize: number, transferredSize: number): void => {
          onProgress(transferredSize, totalSize);
        } : undefined;
      await client.downloadToFile(fullMeta.dlink, destPath, progressAdapter);
      return BaiduNetdiskStorage.toFileInfo(meta);
    } catch (error) {
      if (error instanceof StorageError) {
        throw error;
      }
      hilog.error(DOMAIN, TAG, 'BaiduNetdisk readToFile error: %{public}s', (error as Error).message);
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, (error as Error).message);
    }
  }

  /**
   * 写入文件内容（整缓冲，precreate → superfile2 分片 → create，D4/D5/D6）
   * 条件写入：传入 expectedVersion 时写前复核远端 md5 版本（fail-open，D8）
   * @param path 远端文件路径
   * @param data 文件内容（非空；百度不支持空文件）
   * @param option 写入选项
   * @param onProgress 上传进度回调（可选）：分片粒度上报
   * @returns Promise<void>
   * @throws StorageError(VERSION_CONFLICT / UPLOAD_TOO_LARGE / FILE_WRITE_ERROR / AUTH_EXPIRED)
   */
  public async write(path: string, data: ArrayBuffer, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<void> {
    if (data.byteLength === 0) {
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR,
        'Baidu Netdisk does not support uploading empty files');
    }
    if (data.byteLength > HTTP_UPLOAD_MAX_BYTES) {
      throw new StorageError(StorageErrorCodes.UPLOAD_TOO_LARGE, `${data.byteLength} bytes`);
    }
    const normalizedPath = BaiduNetdiskClient.normalizePath(path);
    await this.ensureValidToken();
    const expectedVersion: string | null = option?.expectedVersion ?? null;
    if (expectedVersion !== null) {
      await this.checkVersionUnchanged(normalizedPath, expectedVersion);
    }
    try {
      // md5 三元组（D5）：整文件 content-md5、前 256KB slice-md5、4MB 分片 block_list
      const contentMd5: string = HashUtils.md5Hex(data);
      const sliceMd5: string = HashUtils.md5Hex(data.slice(0, BaiduNetdiskConstants.RAPID_SLICE_MD5_SIZE));
      const blockList: Array<string> = this.buildBlockList(data);
      await this.uploadWithRetry(normalizedPath, data, contentMd5, sliceMd5, blockList, onProgress);
      // 上传结果以本地已知事实缓存（R6：不依赖 create 返回的服务器时间）
      const info: FileInfo = {
        name: BaiduNetdiskClient.lastSegment(normalizedPath),
        size: data.byteLength,
        modifiedTime: Date.now(),
        path: normalizedPath,
        type: FileType.FILE,
        childrenCount: 0,
        version: contentMd5
      };
      this.cachedUploadInfo = new BaiduUploadInfoCache(normalizedPath, info);
    } catch (error) {
      if (error instanceof StorageError) {
        throw error;
      }
      hilog.error(DOMAIN, TAG, 'BaiduNetdisk write error: %{public}s', (error as Error).message);
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, (error as Error).message);
    }
  }

  /**
   * 计算 4MB 分片 md5 列表（block_list，D6）
   */
  private buildBlockList(data: ArrayBuffer): Array<string> {
    const blockList: Array<string> = [];
    const total: number = data.byteLength;
    const sliceSize: number = BaiduNetdiskConstants.SLICE_SIZE;
    for (let offset = 0; offset < total; offset += sliceSize) {
      const end: number = Math.min(offset + sliceSize, total);
      blockList.push(HashUtils.md5Hex(data.slice(offset, end)));
    }
    return blockList;
  }

  /**
   * 上传主流程（含 uploadid 过期重试，≤2 轮 precreate）
   * 第 1 轮 precreate → returnType=2 秒传完成；=1 按 pre.blockList 序号上传分片 → create；
   * 分片环节 uploadid 过期（BaiduUploadIdExpiredError）→ 第 2 轮重新 precreate 全量重传
   */
  private async uploadWithRetry(remotePath: string, data: ArrayBuffer, contentMd5: string,
    sliceMd5: string, blockList: Array<string>, onProgress?: TransferProgressCallback): Promise<void> {
    const client = this.requireClient();
    const nowSec: number = Math.floor(Date.now() / 1000);
    const total: number = data.byteLength;
    const sliceSize: number = BaiduNetdiskConstants.SLICE_SIZE;
    let attempt = 0;
    while (true) {
      const pre = await client.precreate(remotePath, total, blockList, contentMd5, sliceMd5,
        nowSec, nowSec);
      try {
        if (pre.returnType === RAPID_UPLOAD_RETURN_TYPE) {
          // 秒传：precreate 已完成文件创建
          if (onProgress) {
            onProgress(total, total);
          }
          return;
        }
        for (let i = 0; i < pre.blockList.length; i++) {
          const partSeq: number = pre.blockList[i];
          const start: number = partSeq * sliceSize;
          const end: number = Math.min(start + sliceSize, total);
          await client.uploadSlice(remotePath, pre.uploadid, partSeq, data.slice(start, end));
          if (onProgress) {
            onProgress(end, total);
          }
        }
        await client.createFile(remotePath, total, pre.uploadid, blockList, nowSec, nowSec);
        return;
      } catch (error) {
        const err: Error = error as Error;
        if (err instanceof BaiduUploadIdExpiredError && attempt < 1) {
          attempt++;
          hilog.warn(DOMAIN, TAG, 'uploadid expired, re-precreate and re-upload: %{public}s', err.message);
          continue;
        }
        throw err;
      }
    }
  }

  /**
   * 按路径解析已存在文件的元信息（读取链路共用）
   * @throws StorageError(FILE_READ_ERROR) 文件不存在或为目录
   */
  private async resolveExistingFile(normalizedPath: string): Promise<BaiduFileMeta> {
    const client = this.requireClient();
    const meta: BaiduFileMeta | null = await client.resolveFileInfo(normalizedPath);
    if (meta === null) {
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, `File not found: ${normalizedPath}`);
    }
    if (meta.isdir === 1) {
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, `Not a file: ${normalizedPath}`);
    }
    return meta;
  }

  /**
   * 获取文件信息；文件确定不存在时返回 null，无法判定（网络错误、令牌失效等）时抛异常
   * @param path 文件路径
   * @returns Promise<FileInfo | null> 文件信息，确定不存在时为 null
   * @throws StorageError 如果检查失败则抛出异常
   */
  public async getInfoOrNull(path: string): Promise<FileInfo | null> {
    const normalizedPath = BaiduNetdiskClient.normalizePath(path);
    if (this.cachedUploadInfo !== null && this.cachedUploadInfo.path === normalizedPath) {
      const cached: BaiduUploadInfoCache = this.cachedUploadInfo;
      this.cachedUploadInfo = null;
      hilog.info(DOMAIN, TAG, 'getInfoOrNull: cache hit for path=%{public}s', normalizedPath);
      return cached.info;
    }
    await this.ensureValidToken();
    try {
      const client = this.requireClient();
      const meta: BaiduFileMeta | null = await client.resolveFileInfo(normalizedPath);
      return meta === null ? null : BaiduNetdiskStorage.toFileInfo(meta);
    } catch (error) {
      if (error instanceof StorageError) {
        throw error;
      }
      hilog.error(DOMAIN, TAG, 'BaiduNetdisk getInfoOrNull error: %{public}s', (error as Error).message);
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, (error as Error).message);
    }
  }

  /**
   * 获取目录内容（list 分页循环直至单页不足 LIST_PAGE_SIZE）
   * @param path 目录路径
   * @returns Promise<Array<FileInfo>> 目录内容
   * @throws StorageError 如果获取失败则抛出异常
   */
  public async listDir(path: string): Promise<Array<FileInfo>> {
    const normalizedPath = BaiduNetdiskClient.normalizePath(path);
    await this.ensureValidToken();
    try {
      const client = this.requireClient();
      const result: Array<FileInfo> = [];
      let start = 0;
      while (true) {
        const metas: Array<BaiduFileMeta> = await client.listDir(normalizedPath, start,
          BaiduNetdiskConstants.LIST_PAGE_SIZE);
        for (let i = 0; i < metas.length; i++) {
          result.push(BaiduNetdiskStorage.toFileInfo(metas[i]));
        }
        if (metas.length < BaiduNetdiskConstants.LIST_PAGE_SIZE) {
          break;
        }
        start += metas.length;
      }
      return result;
    } catch (error) {
      if (error instanceof StorageError) {
        throw error;
      }
      if (isBaiduNotFoundError(error)) {
        throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, `Directory not found: ${normalizedPath}`);
      }
      hilog.error(DOMAIN, TAG, 'BaiduNetdisk listDir error: %{public}s', (error as Error).message);
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, (error as Error).message);
    }
  }

  /**
   * 条件写入：写前复核远端 md5 版本，不一致抛出版本冲突
   * 远端不存在（新库首存）、为目录、md5 无法解出或探测失败时放行（fail-open，D8），
   * 由后续上传环节自行报错
   * @param normalizedPath 远端文件路径（已规范化）
   * @param expectedVersion 期望的远端版本（decryptBaiduMd5 还原的内容 md5）
   * @throws StorageError(VERSION_CONFLICT) 版本不一致时抛出
   */
  private async checkVersionUnchanged(normalizedPath: string, expectedVersion: string): Promise<void> {
    const client = this.requireClient();
    try {
      const meta: BaiduFileMeta | null = await client.resolveFileInfo(normalizedPath);
      if (meta === null || meta.isdir === 1) {
        return;
      }
      const currentVersion: string | null = BaiduNetdiskStorage.extractVersion(meta);
      if (currentVersion !== null && currentVersion !== expectedVersion) {
        hilog.warn(DOMAIN, TAG, 'BaiduNetdisk version conflict, path: %{public}s, expected: %{public}s, current: %{public}s',
          normalizedPath, expectedVersion, currentVersion);
        throw new StorageError(StorageErrorCodes.VERSION_CONFLICT, 'BaiduNetdisk file version changed');
      }
      // currentVersion === null：远端 md5 无法解出，无法校验，放行（fail-open）
    } catch (error) {
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      // 远端不存在或探测失败：放行（fail-open），由上传环节自行报错
    }
  }

  /**
   * 百度文件元信息 → FileInfo
   * version：仅文件类型且 decryptBaiduMd5 还原结果为 32 位 hex 时采用（目录/无法解出为 null）
   * modifiedTime：server_mtime（秒）转毫秒，缺省回落 server_ctime
   */
  private static toFileInfo(meta: BaiduFileMeta): FileInfo {
    const name: string = meta.serverFilename.length > 0
      ? meta.serverFilename
      : BaiduNetdiskClient.lastSegment(meta.path);
    const mtimeSec: number = meta.serverMtime > 0 ? meta.serverMtime : meta.serverCtime;
    const info: FileInfo = {
      name: name,
      size: meta.size,
      modifiedTime: mtimeSec * 1000,
      path: meta.path,
      type: meta.isdir === 1 ? FileType.DIR : FileType.FILE,
      childrenCount: 0,
      version: BaiduNetdiskStorage.extractVersion(meta)
    };
    return info;
  }

  /**
   * 提取可信版本标识（decryptBaiduMd5 还原的内容 md5）
   * 目录、无 md5 或还原结果非 32 位 hex 时返回 null（上层内容哈希兜底）
   */
  private static extractVersion(meta: BaiduFileMeta): string | null {
    if (meta.isdir === 1 || meta.md5.length !== 32) {
      return null;
    }
    const decrypted: string = BaiduNetdiskParser.decryptBaiduMd5(meta.md5);
    return /^[0-9a-f]{32}$/.test(decrypted) ? decrypted : null;
  }

  /**
   * 更新存储配置
   * @param config 百度网盘存储配置
   */
  public updateConfig(config: BaiduNetdiskStorageConfig): void {
    this.config = config;
    this.init(config);
  }

  /**
   * 获取当前配置
   * @returns BaiduNetdiskStorageConfig 存储配置
   */
  public getConfig(): BaiduNetdiskStorageConfig | undefined {
    return this.config;
  }
}
