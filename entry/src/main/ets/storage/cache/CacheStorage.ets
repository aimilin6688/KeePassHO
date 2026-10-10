import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BaseFileStorage, FileInfo, FileType, IFileStorage, StorageConfig, TransferProgressCallback, WriteOption } from '../index';
import { CacheConstants } from './CacheConstants';
import { CacheMeta, CacheMetaService } from './CacheMetaService';
import { FileTransfer } from '../FileTransfer';
import { ResourceManager } from '../../common/utils';
import { KdbxError } from 'kdbxweb';
import { ErrorCodes } from '../../services/error/KeepassHoError';

const DOMAIN = 0x0000;
const TAG = 'CacheStorage';

/**
 * 缓存存储装饰器
 * 为远程存储添加本地缓存功能
 */
export class CacheStorage extends BaseFileStorage {
  private readonly decoratedStorage: IFileStorage;

  constructor(decoratedStorage: IFileStorage) {
    super();
    this.decoratedStorage = decoratedStorage;
  }

  /**
   * 获取页面配置
   * @returns PageConfig 页面配置
   */
  public getPageConfig() {
    return this.decoratedStorage.getPageConfig();
  }

  /**
   * 版本快速路径能力协商（透传底层实现，缓存装饰不改变语义）
   */
  public supportsVersionFastPath(): boolean {
    return this.decoratedStorage.supportsVersionFastPath?.() === true;
  }

  /**
   * 初始化
   * @param config 存储配置
   */
  public init(config: StorageConfig): void {
    this.decoratedStorage.init(config);
  }

  /**
   * 读取文件内容
   * 优先从远端加载，完成后异步保存到本地缓存
   * @param path 文件路径
   * @returns 文件内容
   * @throws 如果读取失败则抛出异常
   */
  public async read(path: string): Promise<ArrayBuffer> {
    // 如果禁用本地缓存
    if(!CacheConstants.isEnableLocalCache()){
      return this.decoratedStorage.read(path);
    }

    const cachePath: string = CacheConstants.getCacheFilePath(path);
    const onlyUseCache: boolean = CacheConstants.getOnlyCache();
    const forceRefresh: boolean = CacheConstants.getForceRefresh();

    // 如果强制刷新，清除强制刷新标志
    if (forceRefresh) {
      CacheConstants.clearForceRefresh();
    }

    // 仅使用本地缓存模式
    if (onlyUseCache && !forceRefresh) {
      hilog.debug(DOMAIN, TAG, 'Read from cache only: %{public}s', cachePath);
      return await this.readFromCache(cachePath);
    }

    // 正常模式：优先从远端加载
    hilog.debug(DOMAIN, TAG, 'Read from remote: %{public}s', path);
    const content: ArrayBuffer = await this.decoratedStorage.read(path);

    // 异步保存到本地缓存（不阻塞主流程）
    this.writeToCacheAsync(cachePath, content);
    return content;
  }

  /**
   * 写入文件内容
   * 优先写入本地缓存，完成后异步推送到远端
   * @param path 文件路径
   * @param content 文件内容
   * @param option 写入选项，透传给底层远端存储（条件写入）
   * @throws 如果写入失败则抛出异常
   */
  public async write(path: string, content: ArrayBuffer, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<void> {
    // 如果禁用本地缓存
    if(!CacheConstants.isEnableLocalCache()){
      return this.decoratedStorage.write(path, content, option, onProgress);
    }

    const cachePath: string = CacheConstants.getCacheFilePath(path);
    const onlyUseCache: boolean = CacheConstants.getOnlyCache();
    const forceRefresh: boolean = CacheConstants.getForceRefresh();

    // 如果强制刷新，清除强制刷新标志
    if (forceRefresh) {
      CacheConstants.clearForceRefresh();
    }

    // 仅使用本地缓存模式
    if (onlyUseCache && !forceRefresh) {
      hilog.debug(DOMAIN, TAG, 'Write to cache only: %{public}s', cachePath);
      throw new KdbxError(ErrorCodes.READ_ONLY, ResourceManager.getString($r('app.string.cache_read_only')));
    }

    // 正常模式：异步写入本地缓存（不阻塞），然后推送到远端
    this.writeToCacheAsync(cachePath, content);

    // 推送到远端（核心操作，必须成功；版本冲突错误原样上抛由编排层处理）
    await this.decoratedStorage.write(path, content, option, onProgress);
  }

  /**
   * 流式读取到本地文件（S3 保存链路冲突检测使用）
   * 仅缓存模式：从本地缓存复制到 destPath；正常/强制刷新：委托底层流式下载
   * @param path 远端路径
   * @param destPath 本地目标路径
   * @param onProgress 下载进度回调（可选），仅远端分支透传；本地缓存复制不回调
   */
  public async readToFile(path: string, destPath: string, onProgress?: TransferProgressCallback): Promise<FileInfo> {
    if (!CacheConstants.isEnableLocalCache()) {
      return this.decoratedStorage.readToFile(path, destPath, onProgress);
    }
    const cachePath: string = CacheConstants.getCacheFilePath(path);
    const onlyUseCache: boolean = CacheConstants.getOnlyCache();
    const forceRefresh: boolean = CacheConstants.getForceRefresh();
    if (forceRefresh) {
      CacheConstants.clearForceRefresh();
    }
    // 仅缓存模式：从本地缓存复制（离线可用）
    if (onlyUseCache && !forceRefresh) {
      try {
        await fs.copyFile(cachePath, destPath);
        return await this.getCacheInfo(cachePath, path);
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'readToFile from cache failed: %{public}s', error?.message);
        throw new Error(ResourceManager.getString($r('app.string.cache_file_not_found')));
      }
    }
    // 正常模式：委托底层流式下载到 destPath
    const info: FileInfo = await this.decoratedStorage.readToFile(path, destPath, onProgress);
    // 回填缓存 + 版本元数据（加载链路版本快速路径的事实来源）。
    // 必须 await：destPath 是调用方临时文件（T0），编排层 finally 会删除，异步拷贝会与删除竞态。
    // version 来源零成本——装饰层 readToFile 的返回 FileInfo 本就带 version，无新增请求。
    await this.refreshCache(path, destPath, info, 'readToFile');
    return info;
  }

  /**
   * 版本快速路径（加载链路）：本地缓存元数据与远端版本+尺寸一致时，把缓存内容复制到 destPath，
   * 让调用方跳过全量下载；任一条件不满足返回 false（miss），由调用方回落 readToFile。
   * 仅缓存装饰器实现，决策本身由编排层发起（避免装饰器内自做 getInfo 产生重复元数据请求）。
   * @param path 远端路径
   * @param destPath 本地目标路径
   * @param expectedVersion 远端当前版本（守卫 getInfo 取得的事实）
   * @param expectedSize 远端当前大小（版本之外的第二道防线）
   * @return 命中返回 true（destPath 已写入缓存内容），否则 false
   */
  public async readCacheToFile(path: string, destPath: string, expectedVersion: string,
    expectedSize: number): Promise<boolean> {
    if (!CacheConstants.isEnableLocalCache()) {
      return false; // 关闭本地缓存：装饰器透明，走远端
    }
    if (CacheConstants.getOnlyCache()) {
      return false; // 仅缓存模式：由 readToFile 的仅缓存分支负责
    }
    // 强制刷新（下拉刷新 / 冲突重载）不再直接放弃比对：远端版本+尺寸与缓存元数据一致时，
    // 本地副本即远端事实，用副本替代全量下载；不一致才回落 readToFile 走网络。
    // 一次性标志只在命中时就地消费（快速路径跳过了 readToFile，不清会泄漏给下一次操作）；
    // miss 时保留该标志，交给 readToFile 用于突破仅缓存模式
    const meta: CacheMeta | null = CacheMetaService.readMeta(path);
    if (meta === null || meta.version === null
      || meta.version !== expectedVersion || meta.size !== expectedSize) {
      return false;
    }
    CacheConstants.clearForceRefresh();
    const cachePath: string = CacheConstants.getCacheFilePath(path);
    try {
      await fs.copyFile(cachePath, destPath); // 缓存被删/损坏 → 抛错 → miss → 走下载
      hilog.info(DOMAIN, TAG, 'readCacheToFile hit: %{public}s', path);
      return true;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'readCacheToFile copy failed (miss): %{public}s', error?.message);
      return false;
    }
  }

  /**
   * 保存链路（整缓冲路径）后的缓存刷新：复制成品内容到本地缓存并回写版本元数据。
   * write() 写入时新版本未知，仅异步复制内容不更新元数据；保存成功后由编排层
   * 携带写入后的远端事实（version/size/modifiedTime）调用本方法，对齐流式
   * writeFromFile 的 refreshCache 语义，使"保存后立刻重载"命中版本快速路径。
   * best-effort：失败仅记日志，主链路不受影响
   * @param path 远端路径
   * @param content 写入远端成功的成品内容
   * @param info 写入后的远端文件信息（version 元数据事实来源）
   */
  public async refreshCacheFromBuffer(path: string, content: ArrayBuffer, info: FileInfo): Promise<void> {
    if (!CacheConstants.isEnableLocalCache()) {
      return; // 关闭本地缓存：装饰器透明，无缓存可刷
    }
    try {
      this.ensureCacheDir(CacheConstants.getCacheDir());
      // 内容先于元数据就位（writeToCache 临时文件 + 原子重命名），
      // 元数据指向新版本时缓存文件必已是新内容，避免快速路径命中残缺副本
      await this.writeToCache(CacheConstants.getCacheFilePath(path), content);
      await CacheMetaService.writeMeta(path, {
        version: info.version ?? null,
        size: info.size,
        modifiedTime: info.modifiedTime,
        savedAt: Date.now()
      });
      hilog.info(DOMAIN, TAG, 'refreshCacheFromBuffer success: %{public}s, version=%{public}s',
        path, info.version ?? 'null');
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'refreshCacheFromBuffer failed (transparent): %{public}s', error?.message);
    }
  }

  /**
   * 流式从本地源文件写入远端
   * 仅缓存模式：只读拒绝；正常模式：委托底层 + 异步刷新本地缓存
   * @param path 远端路径
   * @param srcPath 本地源文件路径
   * @param option 写入选项
   * @param onProgress 上传进度回调（可选），透传给底层远端存储
   */
  public async writeFromFile(path: string, srcPath: string, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<FileInfo> {
    if (!CacheConstants.isEnableLocalCache()) {
      return this.decoratedStorage.writeFromFile(path, srcPath, option, onProgress);
    }
    const cachePath: string = CacheConstants.getCacheFilePath(path);
    const onlyUseCache: boolean = CacheConstants.getOnlyCache();
    const forceRefresh: boolean = CacheConstants.getForceRefresh();
    if (forceRefresh) {
      CacheConstants.clearForceRefresh();
    }
    if (onlyUseCache && !forceRefresh) {
      throw new KdbxError(ErrorCodes.READ_ONLY, ResourceManager.getString($r('app.string.cache_read_only')));
    }
    // 委托底层流式上传
    const info: FileInfo = await this.decoratedStorage.writeFromFile(path, srcPath, option, onProgress);
    // 刷新本地缓存 + 回写元数据（writtenInfo.version 即保存后远端事实，零额外请求）：
    // 保存后立刻再次解锁可直接命中加载快速路径
    await this.refreshCache(path, srcPath, info, 'writeFromFile');
    return info;
  }

  /**
   * 刷新缓存文件并回写版本元数据（best-effort：失败仅记日志，主链路不受影响）
   * @param path 远端路径
   * @param srcPath 本地最新内容文件路径
   * @param info 远端文件信息（version 事实来源）
   * @param scene 日志场景标识（下载回填 / 保存回写）
   */
  private async refreshCache(path: string, srcPath: string, info: FileInfo, scene: string): Promise<void> {
    try {
      const cacheDir: string = CacheConstants.getCacheDir();
      this.ensureCacheDir(cacheDir);
      await fs.copyFile(srcPath, CacheConstants.getCacheFilePath(path));
      await CacheMetaService.writeMeta(path, {
        version: info.version ?? null,
        size: info.size,
        modifiedTime: info.modifiedTime,
        savedAt: Date.now()
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, '%{public}s refresh cache failed (transparent): %{public}s', scene, error?.message);
    }
  }

  /**
   * 获取文件信息；确定不存在时返回 null，无法判定时抛异常
   * 策略与 exists 镜像：禁缓存透传远端；仅缓存/强制刷新按策略走缓存或远端；
   * 正常模式远端失败回退缓存副本（离线可用语义不变）
   * @param path 文件路径
   * @returns Promise<FileInfo | null> 文件信息，确定不存在时为 null
   */
  public async getInfoOrNull(path: string): Promise<FileInfo | null> {
    // 如果禁用本地缓存
    if (!CacheConstants.isEnableLocalCache()) {
      return await this.probeDecorated(path);
    }

    const cachePath: string = CacheConstants.getCacheFilePath(path);
    const onlyUseCache: boolean = CacheConstants.getOnlyCache();
    const forceRefresh: boolean = CacheConstants.getForceRefresh();

    // 如果强制刷新，清除强制刷新标志
    if (forceRefresh) {
      CacheConstants.clearForceRefresh();
    }

    // 仅使用本地缓存模式：缓存副本存在返回信息，miss 视为不存在（离线不可打开）
    if (onlyUseCache && !forceRefresh) {
      try {
        return await this.getCacheInfo(cachePath, path);
      } catch (error) {
        hilog.debug(DOMAIN, TAG, 'getInfoOrNull cache miss: %{public}s', cachePath);
        return null;
      }
    }

    // 正常模式：优先远端，失败回退缓存副本（与 exists 离线回退语义一致；
    // 无缓存副本时上抛原始错误，保留"无法判定"语义，由调用方决定保留记录）
    try {
      return await this.probeDecorated(path);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'getInfoOrNull remote failed, fallback to cache: %{public}s', error?.message);
      try {
        return await this.getCacheInfo(cachePath, path);
      } catch {
        throw error as Error;
      }
    } 
  }

  /**
   * 探测被装饰存储（getInfoOrNull 为接口契约成员，直接透传）
   */
  private async probeDecorated(path: string): Promise<FileInfo | null> {
    return await this.decoratedStorage.getInfoOrNull(path);
  }

  /**
   * 检查文件是否存在
   * 优先检查本地缓存
   * @param path 文件路径
   * @returns 文件是否存在
   */
  public async exists(path: string): Promise<boolean> {
    // 如果禁用本地缓存
    if(!CacheConstants.isEnableLocalCache()){
      return this.decoratedStorage.exists(path);
    }

    const onlyUseCache: boolean = CacheConstants.getOnlyCache();
    const forceRefresh: boolean = CacheConstants.getForceRefresh();

    // 如果强制刷新，直接检查远端
    if (forceRefresh) {
      CacheConstants.clearForceRefresh();
      return await this.decoratedStorage.exists(path);
    }

    // 仅使用本地缓存模式：只检查本地缓存
    if (onlyUseCache) {
      return await CacheConstants.cacheExists(path);
    }

    // 正常走远端
    try {
      return await this.decoratedStorage.exists(path);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Check remote exists failed: %{public}s, fallback to cache', error?.message);
      const cached = await CacheConstants.cacheExists(path);
      if (cached) {
        // 远端不可达但存在本地缓存副本：视为存在（支持离线打开）
        return true;
      }
      // 远端错误且无缓存副本：无法判定文件是否存在，上抛错误
      // 由调用方保留最近文件记录（避免网络抖动导致记录被误删）
      throw error as Error;
    }
  }

  /**
   * 获取文件信息
   * 优先从本地缓存获取
   * @param path 文件路径
   * @returns 文件信息
   * @throws 如果获取失败则抛出异常
   */
  public async getInfo(path: string): Promise<FileInfo> {
    // 如果禁用本地缓存
    if(!CacheConstants.isEnableLocalCache()){
      return this.decoratedStorage.getInfo(path);
    }

    const cachePath: string = CacheConstants.getCacheFilePath(path);
    const onlyUseCache: boolean = CacheConstants.getOnlyCache();
    const forceRefresh: boolean = CacheConstants.getForceRefresh();

    // 如果强制刷新，清除强制刷新标志并从远端获取
    if (forceRefresh) {
      CacheConstants.clearForceRefresh();
      return await this.decoratedStorage.getInfo(path);
    }

    // 仅使用本地缓存模式：只从本地缓存获取
    if (onlyUseCache) {
      return await this.getCacheInfo(cachePath, path);
    }

    try {
      // 正常走远端
      return await this.decoratedStorage.getInfo(path);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Get remote info failed: %{public}s, fallback to cache', error?.message);
      return await this.getCacheInfo(cachePath, path);
    }
  }

  /**
   * 获取目录内容
   * @param path 路径
   * @returns 文件信息列表
   * @throws 如果获取失败则抛出异常
   */
  public listDir(path: string): Promise<FileInfo[]> {
    return this.decoratedStorage.listDir(path);
  }

  /**
   * 安全关闭文件
   * @param file 文件对象，可为 null
   */
  private async closeFileSafely(file: fs.File | null): Promise<void> {
    if (file) {
      try {
        await fs.close(file.fd);
      } catch {
        // ignore
      }
    }
  }

  /**
   * 从本地缓存读取文件
   * @param cachePath 缓存文件路径
   * @returns 文件内容
   */
  private async readFromCache(cachePath: string): Promise<ArrayBuffer> {
    let file: fs.File | null = null;
    try {
      file = await fs.open(cachePath, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer);
      hilog.debug(DOMAIN, TAG, 'Read from cache success: %{public}s', cachePath);
      return buffer;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Read from cache failed: %{public}s, error: %{public}s', cachePath, error?.message);
      throw new Error(ResourceManager.getString($r('app.string.cache_file_not_found')));
    } finally {
      await this.closeFileSafely(file);
    }
  }

  /**
   * 写入文件到本地缓存（安全写入）
   * 使用临时文件 + 原子重命名，确保写入失败不破坏原有缓存
   * 包含重试机制，处理目录可能被系统清理的情况
   * @param cachePath 缓存文件路径
   * @param content 文件内容
   */
  private async writeToCache(cachePath: string, content: ArrayBuffer): Promise<void> {
    const tempPath = cachePath + '.tmp';
    let file: fs.File | null = null;
    let retries = 2;

    while (retries > 0) {
      try {
        // 每次尝试前确保目录存在
        const cacheDir: string = CacheConstants.getCacheDir();
        this.ensureCacheDir(cacheDir);

        // 写入临时文件（使用 TRUNC 确保清空旧内容）
        file = await fs.open(tempPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        await fs.write(file.fd, content);

        // 强制落盘，确保数据持久化
        await fs.fsync(file.fd);

        // 关闭文件
        await this.closeFileSafely(file);
        file = null;

        // 原子重命名替换旧文件
        await fs.rename(tempPath, cachePath);

        hilog.debug(DOMAIN, TAG, 'Write to cache success: %{public}s', cachePath);
        return;
      } catch (error) {
        retries--;
        await this.closeFileSafely(file);
        file = null;
        // 清理临时文件
        try {
          await fs.unlink(tempPath);
        } catch {
          // ignore
        }

        if (retries === 0) {
          hilog.error(DOMAIN, TAG, 'Write to cache failed: %{public}s, error: %{public}s', cachePath, error?.stack);
          throw new Error('Write to cache failed: ' + error?.message);
        }
        hilog.warn(DOMAIN, TAG, 'Write to cache retry, previous error: %{public}s', error?.message);
      }
    }
  }

  /**
   * 异步写入到本地缓存（不阻塞主流程）
   * 在正常模式下，缓存失败只记录日志，不向用户显示错误，保持透明性
   * @param cachePath 缓存文件路径
   * @param content 文件内容
   */
  private async writeToCacheAsync(cachePath: string, content: ArrayBuffer): Promise<void> {
    try {
      await this.writeToCache(cachePath, content);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Write to cache async failed (transparent mode): %{public}s, error: %{public}s', cachePath, error?.stack);
    }
  }

  /**
   * 获取缓存文件信息
   * @param cachePath 缓存文件路径
   * @param originalPath 原始文件路径（用于返回给调用方，保持透明性）
   * @returns 文件信息
   */
  private async getCacheInfo(cachePath: string, originalPath?: string): Promise<FileInfo> {
    let file: fs.File | null = null;
    try {
      file = await fs.open(cachePath, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      // 优先使用原始路径提取文件名，确保返回给调用方的是原始路径和文件名
      const fileName: string = originalPath ? originalPath.split('/').pop() ?? '' : cachePath.split('/').pop() ?? '';
      const fileInfo: FileInfo = {
        name: fileName,
        path: originalPath ?? cachePath,  // 返回原始路径而非缓存路径，保持透明性
        size: stat.size,
        modifiedTime: stat.mtime,
        type: FileType.FILE,
        childrenCount: 0
      } as FileInfo;
      return fileInfo;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Get cache info failed: %{public}s, error: %{public}s', cachePath, error?.stack);
      throw new Error('Get cache info failed: ' + error?.message);
    } finally {
      await this.closeFileSafely(file);
    }
  }

  /**
   * 确保缓存目录存在
   * @param cacheDir 缓存目录路径
   * @throws 如果目录创建失败则抛出异常
   */
  private ensureCacheDir(cacheDir: string): void {
    try {
      // 先检查目录是否存在
      if (!fs.accessSync(cacheDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(cacheDir, true);
        hilog.debug(DOMAIN, TAG, 'Cache dir created: %{public}s', cacheDir);
      }
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'Failed to ensure cache dir: %{public}s, error: %{public}s', cacheDir, err.message);
      throw new Error('Failed to ensure cache dir: ' + err.message);
    }
  }
}
