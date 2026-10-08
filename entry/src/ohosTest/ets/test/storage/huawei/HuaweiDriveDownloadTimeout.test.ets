import { describe, expect, it } from '@ohos/hypium';
import { HuaweiDriveClient } from '../../../../../main/ets/storage/huawei/HuaweiDriveClient';

const KB = 1024;
const MB = 1024 * 1024;

/**
 * 华为云盘下载请求超时计算单元测试（纯计算，无网络）：
 * axios timeout 为请求总时长——8MB 分块在 ~260KB/s 弱网需 ~32s，
 * 实例级 30s 总超时会恰好在块完成前杀掉请求（2300028 Operation timeout 实测根因）。
 * downloadRequestTimeout 按传输字节量与保守速率下限（64KB/s）放大，用户更大配置优先
 */
export default function HuaweiDriveDownloadTimeoutTest() {
  describe('HuaweiDriveDownloadTimeoutTest', () => {
    it('8MB chunk gets 128s timeout at 64KB/s floor', 0, () => {
      const timeout = HuaweiDriveClient.downloadRequestTimeout(8 * MB);
      expect(timeout).assertEqual(128 * 1000);
    });

    it('whole-file fallback scales with size (32MB -> 512s)', 0, () => {
      const timeout = HuaweiDriveClient.downloadRequestTimeout(32 * MB);
      expect(timeout).assertEqual(512 * 1000);
    });

    it('small transfers keep 30s floor', 0, () => {
      const timeout = HuaweiDriveClient.downloadRequestTimeout(64 * KB);
      expect(timeout).assertEqual(30 * 1000);
    });

    it('larger user-configured timeout wins', 0, () => {
      const timeout = HuaweiDriveClient.downloadRequestTimeout(8 * MB, 600 * 1000);
      expect(timeout).assertEqual(600 * 1000);
    });

    it('smaller user-configured timeout is raised to size-based value', 0, () => {
      const timeout = HuaweiDriveClient.downloadRequestTimeout(8 * MB, 10 * 1000);
      expect(timeout).assertEqual(128 * 1000);
    });

    it('zero bytes falls back to 30s floor', 0, () => {
      const timeout = HuaweiDriveClient.downloadRequestTimeout(0);
      expect(timeout).assertEqual(30 * 1000);
    });
  });
}
