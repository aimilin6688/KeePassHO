import { describe, expect, it } from '@ohos/hypium';
import { isKdbxDatabaseBytes } from '../../../../main/ets/services/credentials/KeyFileReader';

/**
 * KeyFileReader 密钥文件防误选 KDBX 校验纯函数单元测试。
 *
 * 对齐 KeePass 桌面版 KcpKeyFile(bThrowIfDbFile) 签名集合：
 * - 第一签名（LE u32）：0x9AA2D903（正式版 / 预发布版 / 旧版 KDB 相同）
 * - 第二签名（LE u32）：0xB54BFB67（KDBX 4.x）/ 0xB54BFB66（预发布版）/ 0xB54BFB65（KeePass 1.x KDB）
 */

/** 以 LE u32 写入前 8 字节构造内容 */
function contentOf(sig1: number, sig2: number): ArrayBuffer {
  const buf = new ArrayBuffer(64);
  const view = new DataView(buf);
  view.setUint32(0, sig1, true);
  view.setUint32(4, sig2, true);
  return buf;
}

export default function KeyFileReaderTest() {
  describe('KeyFileReader', () => {
    it('isKdbxDatabaseBytes detects kdbx4 release signature', 0, () => {
      expect(isKdbxDatabaseBytes(contentOf(0x9AA2D903, 0xB54BFB67))).assertTrue();
    });

    it('isKdbxDatabaseBytes detects kdbx pre-release signature', 0, () => {
      expect(isKdbxDatabaseBytes(contentOf(0x9AA2D903, 0xB54BFB66))).assertTrue();
    });

    it('isKdbxDatabaseBytes detects legacy kdb signature', 0, () => {
      expect(isKdbxDatabaseBytes(contentOf(0x9AA2D903, 0xB54BFB65))).assertTrue();
    });

    it('isKdbxDatabaseBytes rejects xml key file content', 0, () => {
      const xml = '<?xml version="1.0" encoding="utf-8"?><KeyFile><Meta><Version>2.0</Version></Meta></KeyFile>';
      const buf = new ArrayBuffer(xml.length);
      const bytes = new Uint8Array(buf);
      for (let i = 0; i < xml.length; i++) {
        bytes[i] = xml.charCodeAt(i) & 0xFF;
      }
      expect(isKdbxDatabaseBytes(buf)).assertFalse();
    });

    it('isKdbxDatabaseBytes rejects raw 32-byte key', 0, () => {
      expect(isKdbxDatabaseBytes(new ArrayBuffer(32))).assertFalse();
    });

    it('isKdbxDatabaseBytes rejects content shorter than 8 bytes', 0, () => {
      expect(isKdbxDatabaseBytes(new ArrayBuffer(7))).assertFalse();
      expect(isKdbxDatabaseBytes(new ArrayBuffer(0))).assertFalse();
    });

    it('isKdbxDatabaseBytes rejects non-kdbx first signature', 0, () => {
      expect(isKdbxDatabaseBytes(contentOf(0x11223344, 0xB54BFB67))).assertFalse();
      expect(isKdbxDatabaseBytes(contentOf(0x9AA2D904, 0xB54BFB67))).assertFalse();
    });
  });
}
