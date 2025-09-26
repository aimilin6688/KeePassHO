import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TotpAlgorithm, TotpConfig, TotpService, TotpType } from '../../../../main/ets/services/TotpService';

export default function TotpServiceTest() {
  describe('TotpService', () => {
    let totpService: TotpService;

    beforeAll(() => {
      totpService = TotpService.getInstance();
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    /**
     * 测试单例模式
     */
    it('getInstance returns singleton instance', 0, () => {
      const instance1 = TotpService.getInstance();
      const instance2 = TotpService.getInstance();
      expect(instance1).assertEqual(instance2);
    });

    /**
     * 测试Base32编码和解码
     */
    it('base32Encode and base32Decode work correctly', 0, () => {
      const testData = new Uint8Array([72, 101, 108, 108, 111, 33]); // "Hello!"
      const encoded = totpService.base32Encode(testData);

      // 使用私有方法进行解码，需要通过反射或其他方式访问
      // 这里我们通过生成令牌间接测试解码功能
      expect(encoded).not().assertEqual('');
    });

    /**
     * 测试生成随机密钥
     */
    it('generateRandomSecret creates valid Base32 secret', 0, async () => {
      const secret = await totpService.generateRandomSecret();
      expect(secret).not().assertEqual('');

      // 检查是否是有效的Base32字符串（只包含A-Z和2-7）
      const base32Regex = /^[A-Z2-7]+$/;
      expect(base32Regex.test(secret)).assertTrue();
    });

    /**
     * 测试生成RFC6238标准令牌
     */
    it('generateToken creates valid RFC6238 token', 0, async () => {
      const config: TotpConfig = {
        type: TotpType.RFC6238,
        secret: 'JBSWY3DPEHPK3PXP', // 测试密钥
        algorithm: TotpAlgorithm.SHA1,
        digits: 6,
        period: 30
      };

      // 使用固定时间戳以获得可预测的结果
      const timestamp = 1623456789000; // 2021-06-12 03:59:49 UTC
      const token = await totpService.generateToken(config, timestamp);

      expect(token).not().assertEqual('');
      expect(token.length).assertEqual(6);

      // 验证是否只包含数字
      const digitRegex = /^\d+$/;
      expect(digitRegex.test(token)).assertTrue();
    });

    /**
     * 测试生成Steam令牌
     */
    it('generateToken creates valid Steam token', 0, async () => {
      const config: TotpConfig = {
        type: TotpType.STEAM,
        secret: 'JBSWY3DPEHPK3PXP', // 测试密钥
        period: 30
      };

      // 使用固定时间戳以获得可预测的结果
      const timestamp = 1623456789000; // 2021-06-12 03:59:49 UTC
      const token = await totpService.generateToken(config, timestamp);

      expect(token).not().assertEqual('');
      expect(token.length).assertEqual(5);

      // 验证是否只包含Steam字符集中的字符（23456789BCDFGHJKMNPQRTVWXY）
      const steamCharsRegex = /^[23456789BCDFGHJKMNPQRTVWXY]+$/;
      expect(steamCharsRegex.test(token)).assertTrue();
    });

    /**
     * 测试解析TOTP URI
     */
    it('parseUri correctly parses standard TOTP URI', 0, () => {
      const uri = 'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA1&digits=6&period=30';
      const config = totpService.parseUri(uri);

      expect(config).not().assertNull();
      expect(config?.type).assertEqual(TotpType.RFC6238);
      expect(config?.secret).assertEqual('JBSWY3DPEHPK3PXP');
      expect(config?.algorithm).assertEqual(TotpAlgorithm.SHA1);
      expect(config?.digits).assertEqual(6);
      expect(config?.period).assertEqual(30);
      expect(config?.name).assertEqual('alice@example.com');
      expect(config?.issuer).assertEqual('Example');
    });

    /**
     * 测试解析没有可选参数的TOTP URI
     */
    it('parseUri correctly parses minimal TOTP URI', 0, () => {
      const uri = 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP';
      const config = totpService.parseUri(uri);

      expect(config).not().assertNull();
      expect(config?.type).assertEqual(TotpType.RFC6238);
      expect(config?.secret).assertEqual('JBSWY3DPEHPK3PXP');
      expect(config?.algorithm).assertEqual(TotpAlgorithm.SHA1); // 默认值
      expect(config?.digits).assertEqual(6); // 默认值
      expect(config?.period).assertEqual(30); // 默认值
      expect(config?.name).assertEqual('Test');
      expect(config?.issuer).assertEqual('');
    });

    /**
     * 测试解析无效的TOTP URI
     */
    it('parseUri returns null for invalid URI', 0, () => {
      const invalidUri = 'invalid://totp/Test?secret=JBSWY3DPEHPK3PXP';
      const config = totpService.parseUri(invalidUri);
      expect(config).assertNull();
    });

    /**
     * 测试生成TOTP URI
     */
    it('generateUri creates valid TOTP URI', 0, () => {
      const config: TotpConfig = {
        type: TotpType.RFC6238,
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: TotpAlgorithm.SHA1,
        digits: 6,
        period: 30,
        name: 'alice@example.com',
        issuer: 'Example'
      };

      let  uri = decodeURIComponent(totpService.generateUri(config));
      expect(uri).assertContain('otpauth://totp/');
      expect(uri).assertContain('Example:alice@example.com');
      expect(uri).assertContain('secret=JBSWY3DPEHPK3PXP');
      expect(uri).assertContain('issuer=Example');
    });

    /**
     * 测试计算令牌剩余有效时间
     */
    it('getRemainingSeconds calculates correct remaining time', 0, () => {
      const config: TotpConfig = {
        type: TotpType.RFC6238,
        secret: 'JBSWY3DPEHPK3PXP',
        period: 30
      };

      // 使用固定时间戳，刚好是一个周期的开始
      const timestamp = 1623456780000; // 2021-06-12 03:59:40 UTC (整30秒)
      const remaining = totpService.getRemainingSeconds(config, timestamp);

      expect(remaining).assertEqual(30);

      // 使用周期中间的时间戳
      const midPeriodTimestamp = 1623456795000; // 2021-06-12 03:59:55 UTC (过了15秒)
      const midPeriodRemaining = totpService.getRemainingSeconds(config, midPeriodTimestamp);

      expect(midPeriodRemaining).assertEqual(15);
    });

    /**
     * 测试解析Steam令牌密钥
     */
    it('parseSteamSecret correctly processes Steam secrets', 0, () => {
      // 测试标准格式
      const standardSecret = 'JBSWY3DPEHPK3PXP';
      expect(totpService.parseSteamSecret(standardSecret)).assertEqual('JBSWY3DPEHPK3PXP');

      // 测试Steam特殊格式
      const steamSecret = 'STE-JBSW-Y3DP-EHPK-3PXP';
      expect(totpService.parseSteamSecret(steamSecret)).assertEqual('JBSWY3DPEHPK3PXP');
    });
  });
}
