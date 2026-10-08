import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageConfig, StorageType } from '../../storage';
import { Constants } from '../../common/constants/Constants';
import { LoadDispatchCache } from './LoadDispatchCache';
import KdbxLoadService from './KdbxLoadService';

const DOMAIN = 0x0000;
const TAG = 'LoadDispatchService';

/**
 * 加载调度服务（分级加载设计 §4/§5）
 *
 * 页面展示期后台准备：已知大小超过主线程阈值时预热常驻加载 Worker
 * （isolate 模块图 + 存储连接 + 大小探测），小库完全不建 Worker（零 isolate 开销）。
 * 全部 best-effort：任何失败仅记日志，不影响后续正常加载。
 */
export class LoadDispatchService {
  /**
   * 页面展示期准备（后台异步，不阻塞 UI）：
   * 尺寸来自加载调度缓存（预加载 probeFileInfo / 上次预热 / 上次加载回填），
   * size > SYNC_LOAD_MAX_BYTES 才预热；LOCAL 存储跳过（stat 即得大小，无需预热）
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
}
