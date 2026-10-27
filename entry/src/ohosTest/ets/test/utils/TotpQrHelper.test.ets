import { describe, expect, it } from '@ohos/hypium';
import { TotpQrHelper } from '../../../../main/ets/common/utils/TotpQrHelper';
import { TotpAlgorithm, TotpConfig, TotpService, TotpType } from '../../../../main/ets/services/TotpService';

export default function TotpQrHelperTest() {
  describe('TotpQrHelper', () => {
    const totpService: TotpService = TotpService.getInstance();

    it('buildQrContent returns original uri when name and issuer both present', 0, () => {
      const uri = 'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example';
      const result = TotpQrHelper.buildQrContent(uri, 'MyEntry');
      expect(result).assertEqual(uri);
    });

    it('buildQrContent returns original uri when only name present', 0, () => {
      const uri = 'otpauth://totp/alice@example.com?secret=JBSWY3DPEHPK3PXP';
      const result = TotpQrHelper.buildQrContent(uri, 'MyEntry');
      expect(result).assertEqual(uri);
    });

    it('buildQrContent returns original uri when only issuer present', 0, () => {
      const uri = 'otpauth://totp/Example?secret=JBSWY3DPEHPK3PXP&issuer=Example';
      const result = TotpQrHelper.buildQrContent(uri, 'MyEntry');
      expect(result).assertEqual(uri);
    });

    it('buildQrContent returns original uri for steam uri', 0, () => {
      const uri = 'otpauth://totp/Steam:user?secret=JBSWY3DPEHPK3PXP&issuer=Steam&encoder=steam';
      const result = TotpQrHelper.buildQrContent(uri, 'MyEntry');
      expect(result).assertEqual(uri);
    });

    it('buildQrContent fills name from entryTitle when name and issuer both empty', 0, () => {
      const uri = 'otpauth://totp/?secret=JBSWY3DPEHPK3PXP';
      const result = TotpQrHelper.buildQrContent(uri, 'My Entry');
      expect(result).assertEqual('otpauth://totp/My%20Entry?secret=JBSWY3DPEHPK3PXP');
      if (result !== null) {
        const parsed = totpService.parseUri(result);
        expect(parsed).not().assertNull();
        if (parsed !== null) {
          expect(parsed.name).assertEqual('My Entry');
          expect(parsed.secret).assertEqual('JBSWY3DPEHPK3PXP');
        }
      }
    });

    it('buildQrContent trims entryTitle before filling name', 0, () => {
      const uri = 'otpauth://totp/?secret=JBSWY3DPEHPK3PXP';
      const result = TotpQrHelper.buildQrContent(uri, '  My Entry  ');
      expect(result).assertEqual('otpauth://totp/My%20Entry?secret=JBSWY3DPEHPK3PXP');
    });

    it('buildQrContent returns original uri when title empty and labels empty', 0, () => {
      const uri = 'otpauth://totp/?secret=JBSWY3DPEHPK3PXP';
      const result = TotpQrHelper.buildQrContent(uri, '   ');
      expect(result).assertEqual(uri);
    });

    it('buildQrContent fills name for steam uri and keeps encoder', 0, () => {
      const uri = 'otpauth://totp/?secret=JBSWY3DPEHPK3PXP&encoder=steam';
      const result = TotpQrHelper.buildQrContent(uri, 'SteamEntry');
      expect(result).not().assertNull();
      if (result !== null) {
        const parsed = totpService.parseUri(result);
        expect(parsed).not().assertNull();
        if (parsed !== null) {
          expect(parsed.name).assertEqual('SteamEntry');
          expect(parsed.type).assertEqual(TotpType.STEAM);
          expect(parsed.secret).assertEqual('JBSWY3DPEHPK3PXP');
        }
      }
    });

    it('buildQrContent returns null for empty uri', 0, () => {
      const result = TotpQrHelper.buildQrContent('', 'MyEntry');
      expect(result).assertNull();
    });

    it('buildQrContent returns null for non-otpauth uri', 0, () => {
      const result = TotpQrHelper.buildQrContent('https://example.com/otpauth?secret=JBSWY3DPEHPK3PXP', 'MyEntry');
      expect(result).assertNull();
    });

    it('buildQrContent returns null for uri without secret', 0, () => {
      const result = TotpQrHelper.buildQrContent('otpauth://totp/Test', 'MyEntry');
      expect(result).assertNull();
    });

    it('buildQrContent returns null for uri exceeding 512 chars', 0, () => {
      let longSecret = '';
      for (let i = 0; i < 600; i++) {
        longSecret += 'A';
      }
      const uri = `otpauth://totp/Long?secret=${longSecret}`;
      const result = TotpQrHelper.buildQrContent(uri, 'MyEntry');
      expect(result).assertNull();
    });

    it('buildQrContent returns original uri for uri within 512 chars', 0, () => {
      let secret400 = '';
      for (let i = 0; i < 400; i++) {
        secret400 += 'A';
      }
      const uri = `otpauth://totp/Long?secret=${secret400}`;
      const result = TotpQrHelper.buildQrContent(uri, 'MyEntry');
      expect(result).assertEqual(uri);
    });

    it('buildQrContent round-trip preserves config for non-default params', 0, () => {
      const configs: TotpConfig[] = [
        {
          type: TotpType.RFC6238,
          secret: 'JBSWY3DPEHPK3PXP',
          algorithm: TotpAlgorithm.SHA256,
          digits: 8,
          period: 60,
          name: 'alice',
          issuer: 'Example'
        },
        {
          type: TotpType.RFC6238,
          secret: 'JBSWY3DPEHPK3PXP',
          algorithm: TotpAlgorithm.SHA512,
          digits: 6,
          period: 30,
          name: 'bob',
          issuer: 'Example'
        },
        {
          type: TotpType.STEAM,
          secret: 'JBSWY3DPEHPK3PXP',
          algorithm: TotpAlgorithm.SHA1,
          digits: 5,
          period: 30,
          name: 'steamuser',
          issuer: 'Steam'
        }
      ];
      for (const config of configs) {
        const uri = totpService.generateUri(config);
        const result = TotpQrHelper.buildQrContent(uri, 'EntryTitle');
        expect(result).not().assertNull();
        if (result !== null) {
          expect(result).assertEqual(uri);
          const parsed = totpService.parseUri(result);
          expect(parsed).not().assertNull();
          if (parsed !== null) {
            expect(parsed.secret).assertEqual(config.secret);
            expect(parsed.algorithm).assertEqual(config.algorithm ?? TotpAlgorithm.SHA1);
            expect(parsed.digits).assertEqual(config.digits ?? 6);
            expect(parsed.period).assertEqual(config.period ?? 30);
            if (config.type === TotpType.STEAM) {
              expect(parsed.type).assertEqual(TotpType.STEAM);
            }
          }
        }
      }
    });
  });
}
