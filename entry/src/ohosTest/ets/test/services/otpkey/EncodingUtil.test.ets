import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils } from 'kdbxweb';
import {
  EncodingUtil,
  OtpDataFmt
} from '../../../../../main/ets/services/otpkey/EncodingUtil';

/**
 * 恢复模式编码解析测试：对齐 EncodingUtil.cs SelfTest（RFC 4648 Base32 向量）与 C# ParseKey 行为。
 */
export default function EncodingUtilTest() {
  describe('EncodingUtil', () => {
    it('format names map to enum values, unknown returns null', 0, () => {
      expect(EncodingUtil.getOtpDataFormat('Hex')).assertEqual(OtpDataFmt.Hex);
      expect(EncodingUtil.getOtpDataFormat('Base64')).assertEqual(OtpDataFmt.Base64);
      expect(EncodingUtil.getOtpDataFormat('UTF-8')).assertEqual(OtpDataFmt.Utf8);
      expect(EncodingUtil.getOtpDataFormat('Dec')).assertEqual(OtpDataFmt.Dec);
      expect(EncodingUtil.getOtpDataFormat('Base32')).assertEqual(OtpDataFmt.Base32);
      expect(EncodingUtil.getOtpDataFormat('Other')).assertNull();
      expect(EncodingUtil.getOtpDataFormat(undefined)).assertNull();
    });

    it('hex parse: whitespace stripped, odd length left-padded, invalid returns null', 0, () => {
      const hex = EncodingUtil.parseKey('00 10\tff', OtpDataFmt.Hex)!;
      expect(ByteUtils.bytesToHex(hex)).assertEqual('0010ff');
      // 奇数长度左补 0（对齐 C# 行为）
      expect(ByteUtils.bytesToHex(EncodingUtil.parseKey('abc', OtpDataFmt.Hex)!)).assertEqual('0abc');
      expect(EncodingUtil.parseKey('zz', OtpDataFmt.Hex)).assertNull();
      expect(EncodingUtil.parseKey('  ', OtpDataFmt.Hex)).assertNull();
    });

    it('base64 parse: valid decodes, invalid returns null', 0, () => {
      expect(ByteUtils.bytesToString(EncodingUtil.parseKey('QUJD', OtpDataFmt.Base64)!)).assertEqual('ABC');
      expect(EncodingUtil.parseKey('!!!not-base64!!!', OtpDataFmt.Base64)).assertNull();
    });

    it('base32 parse: rfc4648 selftest vectors', 0, () => {
      // 对齐 EncodingUtil.SelfTest
      expect(ByteUtils.bytesToString(EncodingUtil.parseKey('MY======', OtpDataFmt.Base32)!)).assertEqual('f');
      expect(ByteUtils.bytesToString(EncodingUtil.parseKey('MZXQ====', OtpDataFmt.Base32)!)).assertEqual('fo');
      expect(ByteUtils.bytesToString(EncodingUtil.parseKey('MZXW6===', OtpDataFmt.Base32)!)).assertEqual('foo');
      expect(ByteUtils.bytesToString(EncodingUtil.parseKey('MZXW6YQ=', OtpDataFmt.Base32)!)).assertEqual('foob');
      expect(ByteUtils.bytesToString(EncodingUtil.parseKey('MZXW6YTB', OtpDataFmt.Base32)!)).assertEqual('fooba');
      expect(ByteUtils.bytesToString(
        EncodingUtil.parseKey('MZXW6YTBOI======', OtpDataFmt.Base32)!)).assertEqual('foobar');
      expect(ByteUtils.bytesToString(EncodingUtil.parseKey(
        'JNSXSIDQOJXXM2LEMVZCAYTBONSWIIDPNYQG63TFFV2GS3LFEBYGC43TO5XXEZDTFY======',
        OtpDataFmt.Base32)!)).assertEqual('Key provider based on one-time passwords.');
    });

    it('base32 parse: lowercase accepted, bad length/char returns null', 0, () => {
      expect(ByteUtils.bytesToString(EncodingUtil.parseKey('mzxw6ytboi======', OtpDataFmt.Base32)!))
        .assertEqual('foobar');
      expect(EncodingUtil.parseKey('MZXW6Y', OtpDataFmt.Base32)).assertNull();
      expect(EncodingUtil.parseKey('MZXW6YT1', OtpDataFmt.Base32)).assertNull();
    });

    it('utf8 parse', 0, () => {
      const bytes = EncodingUtil.parseKey('secret', OtpDataFmt.Utf8)!;
      expect(ByteUtils.bytesToString(bytes)).assertEqual('secret');
    });

    it('dec parse: decimal to 8-byte big-endian, overflow/invalid returns null', 0, () => {
      // 0 → 8 字节零
      expect(ByteUtils.bytesToHex(EncodingUtil.parseKey('0', OtpDataFmt.Dec)!))
        .assertEqual('0000000000000000');
      expect(ByteUtils.bytesToHex(EncodingUtil.parseKey('1', OtpDataFmt.Dec)!))
        .assertEqual('0000000000000001');
      // 2^32
      expect(ByteUtils.bytesToHex(EncodingUtil.parseKey('4294967296', OtpDataFmt.Dec)!))
        .assertEqual('0000000100000000');
      // 2^64 - 1（ulong 上限）
      expect(ByteUtils.bytesToHex(EncodingUtil.parseKey('18446744073709551615', OtpDataFmt.Dec)!))
        .assertEqual('ffffffffffffffff');
      // 溢出 / 非十进制
      expect(EncodingUtil.parseKey('18446744073709551616', OtpDataFmt.Dec)).assertNull();
      expect(EncodingUtil.parseKey('12a', OtpDataFmt.Dec)).assertNull();
      expect(EncodingUtil.parseKey('-1', OtpDataFmt.Dec)).assertNull();
    });

    it('parseCounter: big-endian value across formats', 0, () => {
      expect(EncodingUtil.parseCounter('0A', OtpDataFmt.Hex)).assertEqual(10);
      expect(EncodingUtil.parseCounter('10', OtpDataFmt.Dec)).assertEqual(10);
      expect(EncodingUtil.parseCounter('Cg==', OtpDataFmt.Base64)).assertEqual(10);
      // utf8 '10' → 0x3130
      expect(EncodingUtil.parseCounter('10', OtpDataFmt.Utf8)).assertEqual(0x3130);
      // 超过 8 字节 → null
      expect(EncodingUtil.parseCounter('00000000000000000001', OtpDataFmt.Hex)).assertNull();
    });
  });
}
