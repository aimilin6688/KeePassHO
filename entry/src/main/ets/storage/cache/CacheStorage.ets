import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileInfo, FileType, IFileStorage, StorageConfig } from '../index';
import { CacheConstants } from './CacheConstants';
import { ResourceManager } from '../../common/utils';
import { KdbxError } from 'kdbxweb';
import { ErrorCodes } from '../../services/error/KeepassHoError';

const DOMAIN = 0x0000;
const TAG = 'CacheStorage';

/**
 * 缓存存储装饰器
 * 为远程存储添加本地缓存功能
 */
export class CacheStorage implements IFileStorage {
  private readonly decoratedStorage: IFileStorage;

  constructor(decoratedStorage: IFileStorage) {
    this.decoratedStorage = decoratedStorage;
  }

  /**
   * 获取页面配置
   * @returns 页面配置
   */
  public getPageConfig() {
    return this.decoratedStorage.getPageConfig();
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
   * @throws 如果写入失败则抛出异常
   */
  public async write(path: string, content: ArrayBuffer): Promise<void> {
    // 如果禁用本地缓存
    if(!CacheConstants.isEnableLocalCache()){
      return this.decoratedStorage.write(path, content);
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

    // 推送到远端（核心操作，必须成功）
    await this.decoratedStorage.write(path, content);
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
      return await CacheConstants.cacheExists(path);
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
      hilog.debug(DOMAIN, TAG, 'Write to cache async success: %{public}s', cachePath);
    } catch (error) {
      // 缓存失败只记录日志，不向用户显示错误，保持缓存层透明性
      hilog.error(DOMAIN, TAG, 'Write to cache async failed (transparent mode): %{public}s, error: %{public}s', cachePath, error?.stack);
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
