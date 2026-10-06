import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'TempFileSweeper';

/**
 * 临时文件清扫（设计文档 S7-b）
 *
 * 加载/保存管道的临时文件在正常路径上由 worker 的 finally 即删；
 * 进程被杀、崩溃或断电时可能残留，逐步占满 cacheDir。
 * - 启动时清扫上次运行的残留
 * - onDestroy 全量清扫（同步执行，避免进程退出时异步未完成）
 * 全程 best-effort：失败只记日志，不影响主流程；
 * 清扫活动文件在 POSIX 语义下安全（fd 仍有效，关闭后空间释放）
 */
export class TempFileSweeper {
  /**
   * 管道临时文件前缀：load_t0/t1/t2（解密解压中间态）、save_remote（保存远端副本）、
   * save_x1/x2/x3（S6 保存管道 inner/deflate/成品中间态）
   */
  private static readonly PREFIXES: string[] = [
    'load_t0_', 'load_t1_', 'load_t2_',
    'save_remote_', 'save_x1_', 'save_x2_', 'save_x3_'
  ];
  private static readonly SUFFIX: string = '.tmp';

  /**
   * 异步清扫 cacheDir 中的管道临时文件残留
   * @returns 删除的文件数
   */
  public static async sweep(): Promise<number> {
    let removed: number = 0;
    try {
      const cacheDir: string = CommonUtils.getCacheDir();
      const names: string[] = fs.listFileSync(cacheDir);
      for (const name of names) {
        if (!TempFileSweeper.isPipelineTemp(name)) {
          continue;
        }
        try {
          await fs.unlink(cacheDir + '/' + name);
          removed++;
        } catch (error) {
          // 单个文件清理失败（并发中的活动文件被占用等）：跳过
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'sweep failed: %{public}s', error.message);
    }
    if (removed > 0) {
      hilog.info(DOMAIN, TAG, 'sweep removed %{public}d temp files', removed);
    }
    return removed;
  }

  /**
   * 同步清扫（onDestroy 用：进程退出前确保执行完成）
   * @returns 删除的文件数
   */
  public static sweepSync(): number {
    let removed: number = 0;
    try {
      const cacheDir: string = CommonUtils.getCacheDir();
      const names: string[] = fs.listFileSync(cacheDir);
      for (const name of names) {
        if (!TempFileSweeper.isPipelineTemp(name)) {
          continue;
        }
        try {
          fs.unlinkSync(cacheDir + '/' + name);
          removed++;
        } catch (error) {
          // best effort
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'sweepSync failed: %{public}s', error.message);
    }
    if (removed > 0) {
      hilog.info(DOMAIN, TAG, 'sweepSync removed %{public}d temp files', removed);
    }
    return removed;
  }

  /**
   * 判断是否为管道临时文件（供测试与排查使用）
   */
  public static isPipelineTemp(name: string): boolean {
    if (!name.endsWith(TempFileSweeper.SUFFIX)) {
      return false;
    }
    for (const prefix of TempFileSweeper.PREFIXES) {
      if (name.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }
}
