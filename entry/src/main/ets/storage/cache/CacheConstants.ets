import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from '../../common/utils/CommonUtils';
import { SettingsService } from '../../services/SettingsService';

const DOMAIN = 0x0000;
const TAG = 'CacheConstants';

/**
 * 缓存常量类
 * 用于管理数据库本地缓存相关的常量和状态
 */
export class CacheConstants {
  /**
   * 缓存目录名称
   */
  static readonly CACHE_DIR_NAME: string = 'cache';
  /**
   * 缓存文件后缀
   */
  static readonly CACHE_FILE_SUFFIX: string = '.cache';
  /**
   * 是否仅使用本地缓存的AppStorage键
   */
  static readonly ONLY_CACHE_KEY: string = 'only_use_cache';
  /**
   * 强制刷新标志的AppStorage键
   */
  static readonly FORCE_REFRESH_KEY: string = 'force_refresh';

  // Worker 线程的缓存策略快照（Worker 内无 AppStorage/preferences，
  // 由主线程在创建 Worker 时注入；undefined 表示主线程环境，走真实数据源）
  private static workerEnableLocalCache: boolean | undefined = undefined;
  private static workerOnlyUseCache: boolean | undefined = undefined;
  private static workerForceRefresh: boolean | undefined = undefined;

  /**
   * 注入 Worker 线程的缓存策略快照（仅 Worker 的 INIT 消息处理调用；
   * 主线程不调用，避免快照遮蔽主线程的实时设置）
   */
  static setWorkerCachePolicy(enableLocalCache: boolean, onlyUseCache: boolean,
    forceRefresh: boolean): void {
    CacheConstants.workerEnableLocalCache = enableLocalCache;
    CacheConstants.workerOnlyUseCache = onlyUseCache;
    CacheConstants.workerForceRefresh = forceRefresh;
  }

  /**
   * 获取应用缓存目录
   * @returns 缓存目录路径
   */
  static getCacheDir(): string {
    // 应用级 files 目录：主线程取自 Context，Worker 线程取注入路径（见 CommonUtils.setWorkerPaths）
    return CommonUtils.getAppFilesDir() + '/' + CacheConstants.CACHE_DIR_NAME;
  }

  /**
   * 根据原始文件路径生成缓存文件路径
   * @param originalPath 原始文件路径
   * @returns 缓存文件路径
   */
  static getCacheFilePath(originalPath: string): string {
    const fileName: string = CacheConstants.getCacheFileName(originalPath);
    return CacheConstants.getCacheDir() + '/' + fileName;
  }

  /**
   * 根据原始文件路径生成缓存文件名
   * @param originalPath 原始文件路径
   * @returns 缓存文件名
   */
  private static getCacheFileName(originalPath: string): string {
    // 使用原始路径的哈希值作为缓存文件名，避免文件名过长或包含非法字符
    const hash: number = CacheConstants.hashString(originalPath);
    return hash.toString(16) + CacheConstants.CACHE_FILE_SUFFIX;
  }

  /**
   * 计算字符串的哈希值
   * @param str 字符串
   * @returns 哈希值
   */
  private static hashString(str: string): number {
    let hash: number = 0;
    const length: number = str.length;
    for (let i = 0; i < length; i++) {
      const char: number = str.charCodeAt(i);
      hash = (hash << 5) - hash + char;
      hash = hash & hash; // 转换为32位整数
    }
    return Math.abs(hash);
  }

  /**
   * 检查缓存文件是否存在
   * @param cachePath 缓存文件路径
   * @returns 是否存在
   */
  static async cacheExists(originalPath: string): Promise<boolean> {
    const cachePath: string = CacheConstants.getCacheFilePath(originalPath);
    try {
      const result: boolean = fs.accessSync(cachePath, fs.AccessModeType.EXIST);
      hilog.info(DOMAIN, TAG, `Cache exists: ${result}, path: ${cachePath}`);
      return result;
    } catch (error) {
      hilog.info(DOMAIN, TAG, `Cache not exist: ${cachePath}`);
      return false;
    }
  }

  /**
   * 删除缓存文件
   * @param originalPath 原始文件路径
   */
  static async deleteCache(originalPath: string): Promise<void> {
    const cachePath: string = CacheConstants.getCacheFilePath(originalPath);
    try {
      await fs.unlink(cachePath);
      hilog.info(DOMAIN, TAG, `Cache deleted: ${cachePath}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to delete cache: ${cachePath}, error: ${(error as Error).message}`);
    }
  }

  /**
   * 删除所有缓存文件
   */
  static async deleteAllCache(): Promise<void> {
    try {
      const cacheDir: string = CacheConstants.getCacheDir();
      // 先删除目录中的所有文件
      const files = CacheConstants.listCacheFiles(cacheDir);
      for (const file of files) {
        try {
          await fs.unlink(file);
        } catch {
          // ignore individual file deletion errors
        }
      }
      // 再删除目录
      await fs.rmdir(cacheDir);
      hilog.info(DOMAIN, TAG, `All cache deleted: ${cacheDir}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to delete all cache, error: ${(error as Error).message}`);
    }
  }

  /**
   * 列出缓存目录中的所有文件
   * @param cacheDir 缓存目录路径
   * @returns 文件路径列表
   */
  private static listCacheFiles(cacheDir: string): string[] {
    const files: string[] = [];
    try {
      const entries = fs.listFileSync(cacheDir);
      for (const entry of entries) {
        files.push(cacheDir + '/' + entry);
      }
    } catch {
      // 目录不存在或无法读取
    }
    return files;
  }

  /**
   * 设置是否仅使用本地缓存
   * @param onlyCache 是否仅使用缓存
   */
  static setOnlyCache(onlyCache: boolean): void {
    try {
      AppStorage.setOrCreate(CacheConstants.ONLY_CACHE_KEY, onlyCache);
      hilog.debug(DOMAIN, TAG, `Set only cache: ${onlyCache}`);
    } catch {
      // Worker 线程无 AppStorage：策略由主线程在创建 Worker 时以快照注入
    }
  }

  /**
   * 获取是否仅使用本地缓存
   * @returns 是否仅使用缓存
   */
  static getOnlyCache(): boolean {
    if (CacheConstants.workerOnlyUseCache !== undefined) {
      return CacheConstants.workerOnlyUseCache;
    }
    try {
      return AppStorage.get<boolean>(CacheConstants.ONLY_CACHE_KEY) ?? false;
    } catch {
      // Worker 线程无 AppStorage：默认非仅缓存模式（正常读远端）
      return false;
    }
  }

  /**
   * 设置强制刷新标志
   * @param forceRefresh 是否强制刷新
   */
  static setForceRefresh(forceRefresh: boolean): void {
    try {
      AppStorage.setOrCreate(CacheConstants.FORCE_REFRESH_KEY, forceRefresh);
      hilog.debug(DOMAIN, TAG, `Set force refresh: ${forceRefresh}`);
    } catch {
      // Worker 线程无 AppStorage：标志由主线程在创建 Worker 时一次性消费并随快照注入
    }
  }

  /**
   * 获取强制刷新标志
   * @returns 是否强制刷新
   */
  static getForceRefresh(): boolean {
    if (CacheConstants.workerForceRefresh !== undefined) {
      return CacheConstants.workerForceRefresh;
    }
    try {
      return AppStorage.get<boolean>(CacheConstants.FORCE_REFRESH_KEY) ?? false;
    } catch {
      // Worker 线程无 AppStorage：默认不强制刷新
      return false;
    }
  }

  /**
   * 清除强制刷新标志
   */
  static clearForceRefresh(): void {
    try {
      AppStorage.setOrCreate(CacheConstants.FORCE_REFRESH_KEY, false);
      hilog.debug(DOMAIN, TAG, 'Clear force refresh');
    } catch {
      // Worker 线程无 AppStorage：快照标志随 Worker 生命周期结束自动失效
    }
  }

  /**
   * 是否开启本地缓存
   * @returns
   */
  static isEnableLocalCache(): boolean {
    if (CacheConstants.workerEnableLocalCache !== undefined) {
      return CacheConstants.workerEnableLocalCache;
    }
    return SettingsService.getSync(SettingsService.KEY_APP_ENABLE_LOCAL_CACHE, SettingsService.KEY_APP_ENABLE_LOCAL_CACHE_DEFAULT);
  }
}
