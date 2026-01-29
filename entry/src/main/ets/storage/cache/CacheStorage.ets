import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { IFileStorage, FileInfo, StorageType, FileType } from '../index';
import { CacheConstants } from './CacheConstants';
import { DialogHelper } from '@pura/harmony-dialog';
import { ResourceManager } from '../../common/utils/ResourceManager';

const DOMAIN = 0x0000;
const TAG = 'CacheStorage';

/**
 * 缓存存储装饰器
 * 为远程存储添加本地缓存功能
 */
export class CacheStorage implements IFileStorage {
  private readonly decoratedStorage: IFileStorage;
  private readonly storageType: StorageType;

  constructor(decoratedStorage: IFileStorage, storageType: StorageType) {
    this.decoratedStorage = decoratedStorage;
    this.storageType = storageType;
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
  public init(config): void {
    this.decoratedStorage.init(config);
  }

  /**
   * 读取文件内容
   * 优先从远端加载，完成后异步保存到本地缓存
   * @param path 文件路径
   * @returns 文件内容
   */
  public async read(path: string): Promise<ArrayBuffer> {
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
    
    // 异步保存到本地缓存
    this.saveToCacheAsync(cachePath, content);
    
    // 设置缓存路径
    CacheConstants.setCachePath(cachePath);
    
    return content;
  }

  /**
   * 写入文件内容
   * 优先写入本地缓存，完成后异步推送到远端
   * @param path 文件路径
   * @param content 文件内容
   */
  public async write(path: string, content: ArrayBuffer): Promise<void> {
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
      await this.writeToCache(cachePath, content);
      CacheConstants.setLocalEditState(path, true);
      return;
    }

    // 正常模式：优先写入本地缓存，然后异步推送到远端
    hilog.debug(DOMAIN, TAG, 'Write to cache first: %{public}s', cachePath);
    await this.writeToCache(cachePath, content);
    
    // 异步推送到远端
    this.pushToRemoteAsync(path, content);
    
    // 清除本地编辑状态
    CacheConstants.removeLocalEditState(path);
  }

  /**
   * 检查文件是否存在
   * 优先检查本地缓存
   * @param path 文件路径
   * @returns 文件是否存在
   */
  public async exists(path: string): Promise<boolean> {
    const cachePath: string = CacheConstants.getCacheFilePath(path);
    const onlyUseCache: boolean = CacheConstants.getOnlyCache();
    const forceRefresh: boolean = CacheConstants.getForceRefresh();

    // 如果强制刷新，直接检查远端
    if (forceRefresh) {
      CacheConstants.clearForceRefresh();
      return await this.decoratedStorage.exists(path);
    }

    // 仅使用本地缓存模式：只检查本地缓存
    if (onlyUseCache) {
      return await CacheConstants.cacheExists(cachePath);
    }

    // 正常模式：优先检查本地缓存
    const cacheExists: boolean = await CacheConstants.cacheExists(cachePath);
    if (cacheExists) {
      return true;
    }

    // 本地缓存不存在，检查远端
    return await this.decoratedStorage.exists(path);
  }

  /**
   * 获取文件信息
   * 优先从本地缓存获取
   * @param path 文件路径
   * @returns 文件信息
   */
  public async getInfo(path: string): Promise<FileInfo> {
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
      return await this.getCacheInfo(cachePath);
    }

    // 正常模式：优先从本地缓存获取
    try {
      return await this.getCacheInfo(cachePath);
    } catch (error) {
      // 本地缓存不存在，从远端获取
      return await this.decoratedStorage.getInfo(path);
    }
  }

  /**
   * 获取目录内容
   * @param path 路径
   * @returns 文件信息列表
   */
  public listDir(path: string): Promise<FileInfo[]> {
    return this.decoratedStorage.listDir(path);
  }

  /**
   * 从本地缓存读取文件
   * @param cachePath 缓存文件路径
   * @returns 文件内容
   */
  private async readFromCache(cachePath: string): Promise<ArrayBuffer> {
    try {
      const file = await fs.open(cachePath, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer);
      await fs.close(file.fd);
      hilog.debug(DOMAIN, TAG, 'Read from cache success: %{public}s', cachePath);
      return buffer;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Read from cache failed: %{public}s, error: %{public}s', 
        cachePath, (error as Error).message);
      throw new Error(ResourceManager.getString($r('app.string.cache_file_not_found')));
    }
  }

  /**
   * 写入文件到本地缓存
   * @param cachePath 缓存文件路径
   * @param content 文件内容
   */
  private async writeToCache(cachePath: string, content: ArrayBuffer): Promise<void> {
    try {
      const cacheDir: string = CacheConstants.getCacheDir();
      await this.ensureCacheDir(cacheDir);
      
      const file = await fs.open(cachePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      await fs.write(file.fd, content);
      await fs.close(file.fd);
      hilog.debug(DOMAIN, TAG, 'Write to cache success: %{public}s', cachePath);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Write to cache failed: %{public}s, error: %{public}s', 
        cachePath, (error as Error).message);
      const errorMsg: string = 'Write to cache failed: ' + (error as Error).message;
      throw new Error(errorMsg);
    }
  }

  /**
   * 异步保存到本地缓存
   * @param cachePath 缓存文件路径
   * @param content 文件内容
   */
  private async saveToCacheAsync(cachePath: string, content: ArrayBuffer): Promise<void> {
    try {
      await this.writeToCache(cachePath, content);
      hilog.debug(DOMAIN, TAG, 'Save to cache async success: %{public}s', cachePath);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Save to cache async failed: %{public}s, error: %{public}s', 
        cachePath, (error as Error).message);
      // 忽略缓存写入错误，不影响主流程
    }
  }

  /**
   * 异步推送到远端
   * @param path 原始文件路径
   * @param content 文件内容
   */
  private async pushToRemoteAsync(path: string, content: ArrayBuffer): Promise<void> {
    try {
      hilog.debug(DOMAIN, TAG, 'Push to remote async: %{public}s', path);
      await this.decoratedStorage.write(path, content);
      hilog.debug(DOMAIN, TAG, 'Push to remote async success: %{public}s', path);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Push to remote async failed: %{public}s, error: %{public}s', 
        path, (error as Error).message);
      // 显示错误提示
      this.showErrorDialog((error as Error).message);
    }
  }

  /**
   * 显示错误提示对话框
   * @param errorMessage 错误信息
   */
  private showErrorDialog(errorMessage: string): void {
    try {
      const errorTitle: string = ResourceManager.getString($r('app.string.dialog_error_title'));
      const errorMsg: string = ResourceManager.getString($r('app.string.push_to_remote_failed'));
      const message: string = errorMsg.replace('%s', errorMessage);
      
      DialogHelper.showTipsDialog({
        imageRes: $r('app.media.ic_error'),
        imageSize: { width: 48, height: 48 },
        title: $r('app.string.dialog_error_title'),
        primaryButton: {
          value: $r('app.string.confirm'),
          action: () => {
            // 用户点击确认
          }
        },
        content: message
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Show error dialog failed: %{public}s', (error as Error).message);
    }
  }

  /**
   * 获取缓存文件信息
   * @param cachePath 缓存文件路径
   * @returns 文件信息
   */
  private async getCacheInfo(cachePath: string): Promise<FileInfo> {
    try {
      const file = await fs.open(cachePath, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      await fs.close(file.fd);
      const fileName: string = cachePath.split('/').pop() ?? '';
      const fileInfo: FileInfo = {
        name: fileName,
        path: cachePath,
        size: stat.size,
        modifiedTime: stat.mtime,
        type: FileType.FILE,
        childrenCount: 0
      } as FileInfo;
      return fileInfo;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Get cache info failed: %{public}s, error: %{public}s', 
        cachePath, (error as Error).message);
      const errorMsg: string = 'Get cache info failed: ' + (error as Error).message;
      throw new Error(errorMsg);
    }
  }

  /**
   * 确保缓存目录存在
   * @param cacheDir 缓存目录路径
   */
  private async ensureCacheDir(cacheDir: string): Promise<void> {
    try {
      const result: number = fs.accessSync(cacheDir, fs.AccessModeType.EXIST);
      hilog.debug(DOMAIN, TAG, 'Cache dir exists: %{public}s', cacheDir);
    } catch (error) {
      // 目录不存在，创建目录
      hilog.debug(DOMAIN, TAG, 'Create cache dir: %{public}s', cacheDir);
      // 注意：这里简化处理，实际可能需要递归创建父目录
      try {
        const file = await fs.open(cacheDir, fs.OpenMode.CREATE | fs.OpenMode.READ_ONLY);
        await fs.close(file.fd);
      } catch (createError) {
        hilog.error(DOMAIN, TAG, 'Create cache dir failed: %{public}s, error: %{public}s', 
          cacheDir, (createError as Error).message);
      }
    }
  }
}
