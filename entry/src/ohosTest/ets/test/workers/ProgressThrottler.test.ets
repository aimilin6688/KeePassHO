import { describe, expect, it } from '@ohos/hypium';
import { ProgressThrottler } from '../../../../main/ets/workers/ProgressThrottler';

/**
 * ProgressThrottler 传输进度限频器单元测试
 *
 * 覆盖：
 * - percentOf：总字节未知 / 正常 floor 计算 / 超界钳制
 * - onProgress：首条必放行 / 100% 必放行 / 时间+步进双门槛限频 / 事件注入总字节
 * - finish：末条 100% 补发 / 已发 100% 去重 / 全程零事件无操作（防假 100%）
 */
export default function ProgressThrottlerTest() {
  describe('ProgressThrottlerTest', () => {
    // ==================== percentOf ====================

    it('percentOf returns -1 when totalBytes is 0', 0, () => {
      expect(ProgressThrottler.percentOf(100, 0)).assertEqual(-1);
    });

    it('percentOf returns -1 when totalBytes is negative', 0, () => {
      expect(ProgressThrottler.percentOf(100, -5)).assertEqual(-1);
    });

    it('percentOf computes floor percentage', 0, () => {
      expect(ProgressThrottler.percentOf(250, 1000)).assertEqual(25);
      expect(ProgressThrottler.percentOf(999, 1000)).assertEqual(99);
    });

    it('percentOf clamps to 100 when transferred exceeds total', 0, () => {
      expect(ProgressThrottler.percentOf(1500, 1000)).assertEqual(100);
    });

    it('percentOf clamps to 0 when transferred is negative', 0, () => {
      expect(ProgressThrottler.percentOf(-10, 1000)).assertEqual(0);
    });

    // ==================== onProgress ====================

    it('first event always passes', 0, () => {
      const throttler = new ProgressThrottler(1000);
      expect(throttler.onProgress(0)).assertEqual(0);
    });

    it('immediate second event with same percent is blocked', 0, () => {
      const throttler = new ProgressThrottler(1000);
      throttler.onProgress(0);
      expect(throttler.onProgress(0)).assertEqual(-1);
    });

    it('immediate event below 100 percent is blocked by time gate', 0, () => {
      const throttler = new ProgressThrottler(1000);
      throttler.onProgress(0);
      // 百分比步进足够（50%）但距上次放行 < 500ms → 拦截
      expect(throttler.onProgress(500)).assertEqual(-1);
    });

    it('event reaching 100 percent always passes regardless of time', 0, () => {
      const throttler = new ProgressThrottler(1000);
      throttler.onProgress(0);
      expect(throttler.onProgress(1000)).assertEqual(100);
    });

    it('percent step below threshold is blocked even without time gate', 0, () => {
      // minIntervalMs=0 关闭时间门槛，仅受步进门槛约束
      const throttler = new ProgressThrottler(1000, 0, 50);
      throttler.onProgress(0);
      expect(throttler.onProgress(400)).assertEqual(-1);
      expect(throttler.onProgress(500)).assertEqual(50);
    });

    it('unknown total blocks until injected by event', 0, () => {
      const throttler = new ProgressThrottler();
      expect(throttler.onProgress(500)).assertEqual(-1);
      // 事件注入总字节后首条放行
      expect(throttler.onProgress(500, 1000)).assertEqual(50);
    });

    it('zero or negative event total does not override constructor total', 0, () => {
      const throttler = new ProgressThrottler(2000);
      throttler.onProgress(1000);
      // 无效 total（0）不注入：沿用构造值，2000/2000=100% 必放行（若被覆盖为 0 则返回 -1）
      expect(throttler.onProgress(2000, 0)).assertEqual(100);
    });

    // ==================== finish ====================

    it('finish returns -1 when no event ever arrived', 0, () => {
      const throttler = new ProgressThrottler(1000);
      expect(throttler.finish()).assertEqual(-1);
    });

    it('finish returns -1 when no event passed due to unknown total', 0, () => {
      const throttler = new ProgressThrottler();
      throttler.onProgress(100);
      expect(throttler.finish()).assertEqual(-1);
    });

    it('finish emits 100 when last passed percent is below 100', 0, () => {
      const throttler = new ProgressThrottler(1000);
      throttler.onProgress(500);
      expect(throttler.finish()).assertEqual(100);
    });

    it('finish deduplicates when 100 already emitted', 0, () => {
      const throttler = new ProgressThrottler(1000);
      throttler.onProgress(1000);
      expect(throttler.finish()).assertEqual(-1);
    });

    it('finish emits only once', 0, () => {
      const throttler = new ProgressThrottler(1000);
      throttler.onProgress(500);
      expect(throttler.finish()).assertEqual(100);
      expect(throttler.finish()).assertEqual(-1);
    });
  });
}
