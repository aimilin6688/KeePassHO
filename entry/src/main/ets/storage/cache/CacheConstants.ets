import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { CommonUtils } from '../../common/utils/CommonUtils';

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
   * 缓存路径的AppStorage键
   */
  static readonly CACHE_PATH_KEY: string = 'cache_path';

  /**
   * 强制刷新标志的AppStorage键
   */
  static readonly FORCE_REFRESH_KEY: string = 'force_refresh';

  /**
   * 本地编辑状态的AppStorage键前缀
   */
  static readonly LOCAL_EDIT_STATE_PREFIX: string = 'local_edit_state_';

  /**
   * 获取应用缓存目录
   * @returns 缓存目录路径
   */
  static getCacheDir(): string {
    const context = CommonUtils.getContext();
    return context.filesDir + '/' + CacheConstants.CACHE_DIR_NAME;
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
  static async cacheExists(cachePath: string): Promise<boolean> {
    try {
      const result: number = fs.accessSync(cachePath, fs.AccessModeType.EXIST);
      hilog.info(DOMAIN, TAG, `Cache exists: ${result}, path: ${cachePath}`);
      return true;
    } catch (error) {
      hilog.info(DOMAIN, TAG, `Cache not exist: ${cachePath}`);
      return false;
    }
  }

  /**
   * 删除缓存文件
   * @param cachePath 缓存文件路径
   */
  static async deleteCache(cachePath: string): Promise<void> {
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
      await fs.rmdir(cacheDir);
      hilog.info(DOMAIN, TAG, `All cache deleted: ${cacheDir}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to delete all cache, error: ${(error as Error).message}`);
    }
  }

  /**
   * 设置是否仅使用本地缓存
   * @param onlyCache 是否仅使用缓存
   */
  static setOnlyCache(onlyCache: boolean): void {
    AppStorage.setOrCreate(CacheConstants.ONLY_CACHE_KEY, onlyCache);
    hilog.debug(DOMAIN, TAG, `Set only cache: ${onlyCache}`);
  }

  /**
   * 获取是否仅使用本地缓存
   * @returns 是否仅使用缓存
   */
  static getOnlyCache(): boolean {
    return AppStorage.get<boolean>(CacheConstants.ONLY_CACHE_KEY) ?? false;
  }

  /**
   * 设置缓存路径
   * @param cachePath 缓存路径
   */
  static setCachePath(cachePath: string): void {
    AppStorage.setOrCreate(CacheConstants.CACHE_PATH_KEY, cachePath);
    hilog.debug(DOMAIN, TAG, `Set cache path: ${cachePath}`);
  }

  /**
   * 获取缓存路径
   * @returns 缓存路径
   */
  static getCachePath(): string {
    return AppStorage.get<string>(CacheConstants.CACHE_PATH_KEY) ?? '';
  }

  /**
   * 设置强制刷新标志
   * @param forceRefresh 是否强制刷新
   */
  static setForceRefresh(forceRefresh: boolean): void {
    AppStorage.setOrCreate(CacheConstants.FORCE_REFRESH_KEY, forceRefresh);
    hilog.debug(DOMAIN, TAG, `Set force refresh: ${forceRefresh}`);
  }

  /**
   * 获取强制刷新标志
   * @returns 是否强制刷新
   */
  static getForceRefresh(): boolean {
    return AppStorage.get<boolean>(CacheConstants.FORCE_REFRESH_KEY) ?? false;
  }

  /**
   * 清除强制刷新标志
   */
  static clearForceRefresh(): void {
    AppStorage.setOrCreate(CacheConstants.FORCE_REFRESH_KEY, false);
    hilog.debug(DOMAIN, TAG, 'Clear force refresh');
  }

  /**
   * 设置本地编辑状态
   * @param path 文件路径
   * @param hasEdit 是否有本地编辑
   */
  static setLocalEditState(path: string, hasEdit: boolean): void {
    const key: string = CacheConstants.LOCAL_EDIT_STATE_PREFIX + CacheConstants.hashString(path).toString(16);
    AppStorage.setOrCreate(key, hasEdit);
    hilog.debug(DOMAIN, TAG, `Set local edit state: ${path}, ${hasEdit}`);
  }

  /**
   * 获取本地编辑状态
   * @param path 文件路径
   * @returns 是否有本地编辑
   */
  static getLocalEditState(path: string): boolean {
    const key: string = CacheConstants.LOCAL_EDIT_STATE_PREFIX + CacheConstants.hashString(path).toString(16);
    return AppStorage.get<boolean>(key) ?? false;
  }

  /**
   * 移除本地编辑状态
   * @param path 文件路径
   */
  static removeLocalEditState(path: string): void {
    const key: string = CacheConstants.LOCAL_EDIT_STATE_PREFIX + CacheConstants.hashString(path).toString(16);
    AppStorage.setOrCreate(key, false);
    hilog.debug(DOMAIN, TAG, `Remove local edit state: ${path}`);
  }
}
