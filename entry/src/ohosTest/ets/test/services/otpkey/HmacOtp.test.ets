import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils } from 'kdbxweb';
import { HmacOtp } from '../../../../../main/ets/services/otpkey/HmacOtp';

/**
 * RFC 4226 官方测试向量 + KP2A OtpKeyProv 生成码向量（node crypto 独立校验）。
 * secret = ASCII '12345678901234567890'（RFC 4226 Appendix D）。
 */
export default function HmacOtpTest() {
  describe('HmacOtp', () => {
    const secret = ByteUtils.stringToBytes('12345678901234567890');

    it('rfc4226 appendix d: 6-digit hotp values, counter 0-9', 0, async () => {
      const expected = ['755224', '287082', '359152', '969429', '338314',
        '254676', '287922', '162583', '399871', '520489'];
      for (let i = 0; i < expected.length; i++) {
        const code = await HmacOtp.generate(secret, i, 6, false, -1);
        expect(code).assertEqual(expected[i]);
      }
    });

    it('rfc4226 appendix d: 7-digit hotp values', 0, async () => {
      expect(await HmacOtp.generate(secret, 0, 7, false, -1)).assertEqual('4755224');
      expect(await HmacOtp.generate(secret, 1, 7, false, -1)).assertEqual('4287082');
      expect(await HmacOtp.generate(secret, 2, 7, false, -1)).assertEqual('7359152');
    });

    it('rfc4226 appendix d: 8-digit hotp values', 0, async () => {
      expect(await HmacOtp.generate(secret, 0, 8, false, -1)).assertEqual('84755224');
      expect(await HmacOtp.generate(secret, 1, 8, false, -1)).assertEqual('94287082');
      expect(await HmacOtp.generate(secret, 2, 8, false, -1)).assertEqual('37359152');
    });

    it('rfc4226 appendix d: 6-digit + luhn checksum digit', 0, async () => {
      expect(await HmacOtp.generate(secret, 0, 6, true, -1)).assertEqual('7552243');
      expect(await HmacOtp.generate(secret, 1, 6, true, -1)).assertEqual('2870822');
      expect(await HmacOtp.generate(secret, 2, 6, true, -1)).assertEqual('3591526');
    });

    it('rfc4226 appendix d: fixed truncation offsets', 0, async () => {
      expect(await HmacOtp.generate(secret, 0, 6, false, 1)).assertEqual('339280');
      expect(await HmacOtp.generate(secret, 5, 6, false, 9)).assertEqual('418534');
    });

    it('otpkeyprov aux vector: 7-digit codes at counter 5-7', 0, async () => {
      const auxSecret = ByteUtils.hexToBytes(
        '656e637279707453656372657420726f756e647472697020736563726574');
      expect(await HmacOtp.generate(auxSecret, 5, 7, false, -1)).assertEqual('3967057');
      expect(await HmacOtp.generate(auxSecret, 6, 7, false, -1)).assertEqual('2320446');
      expect(await HmacOtp.generate(auxSecret, 7, 7, false, -1)).assertEqual('1963236');
    });
  });
}
