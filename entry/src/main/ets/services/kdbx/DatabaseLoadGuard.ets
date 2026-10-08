import { statfs } from '@kit.CoreFileKit';
import { appManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileInfo } from '../../storage';
import { KdbxFileManager } from './KdbxFileManager';
import { SettingsService } from '../SettingsService';
import { CommonUtils } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'DatabaseLoadGuard';

/**
 * 读前守卫结果
 */
export class GuardCheckResult {
  /** 拒绝原因的资源名（由消费方按名本地化），null 表示放行 */
  rejectReason: string | null = null;
  /** 预检顺带获取的远端文件信息；探测失败或大小无效时为 null（供调用方复用，避免重复 getInfo） */
  fileInfo: FileInfo | null = null;
}

/**
 * 数据库加载守卫（设计文档 CP1 / CP-DISK / CP2'）
 * 全部 fail-open：任何探测失败都放行加载，由后续真实加载流程给出错误
 */
export class DatabaseLoadGuard {
  /** CP-DISK：本地可用磁盘需 ≥ 文件大小的倍数（解压 + 保存 + 导出余量） */
  private static readonly DISK_FREE_FACTOR: number = 4;
  /** CP2'：应用可用内存中允许用于模型的比例 */
  private static readonly MEM_ALLOW_RATIO: number = 0.55;
  /** CP2'：KDBX 载荷解压放大系数（XML 解压后约为压缩前的 1.3 倍以上，取保守值） */
  private static readonly DECOMPRESS_AMPLIFICATION: number = 1.3;
  /** appManager 探测失败时的兜底应用内存（MB） */
  private static readonly FALLBACK_APP_MEMORY_MB: number = 512;
  /** CP2' 结果缓存（进程内不变，避免每次加载重复探测） */
  private static cachedMaxDecompressedBytes: number | undefined = undefined;

  /**
   * CP1 + CP-DISK：读取前检查文件大小与本地磁盘余量
   * 接收调用方已创建的 KdbxFileManager（单 manager 贯穿一次操作，避免每阶段重复 init 存储、重复刷新令牌）；
   * 预检的 getInfo 结果随 GuardCheckResult 返回，调用方可复用（版本预检 / 下载基线），不产生额外请求
   * @param fileManager 已完成 init 的文件管理器
   * @param filePath 文件路径
   * @returns GuardCheckResult（rejectReason 为 null 表示放行）
   */
  public static async checkBeforeRead(fileManager: KdbxFileManager, filePath: string): Promise<GuardCheckResult> {
    const result: GuardCheckResult = new GuardCheckResult();
    let fileSize: number = -1;
    try {
      const fileInfo = await fileManager.getInfo(filePath);
      result.fileInfo = fileInfo;
      fileSize = fileInfo.size;
    } catch (error) {
      // 取不到文件信息（远端不支持 / 网络失败）：放行，由真实读取流程报错
      hilog.warn(DOMAIN, TAG, 'checkBeforeRead get file info failed: %{public}s', error.message);
      return result;
    }
    if (fileSize <= 0) {
      return result;
    }
    // CP1：文件大小上限
    const maxFileSizeMb: number = SettingsService.getSync<number>(SettingsService.KEY_DATABASE_MAX_SIZE,
      SettingsService.KEY_DATABASE_MAX_SIZE_DEFAULT);
    if (fileSize > maxFileSizeMb * 1024 * 1024) {
      hilog.warn(DOMAIN, TAG, 'CP1 reject: file %{public}d bytes > limit %{public}d MB', fileSize, maxFileSizeMb);
      result.rejectReason = 'database_too_large';
      return result;
    }
    // CP-DISK：本地磁盘余量检查（含本地文件，保存前解压/导出都需要本地空间）
    try {
      const freeBytes: number = await statfs.getFreeSize(CommonUtils.getAppFilesDir());
      if (freeBytes < fileSize * DatabaseLoadGuard.DISK_FREE_FACTOR) {
        hilog.warn(DOMAIN, TAG, 'CP-DISK reject: free %{public}d < %{public}d x file %{public}d',
          freeBytes, DatabaseLoadGuard.DISK_FREE_FACTOR, fileSize);
        result.rejectReason = 'database_not_enough_disk';
        return result;
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'checkBeforeRead statfs failed (fail-open): %{public}s', error.message);
    }
    return result;
  }

  /**
   * CP2'：计算解压后模型大小上限（字节），进程内缓存
   * 上限 = 应用可用内存 × MEM_ALLOW_RATIO ÷ DECOMPRESS_AMPLIFICATION
   */
  public static async getMaxDecompressedBytes(): Promise<number> {
    if (DatabaseLoadGuard.cachedMaxDecompressedBytes !== undefined) {
      return DatabaseLoadGuard.cachedMaxDecompressedBytes;
    }
    let appMemoryMb: number = DatabaseLoadGuard.FALLBACK_APP_MEMORY_MB;
    try {
      appMemoryMb = await appManager.getAppMemorySize();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'getAppMemorySize failed, fallback %{public}d MB: %{public}s',
        DatabaseLoadGuard.FALLBACK_APP_MEMORY_MB, error.message);
    }
    const maxBytes: number = Math.floor(
      appMemoryMb * 1024 * 1024 * DatabaseLoadGuard.MEM_ALLOW_RATIO / DatabaseLoadGuard.DECOMPRESS_AMPLIFICATION);
    DatabaseLoadGuard.cachedMaxDecompressedBytes = maxBytes;
    hilog.info(DOMAIN, TAG, 'CP2 limit: appMem %{public}d MB -> maxDecompressedBytes %{public}d',
      appMemoryMb, maxBytes);
    return maxBytes;
  }
}
