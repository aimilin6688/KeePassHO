import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils } from 'kdbxweb';
import { OtpDataFmt } from '../../../../../main/ets/services/otpkey/EncodingUtil';
import { OtpInfo } from '../../../../../main/ets/services/otpkey/OtpInfo';
import {
  OtpKeyProvService
} from '../../../../../main/ets/services/otpkey/OtpKeyProvService';

/**
 * OtpKeyProv 编排测试：v1/v2 派生、前瞻窗口偏移、恢复模式、辅助文件名定位。
 * 向量由 node crypto 独立生成（对齐 KP2A OathHotpKeyProv 流程）。
 */
export default function OtpKeyProvServiceTest() {
  describe('OtpKeyProvService', () => {
    it('v2 fixture: derive secret from otps, counterDelta = otpsRequired + 0', 0, async () => {
      const xml = '<?xml version="1.0" encoding="utf-8"?>\n' +
        '<OtpInfo>\n' +
        '\t<Version>2.0</Version>\n' +
        '\t<EncryptedSecrets>\n' +
        '\t\t<EncryptedData>\n' +
        '\t\t\t<CipherText>s20://IQ7Y3d0kVrXOk+6qgdcP595cd83SbK+I6S6jergcfBg=</CipherText>\n' +
        '\t\t\t<IV>MDEyMzQ1Njc4OTo7PD0+Pw==</IV>\n' +
        '\t\t\t<TransformationKey>EBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8=</TransformationKey>\n' +
        '\t\t\t<TransformationRounds>3</TransformationRounds>\n' +
        '\t\t\t<PlainTextHash>nr9EWld3C/C3fyykGJtwlEUy9tpy9pZq56AJC6vYsGs=</PlainTextHash>\n' +
        '\t\t\t<PlainTextHashTransformationKey>ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=</PlainTextHashTransformationKey>\n' +
        '\t\t\t<PlainTextHashTransformationRounds>2</PlainTextHashTransformationRounds>\n' +
        '\t\t</EncryptedData>\n' +
        '\t</EncryptedSecrets>\n' +
        '\t<Counter>0</Counter>\n' +
        '\t<OtpLength>8</OtpLength>\n' +
        '\t<OtpsRequired>2</OtpsRequired>\n' +
        '</OtpInfo>';
      const info = OtpInfo.fromXml(xml);
      const result = await OtpKeyProvService.deriveSecretFromOtps(info, ['13579246', '86420975']);
      expect(result.secretHex).assertEqual(
        '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
      expect(result.counterDelta).assertEqual(2);
      // v2 命中即 PlainTextHash 校验通过：加载前可安全写回 Counter
      expect(result.verified).assertTrue();
    });

    it('v1 fixture: derive secret from otps (no hash verification path)', 0, async () => {
      const xml = '<?xml version="1.0" encoding="utf-8"?>\n' +
        '<OtpInfo>\n' +
        '\t<Version>1.0</Version>\n' +
        '\t<EncryptedSecret>s20://kX+X9jfmfc7gjXTvvLII4Q==</EncryptedSecret>\n' +
        '\t<EncryptionIV>UFFSU1RVVldYWVpbXF1eXw==</EncryptionIV>\n' +
        '\t<TransformationKey>QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8=</TransformationKey>\n' +
        '\t<TransformationRounds>2</TransformationRounds>\n' +
        '\t<Counter>0</Counter>\n' +
        '\t<OtpLength>8</OtpLength>\n' +
        '\t<OtpsRequired>2</OtpsRequired>\n' +
        '</OtpInfo>';
      const info = OtpInfo.fromXml(xml);
      const result = await OtpKeyProvService.deriveSecretFromOtps(info, ['11111111', '22222222']);
      expect(result.secretHex).assertEqual('76312073656372657420627974657321');
      expect(result.counterDelta).assertEqual(2);
      // v1 派生无 PlainTextHash 校验：解锁成功前不得提前写回 Counter
      expect(result.verified).assertFalse();
    });

    it('v2 look-ahead: user enters 2nd/3rd codes → hits item i=1, delta = otpsRequired + 1', 0, async () => {
      // secret = 'encryptSecret roundtrip secret'，counter=5，otpLength=7，otpsRequired=2，lookAhead=1
      const secret = ByteUtils.stringToBytes('encryptSecret roundtrip secret');
      const info = new OtpInfo();
      info.otpLength = 7;
      info.otpsRequired = 2;
      info.lookAheadCount = 1;
      info.counter = 5;

      await OtpKeyProvService.encryptOtpInfoSecret(info, secret);
      expect(info.type).assertEqual('OATH HOTP / RFC 4226');
      expect(info.version).assertEqual('2.0');
      expect(info.encryptedSecret).assertEqual('');
      expect(info.encryptedSecrets.length).assertEqual(2);

      // 生成码应为 HOTP(secret, 5/6/7, 7 位) = 3967057 / 2320446 / 1963236
      const result = await OtpKeyProvService.deriveSecretFromOtps(info, ['2320446', '1963236']);
      expect(result.secretHex).assertEqual(ByteUtils.bytesToHex(secret));
      expect(result.counterDelta).assertEqual(3);
      // 前瞻窗口命中同样经过 PlainTextHash 校验
      expect(result.verified).assertTrue();
    });

    it('wrong otps: v2 derive throws (all look-ahead items fail)', 0, async () => {
      const secret = ByteUtils.stringToBytes('encryptSecret roundtrip secret');
      const info = new OtpInfo();
      info.otpLength = 7;
      info.otpsRequired = 2;
      info.lookAheadCount = 0;
      info.counter = 0;
      await OtpKeyProvService.encryptOtpInfoSecret(info, secret);

      let threw = false;
      try {
        await OtpKeyProvService.deriveSecretFromOtps(info, ['0000000', '1111111']);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('recovery mode: hex/base64/base32 encodings parse to same secret', 0, () => {
      const secretHex = '000102030405060708090a0b0c0d0e0f';
      const secret = ByteUtils.hexToBytes(secretHex);
      // 同一 secret 的三种二进制编码
      expect(ByteUtils.bytesToHex(
        OtpKeyProvService.deriveSecretFromRecoveryInput(secretHex, OtpDataFmt.Hex)))
        .assertEqual(secretHex);
      expect(ByteUtils.bytesToHex(OtpKeyProvService.deriveSecretFromRecoveryInput(
        ByteUtils.bytesToBase64(secret), OtpDataFmt.Base64))).assertEqual(secretHex);
      expect(ByteUtils.bytesToHex(OtpKeyProvService.deriveSecretFromRecoveryInput(
        'AAAQEAYEAUDAOCAJBIFQYDIOB4======', OtpDataFmt.Base32))).assertEqual(secretHex);

      // utf8：可打印 secret 直接解析（VT/FF 等空白字符会被 trim，与 C# 一致）
      const printable = 'recovery-secret!';
      expect(ByteUtils.bytesToString(OtpKeyProvService.deriveSecretFromRecoveryInput(
        printable, OtpDataFmt.Utf8))).assertEqual(printable);

      // 非法输入抛错
      let threw = false;
      try {
        OtpKeyProvService.deriveSecretFromRecoveryInput('zz!!', OtpDataFmt.Hex);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('buildAuxFileName: db name → aux file name in same directory', 0, () => {
      expect(OtpKeyProvService.buildAuxFileName('test.kdbx')).assertEqual('test.otp.xml');
      expect(OtpKeyProvService.buildAuxFileName('/a/b/my.db.kdbx')).assertEqual('my.db.otp.xml');
      expect(OtpKeyProvService.buildAuxFileName('noext')).assertEqual('noext.otp.xml');
    });
  });
}
