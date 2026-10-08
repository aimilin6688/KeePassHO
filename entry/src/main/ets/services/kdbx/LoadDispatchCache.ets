/**
 * 加载调度尺寸缓存（进程内存）
 *
 * 缓存"文件路径 → 压缩后 KDBX 大小"，供分级加载调度（小库主线程直开 / 大库 Worker）
 * 零网络解析尺寸。写入点：预加载探测（RecentFilesService.probeFileInfo）、
 * Worker 预热回传、加载成功 SuccessMessage.fileSize 回填。
 * 仅缓存 size > 0 的有效值；不做失效时间戳（大小变化渐进，过期误判由加载守卫兜底）。
 */
export class LoadDispatchCache {
  private static cache: Map<string, number> = new Map<string, number>();

  /**
   * 写入尺寸（size ≤ 0 视为未知，忽略）
   */
  public static put(filePath: string, size: number): void {
    if (size > 0) {
      LoadDispatchCache.cache.set(filePath, size);
    }
  }

  /**
   * 读取尺寸；未命中返回 undefined（调用方按"未知"处理）
   */
  public static get(filePath: string): number | undefined {
    return LoadDispatchCache.cache.get(filePath);
  }

  /**
   * 清空缓存（锁定 / 切换数据库时调用）
   */
  public static clear(): void {
    LoadDispatchCache.cache.clear();
  }
}
