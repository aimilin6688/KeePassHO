import { describe, expect, it } from '@ohos/hypium';
import { DownloadProgressAggregator } from '../../../../../main/ets/storage/huawei/HuaweiDriveClient';
import { TransferProgressCallback } from '../../../../../main/ets/storage';

/**
 * 进度回调捕获器
 */
class ProgressCapture {
  public count: number = 0;
  public lastTransferred: number = -1;
  public lastTotal: number = -1;

  asCallback(): TransferProgressCallback {
    return (transferredBytes: number, totalBytes: number): void => {
      this.count++;
      this.lastTransferred = transferredBytes;
      this.lastTotal = totalBytes;
    };
  }
}

/**
 * DownloadProgressAggregator 下载进度聚合器单元测试
 *
 * 覆盖：
 * - add 累加字节并按 (累计值, 总量) 上报
 * - 每个网络包都上报（不限频，限频由上层 ProgressThrottler 承担）
 * - 零字节包同样上报
 */
export default function DownloadProgressAggregatorTest() {
  describe('DownloadProgressAggregatorTest', () => {
    it('add accumulates bytes and reports cumulative transfer', 0, () => {
      const capture = new ProgressCapture();
      const aggregator = new DownloadProgressAggregator(1000, capture.asCallback());

      aggregator.add(100);
      expect(capture.count).assertEqual(1);
      expect(capture.lastTransferred).assertEqual(100);
      expect(capture.lastTotal).assertEqual(1000);

      aggregator.add(150);
      expect(capture.count).assertEqual(2);
      expect(capture.lastTransferred).assertEqual(250);
      expect(capture.lastTotal).assertEqual(1000);
    });

    it('add reports every packet without throttling', 0, () => {
      const capture = new ProgressCapture();
      const aggregator = new DownloadProgressAggregator(100, capture.asCallback());

      for (let i = 0; i < 10; i++) {
        aggregator.add(10);
      }
      expect(capture.count).assertEqual(10);
      expect(capture.lastTransferred).assertEqual(100);
      expect(capture.lastTotal).assertEqual(100);
    });

    it('add with zero bytes still reports', 0, () => {
      const capture = new ProgressCapture();
      const aggregator = new DownloadProgressAggregator(100, capture.asCallback());

      aggregator.add(0);
      expect(capture.count).assertEqual(1);
      expect(capture.lastTransferred).assertEqual(0);
    });
  });
}
