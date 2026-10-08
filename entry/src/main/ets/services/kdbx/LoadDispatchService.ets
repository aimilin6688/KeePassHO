import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageConfig, StorageType } from '../../storage';
import { Constants } from '../../common/constants/Constants';
import { LoadDispatchCache } from './LoadDispatchCache';
import KdbxLoadService from './KdbxLoadService';
import { RecentFilesService } from '../RecentFilesService';
import { KdbxFileManager } from './KdbxFileManager';

const DOMAIN = 0x0000;
const TAG = 'LoadDispatchService';

/**
 * 加载调度服务（分级加载设计 §3/§4）
 *
 * 小库（≤ SYNC_LOAD_MAX_BYTES）主线程直开：零协议税、零 isolate 开销、复用预加载暖连接；
 * 大库（> 阈值）或大小未知走 Worker（保守默认，UI 保护更强）。
 * 尺寸解析链：调度缓存 → 最近文件持久化快照 → 主线程兜底探测（getInfoOrNull，warm）→ 未知。
 * 全部 best-effort：解析失败按"未知"处理，不阻断加载。
 */
export class LoadDispatchService {
  /**
   * 页面展示期准备（后台异步，不阻塞 UI）：
   * 已知大小超过主线程阈值时预热常驻加载 Worker
   * （isolate 模块图 + 存储连接 + 大小探测），小库完全不建 Worker（零 isolate 开销）；
   * LOCAL 存储跳过（stat 即得大小，无需预热）
   */
  public static prepare(storageType: StorageType, storageConfig: StorageConfig, filePath: string): void {
    if (storageType === StorageType.LOCAL) {
      return;
    }
    const size: number | undefined = LoadDispatchCache.get(filePath);
    if (size !== undefined && size > Constants.SYNC_LOAD_MAX_BYTES) {
      hilog.info(DOMAIN, TAG, 'prepare: prewarm big file %{public}d bytes: %{public}s', size, filePath);
      KdbxLoadService.prewarm(filePath, storageType, storageConfig);
      return;
    }
    hilog.debug(DOMAIN, TAG, 'prepare: size=%{public}d (cached), skip prewarm: %{public}s',
      size ?? -1, filePath);
  }

  /**
   * 解析文件大小（优先级从高到低，命中即返回；全部 miss 返回 undefined 表示未知）：
   * ① 调度缓存（预加载探测 / Worker 预热 / 上次加载回填）
   * ② 最近文件持久化快照 RecentFile.fileSize（跨进程重启兜底）
   * ③ 主线程兜底探测（getInfoOrNull；LOCAL 即 stat，远端 warm 连接一次元数据请求）
   * 探测异常（网络失败等）按未知处理，由真实加载流程给出错误
   */
  public static async resolveSize(filePath: string, storageType: StorageType,
    storageConfig: StorageConfig): Promise<number | undefined> {
    // ① 调度缓存
    const cached: number | undefined = LoadDispatchCache.get(filePath);
    if (cached !== undefined && cached > 0) {
      return cached;
    }

    // ② 最近文件持久化快照（大小有效则顺手回填缓存）
    try {
      const recentFile = await RecentFilesService.getRecentFile(filePath);
      if (recentFile !== null && recentFile.fileSize !== undefined && recentFile.fileSize > 0) {
        LoadDispatchCache.put(filePath, recentFile.fileSize);
        return recentFile.fileSize;
      }
    } catch (error) {
      hilog.debug(DOMAIN, TAG, 'resolveSize recent file snapshot miss: %{public}s', (error as Error).message);
    }

    // ③ 主线程兜底探测
    try {
      const info = await new KdbxFileManager(storageType, storageConfig).getInfoOrNull(filePath);
      if (info !== null && info.size > 0) {
        LoadDispatchCache.put(filePath, info.size);
        return info.size;
      }
    } catch (error) {
      hilog.debug(DOMAIN, TAG, 'resolveSize probe failed (unknown): %{public}s', (error as Error).message);
    }
    return undefined;
  }
}
