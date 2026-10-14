import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils } from 'kdbxweb';
import { OtpEncryptedData } from '../../../../../main/ets/services/otpkey/OtpInfo';
import { OtpUtil } from '../../../../../main/ets/services/otpkey/OtpUtil';

/**
 * 密钥派生/加解密向量测试（node crypto + 独立 Salsa20/AES-KDF 模拟生成）：
 * - KeyFromOtps：SHA-256 → AES-KDF（KeyEncryptorAes 语义）→ SHA-256；
 * - v1/v2 辅助文件夹具（OtpKeyProv 2.x 桌面版格式）解密；
 * - EncryptSecret（创建）→ DecryptSecret（校验）往返。
 */
export default function OtpUtilTest() {
  describe('OtpUtil', () => {
    const trfKeyHex = '101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f';
    const expectedKeyHex = 'f0c0f2571897c7a42e47970c97808ab4a740c9eb536bce9403543a82ff014f1f';

    it('keyFromOtps: sha256 → aes-kdf(3 rounds) → sha256', 0, async () => {
      const key = await OtpUtil.keyFromOtps(
        ['13579246', '86420975'], 0, 2,
        ByteUtils.hexToBytes(trfKeyHex), 3);
      expect(ByteUtils.bytesToHex(key)).assertEqual(expectedKeyHex);
    });

    it('keyFromOtps: otp codes are trimmed before join', 0, async () => {
      const key = await OtpUtil.keyFromOtps(
        ['  13579246  ', '86420975\t'], 0, 2,
        ByteUtils.hexToBytes(trfKeyHex), 3);
      expect(ByteUtils.bytesToHex(key)).assertEqual(expectedKeyHex);
    });

    it('encryptData/decryptData: s20 round-trip, prefix enforced', 0, () => {
      const data = ByteUtils.stringToBytes('round trip data!');
      const key32 = ByteUtils.hexToBytes(expectedKeyHex);
      const iv16 = ByteUtils.hexToBytes('00112233445566778899aabbccddeeff');
      const packed = OtpUtil.encryptData(data, key32, iv16);
      expect(packed.startsWith('s20://')).assertTrue();
      const restored = OtpUtil.decryptData(packed, key32, iv16)!;
      expect(ByteUtils.bytesToString(restored)).assertEqual('round trip data!');
      // 非 s20 前缀 → null
      expect(OtpUtil.decryptData('plain text', key32, iv16)).assertNull();
    });

    it('v2 fixture: decryptSecret verifies PlainTextHash and returns secret', 0, async () => {
      const d = new OtpEncryptedData();
      d.cipherText = 's20://IQ7Y3d0kVrXOk+6qgdcP595cd83SbK+I6S6jergcfBg=';
      d.iv = 'MDEyMzQ1Njc4OTo7PD0+Pw==';
      d.transformationKey = 'EBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8=';
      d.transformationRounds = 3;
      d.plainTextHash = 'nr9EWld3C/C3fyykGJtwlEUy9tpy9pZq56AJC6vYsGs=';
      d.plainTextHashTransformationKey = 'ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=';
      d.plainTextHashTransformationRounds = 2;

      const secret = await OtpUtil.decryptSecret(d, ['13579246', '86420975'], 0, 2);
      expect(secret).not().assertNull();
      expect(ByteUtils.bytesToHex(secret!)).assertEqual(
        '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');

      // 错误 OTP → PlainTextHash 不匹配 → null
      const wrong = await OtpUtil.decryptSecret(d, ['99999999', '88888888'], 0, 2);
      expect(wrong).assertNull();
    });

    it('v1 fixture: keyFromOtps + decryptData without hash verification', 0, async () => {
      const key = await OtpUtil.keyFromOtps(
        ['11111111', '22222222'], 0, 2,
        ByteUtils.base64ToBytes('QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8='), 2);
      expect(ByteUtils.bytesToHex(key)).assertEqual(
        '48ca327b8b24b780fd573c09903b5bf2a45508a8190d7dc53d27cafc2bde81f2');
      const secret = OtpUtil.decryptData(
        's20://kX+X9jfmfc7gjXTvvLII4Q==',
        key,
        ByteUtils.base64ToBytes('UFFSU1RVVldYWVpbXF1eXw=='))!;
      expect(ByteUtils.bytesToHex(secret)).assertEqual('76312073656372657420627974657321');
    });

    it('encryptSecret → decryptSecret round-trip (default 10000 rounds)', 0, async () => {
      const secret = ByteUtils.stringToBytes('encryptSecret roundtrip secret');
      const otps = ['13579246', '86420975'];
      const d = await OtpUtil.encryptSecret(secret, otps, 0, 2);
      expect(d.transformationRounds).assertEqual(10000);
      expect(d.plainTextHashTransformationRounds).assertEqual(10000);

      const restored = await OtpUtil.decryptSecret(d, otps, 0, 2);
      expect(restored).not().assertNull();
      expect(ByteUtils.bytesToString(restored!)).assertEqual('encryptSecret roundtrip secret');

      const wrong = await OtpUtil.decryptSecret(d, ['00000000', '11111111'], 0, 2);
      expect(wrong).assertNull();
    });
  });
}
