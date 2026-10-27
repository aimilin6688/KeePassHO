import { describe, expect, it } from '@ohos/hypium';
import {
  CsvEncoding,
  CsvEncodingUtils
} from '../../../../main/ets/services/importExport/csvimport/CsvEncodingUtils';

/**
 * CsvEncodingUtils 单元测试
 * 检测策略：UTF-8 BOM → 严格 UTF-8 字节序列校验 → 回退 GBK
 * '你好' GBK = C4 E3 BA C3；UTF-8 = E4 BD A0 E5 A5 BD
 */
export default function CsvEncodingUtilsTest() {
  describe('CsvEncodingUtils', () => {
    describe('detect', () => {
      it('shouldDetectUtf8WithBom', 0, () => {
        const bytes = new Uint8Array([0xEF, 0xBB, 0xBF, 0x61, 0x62, 0x63]);
        expect(CsvEncodingUtils.detect(bytes)).assertEqual(CsvEncoding.UTF8);
      });

      it('shouldDetectUtf8Chinese', 0, () => {
        // '你好' UTF-8
        const bytes = new Uint8Array([0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD]);
        expect(CsvEncodingUtils.detect(bytes)).assertEqual(CsvEncoding.UTF8);
      });

      it('shouldDetectGbkChinese', 0, () => {
        // '你好' GBK：C4 非法 UTF-8 首字节 → 回退 GBK
        const bytes = new Uint8Array([0xC4, 0xE3, 0xBA, 0xC3]);
        expect(CsvEncodingUtils.detect(bytes)).assertEqual(CsvEncoding.GBK);
      });

      it('shouldDetectAsciiAsUtf8', 0, () => {
        // 纯 ASCII 对 UTF-8/GBK 同构，按 UTF-8 处理
        const bytes = new Uint8Array([0x6E, 0x61, 0x6D, 0x65, 0x2C, 0x74, 0x69, 0x74, 0x6C, 0x65]);
        expect(CsvEncodingUtils.detect(bytes)).assertEqual(CsvEncoding.UTF8);
      });

      it('shouldDetectEmptyAsUtf8', 0, () => {
        expect(CsvEncodingUtils.detect(new Uint8Array(0))).assertEqual(CsvEncoding.UTF8);
      });

      it('shouldDetectGbkRowWithAsciiHeader', 0, () => {
        // 'name,你好,note' GBK：'你' = C4 E3，C4 非法 UTF-8 首字节
        const bytes = new Uint8Array([
          0x6E, 0x61, 0x6D, 0x65, 0x2C, 0xC4, 0xE3, 0xBA, 0xC3, 0x2C, 0x6E, 0x6F, 0x74, 0x65
        ]);
        expect(CsvEncodingUtils.detect(bytes)).assertEqual(CsvEncoding.GBK);
      });
    });

    describe('decode', () => {
      it('shouldDecodeGbkBytes', 0, () => {
        const bytes = new Uint8Array([0xC4, 0xE3, 0xBA, 0xC3]);
        expect(CsvEncodingUtils.decode(bytes, CsvEncoding.GBK)).assertEqual('你好');
      });

      it('shouldDecodeUtf8Bytes', 0, () => {
        const bytes = new Uint8Array([0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD]);
        expect(CsvEncodingUtils.decode(bytes, CsvEncoding.UTF8)).assertEqual('你好');
      });

      it('shouldDecodeAsciiWithEitherEncoding', 0, () => {
        const bytes = new Uint8Array([0x61, 0x62, 0x63]);
        expect(CsvEncodingUtils.decode(bytes, CsvEncoding.GBK)).assertEqual('abc');
        expect(CsvEncodingUtils.decode(bytes, CsvEncoding.UTF8)).assertEqual('abc');
      });
    });

    describe('decodeAuto', () => {
      it('shouldDecodeGbkBufferAutomatically', 0, () => {
        // '你好' GBK
        const buffer = new Uint8Array([0xC4, 0xE3, 0xBA, 0xC3]).buffer as ArrayBuffer;
        expect(CsvEncodingUtils.decodeAuto(buffer)).assertEqual('你好');
      });

      it('shouldDecodeUtf8BufferAutomatically', 0, () => {
        // '你好' UTF-8
        const buffer = new Uint8Array([0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD]).buffer as ArrayBuffer;
        expect(CsvEncodingUtils.decodeAuto(buffer)).assertEqual('你好');
      });

      it('shouldDecodeAsciiBuffer', 0, () => {
        const buffer = new Uint8Array([0x61, 0x2C, 0x62]).buffer as ArrayBuffer;
        expect(CsvEncodingUtils.decodeAuto(buffer)).assertEqual('a,b');
      });
    });

    describe('hasUtf8Bom', () => {
      it('shouldDetectBom', 0, () => {
        expect(CsvEncodingUtils.hasUtf8Bom(new Uint8Array([0xEF, 0xBB, 0xBF, 0x61]))).assertTrue();
      });

      it('shouldRejectMissingBom', 0, () => {
        expect(CsvEncodingUtils.hasUtf8Bom(new Uint8Array([0xEF, 0xBB, 0x61]))).assertFalse();
        expect(CsvEncodingUtils.hasUtf8Bom(new Uint8Array([0x61, 0x62, 0x63]))).assertFalse();
        expect(CsvEncodingUtils.hasUtf8Bom(new Uint8Array(0))).assertFalse();
      });
    });

    describe('isValidUtf8', () => {
      it('shouldAcceptValidSequences', 0, () => {
        // ASCII + 2/3/4 字节序列 + Emoji（U+1F600）
        const bytes = new Uint8Array([
          0x61, 0xE4, 0xBD, 0xA0, 0xE8, 0x80, 0x80, 0xF0, 0x9F, 0x98, 0x80
        ]);
        expect(CsvEncodingUtils.isValidUtf8(bytes)).assertTrue();
      });

      it('shouldRejectGbkBytes', 0, () => {
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array([0xC4, 0xE3, 0xBA, 0xC3]))).assertFalse();
      });

      it('shouldRejectOverlongEncoding', 0, () => {
        // C0 80 = U+0000 过长编码（首字节 C0/C1 非法）
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array([0xC0, 0x80]))).assertFalse();
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array([0xC1, 0xBF]))).assertFalse();
      });

      it('shouldRejectSurrogateRange', 0, () => {
        // ED A0 80 = U+D800 UTF-16 代理区
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array([0xED, 0xA0, 0x80]))).assertFalse();
        // ED 9F BF = U+D7FF 合法上界
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array([0xED, 0x9F, 0xBF]))).assertTrue();
      });

      it('shouldRejectOutOfRangeCodePoint', 0, () => {
        // F4 90 80 80 = U+110000 越界；F4 8F BF BF = U+10FFFF 合法上界
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array([0xF4, 0x90, 0x80, 0x80]))).assertFalse();
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array([0xF4, 0x8F, 0xBF, 0xBF]))).assertTrue();
      });

      it('shouldRejectTruncatedSequence', 0, () => {
        // 截断的 3 字节序列
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array([0xE4, 0xBD]))).assertFalse();
        // 后续字节越出 0x80-0xBF
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array([0xE4, 0xBD, 0x41]))).assertFalse();
      });

      it('shouldRejectFiveByteLead', 0, () => {
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array([0xF8, 0x80, 0x80, 0x80, 0x80]))).assertFalse();
      });

      it('shouldAcceptEmpty', 0, () => {
        expect(CsvEncodingUtils.isValidUtf8(new Uint8Array(0))).assertTrue();
      });
    });
  });
}
