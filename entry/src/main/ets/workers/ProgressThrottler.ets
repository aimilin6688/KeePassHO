/**
 * 传输进度限频器（加载/保存共用）
 *
 * Worker→主线程的进度消息经此限频，保证消息量极小（最坏 2 条/秒）：
 * - 首条必放行（UI 立即进入进度态）
 * - 达 100% 必放行（末条）
 * - 其余仅在"距上次放行 ≥ minIntervalMs 且 百分比增量 ≥ minPercentStep"时放行
 *
 * 返回值约定：放行时返回当前百分比（0-100），不放行返回 -1，
 * 调用方据此构造 ProgressMessage，避免重复计算百分比
 */
export class ProgressThrottler {
  private totalBytes: number;
  private readonly minIntervalMs: number;
  private readonly minPercentStep: number;
  private lastEmitTime: number = 0;
  private lastEmitPercent: number = -1;
  private receivedAny: boolean = false;

  /**
   * 构造限频器
   * @param totalBytes 总字节数，默认 0（未知，可由首个进度事件经 onProgress 注入）
   * @param minIntervalMs 最小放行间隔（毫秒），默认 500
   * @param minPercentStep 最小百分比增量，默认 1
   */
  constructor(totalBytes: number = 0, minIntervalMs: number = 500, minPercentStep: number = 1) {
    this.totalBytes = totalBytes;
    this.minIntervalMs = minIntervalMs;
    this.minPercentStep = minPercentStep;
  }

  /**
   * 计算当前百分比（0-100，floor，上限 100；总字节未知时返回 -1）
   * @param transferredBytes 已传输字节
   * @return number 百分比；totalBytes ≤ 0 时为 -1
   */
  public static percentOf(transferredBytes: number, totalBytes: number): number {
    if (totalBytes <= 0) {
      return -1;
    }
    const percent = Math.floor(transferredBytes * 100 / totalBytes);
    return Math.min(100, Math.max(0, percent));
  }

  /**
   * 进度事件入站：判定是否放行本次进度
   * @param transferredBytes 已传输字节
   * @param totalBytes 总字节数（>0 时注入/更新分母；省略时沿用构造值）
   * @return number 放行时返回当前百分比（0-100）；不放行或总字节未知时返回 -1
   */
  public onProgress(transferredBytes: number, totalBytes?: number): number {
    if (totalBytes !== undefined && totalBytes > 0) {
      this.totalBytes = totalBytes;
    }
    const percent = ProgressThrottler.percentOf(transferredBytes, this.totalBytes);
    if (percent < 0) {
      return -1;
    }
    this.receivedAny = true;
    // 首条必放行
    if (this.lastEmitPercent < 0) {
      return this.emit(percent);
    }
    // 达 100% 必放行（末条）
    if (percent >= 100) {
      return this.emit(percent);
    }
    // 限频：时间间隔与百分比增量同时满足才放行
    const now = Date.now();
    const timeReached = now - this.lastEmitTime >= this.minIntervalMs;
    const stepReached = percent - this.lastEmitPercent >= this.minPercentStep;
    if (timeReached && stepReached) {
      return this.emit(percent);
    }
    return -1;
  }

  /**
   * 传输结束：若末条 100% 未曾放行则强制放行
   * 仅在真实事件流存在（receivedAny）时补发——存储不支持进度能力（全程零事件）时无操作，
   * 避免 UI 在从未展示进度的情况下收到"假 100%"
   * @return number 需补发时返回 100；无需补发返回 -1
   */
  public finish(): number {
    if (!this.receivedAny || this.lastEmitPercent >= 100) {
      return -1;
    }
    return this.emit(100);
  }

  /**
   * 记录放行状态并返回百分比
   */
  private emit(percent: number): number {
    this.lastEmitTime = Date.now();
    this.lastEmitPercent = percent;
    return percent;
  }
}
