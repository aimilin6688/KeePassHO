import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CacheConstants } from './CacheConstants';

const DOMAIN = 0x0000;
const TAG = 'CacheMetaService';

/**
 * 本地缓存元数据：记录"缓存内容对应远端哪个版本"这一事实
 * （加载链路版本快速路径的判据来源；缓存文件本身是无版本的裸文件）
 */
export interface CacheMeta {
  /**
   * 远端版本标识（FileInfo.version），null 表示无版本事实（快速路径永不命中）
   */
  version: string | null;
  /**
   * 远端文件大小（字节），版本之外的第二道防线（弱 ETag / 秒级 mtime 误判）
   */
  size: number;
  /**
   * 远端最后修改时间（毫秒），仅供观测与排查
   */
  modifiedTime: number;
  /**
   * 元数据落盘时间（毫秒时间戳）
   */
  savedAt: number;
}

/**
 * 缓存元数据服务（sidecar 文件：<cachePath>.meta）
 *
 * 仅依赖 CoreFileKit 与 CommonUtils.getAppFilesDir（Worker 路径已由 setWorkerPaths 注入），
 * 无 AppStorage / preferences 依赖，主线程与 Worker 线程行为完全一致。
 * 全部 fail-safe：读失败视为无元数据（退化为全量下载），写/删失败仅记日志（缓存始终 best-effort）。
 */
export class CacheMetaService {
  /** 元数据文件后缀（与缓存文件同目录同名加后缀，生命周期天然绑定） */
  private static readonly META_SUFFIX: string = '.meta';

  /**
   * 计算元数据文件路径
   * @param originalPath 远端原始路径
   * @returns 元数据文件路径
   */
  public static getMetaPath(originalPath: string): string {
    return CacheConstants.getCacheFilePath(originalPath) + CacheMetaService.META_SUFFIX;
  }

  /**
   * 读取缓存元数据（同步，<200B 小文件）
   * 文件不存在 / JSON 解析失败 / 结构异常 → null（调用方退化为全量下载）
   * @param originalPath 远端原始路径
   * @returns 元数据，不可用时为 null
   */
  public static readMeta(originalPath: string): CacheMeta | null {
    const metaPath: string = CacheMetaService.getMetaPath(originalPath);
    try {
      if (!fs.accessSync(metaPath, fs.AccessModeType.EXIST)) {
        return null;
      }
      const text: string = fs.readTextSync(metaPath);
      if (!text) {
        return null;
      }
      const parsed: CacheMeta = JSON.parse(text) as CacheMeta;
      if (parsed === null || typeof parsed !== 'object') {
        return null;
      }
      return parsed;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'read meta failed (treat as none): %{public}s', (error as Error).message);
      return null;
    }
  }

  /**
   * 写入缓存元数据（临时文件 + fsync + rename 原子落盘，写中断不破坏旧元数据）
   * 失败仅记日志：缓存层始终 best-effort，不影响主链路
   * @param originalPath 远端原始路径
   * @param meta 元数据
   */
  public static async writeMeta(originalPath: string, meta: CacheMeta): Promise<void> {
    const metaPath: string = CacheMetaService.getMetaPath(originalPath);
    const tmpPath: string = metaPath + '.tmp';
    try {
      const cacheDir: string = CacheConstants.getCacheDir();
      if (!fs.accessSync(cacheDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(cacheDir, true);
      }
      const file: fs.File = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        await fs.write(file.fd, JSON.stringify(meta));
        await fs.fsync(file.fd);
      } finally {
        await fs.close(file.fd);
      }
      await fs.rename(tmpPath, metaPath);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'write meta failed (transparent): %{public}s', (error as Error).message);
      try {
        await fs.unlink(tmpPath);
      } catch {
        // 临时文件不存在或清理失败：忽略
      }
    }
  }

  /**
   * 删除缓存元数据（文件不存在时忽略）
   * @param originalPath 远端原始路径
   */
  public static async deleteMeta(originalPath: string): Promise<void> {
    try {
      await fs.unlink(CacheMetaService.getMetaPath(originalPath));
    } catch {
      // 元数据不存在：忽略
    }
  }
}
