import { describe, expect, it } from '@ohos/hypium';
import {
  HuaweiDriveOAuth2Config,
  HuaweiDriveOAuth2Provider
} from '../../../../../main/ets/storage/huawei/HuaweiDriveOAuth2Provider';
import { OAuth2Provider } from '../../../../../main/ets/common/oauth2';
import { HuaweiDriveScope } from '../../../../../main/ets/storage/huawei/HuaweiDriveConfig';
import BuildProfile from 'BuildProfile';

export default function HuaweiDriveOAuth2ProviderTest() {
  describe('HuaweiDriveOAuth2ProviderTest', () => {

    describe('getConfig', () => {
      it('should populate clientId from BuildProfile', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        expect(cfg.clientId).assertEqual(BuildProfile.HUAWEI_DRIVE_CLIENT_ID);
      });

      it('should populate clientSecret from BuildProfile', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        expect(cfg.clientSecret).assertEqual(BuildProfile.HUAWEI_DRIVE_CLIENT_SECRET);
      });

      it('should populate redirectUri from BuildProfile', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        expect(cfg.redirectUri).assertEqual(BuildProfile.HUAWEI_DRIVE_REDIRECT_URI);
      });

      it('should expose non-empty clientId/clientSecret/redirectUri', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        expect(cfg.clientId.length > 0).assertTrue();
        expect(cfg.clientSecret.length > 0).assertTrue();
        expect(cfg.redirectUri.length > 0).assertTrue();
      });

      it('should set Huawei authorize endpoint', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        expect(cfg.authorizationEndpoint).assertEqual('https://oauth-login.cloud.huawei.com/oauth2/v3/authorize');
      });

      it('should set Huawei token endpoint', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        expect(cfg.tokenEndpoint).assertEqual('https://oauth-login.cloud.huawei.com/oauth2/v3/token');
      });

      it('should set the FULL scope', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        expect(cfg.scope).assertEqual(HuaweiDriveScope.FULL);
      });

      it('should set the APP_FILE scope', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.APP_FILE);
        expect(cfg.scope).assertEqual(HuaweiDriveScope.APP_FILE);
      });

      it('should tag provider as HUAWEI_DRIVE', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        expect(cfg.provider).assertEqual(OAuth2Provider.HUAWEI_DRIVE);
      });

      it('should include access_type=offline authExtraParams', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        expect(cfg.authExtraParams!['access_type']).assertEqual('offline');
      });

      it('should produce a new config object each call', 0, () => {
        const a: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const b: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        expect(a).not().assertEqual(b);
        expect(a.clientId).assertEqual(b.clientId);
      });
    });

    describe('HuaweiDriveOAuth2Provider_instance', () => {
      it('should construct with config', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        expect(provider).not().assertUndefined();
      });

      it('getProviderName should return HuaweiDrive', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        expect(provider.getProviderName()).assertEqual('HuaweiDrive');
      });

      it('getConfig should return the BuildProfile clientId', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        expect(provider.getConfig().clientId).assertEqual(BuildProfile.HUAWEI_DRIVE_CLIENT_ID);
      });

      it('setConfig should replace the config', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        const cfg2: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.APP_FILE);
        provider.setConfig(cfg2);
        expect(provider.getConfig().scope).assertEqual(HuaweiDriveScope.APP_FILE);
      });
    });

    describe('getAuthorizationUrl', () => {
      it('should start with the Huawei authorize endpoint', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        const url: string = provider.getAuthorizationUrl();
        expect(url).assertContain('https://oauth-login.cloud.huawei.com/oauth2/v3/authorize');
      });

      it('should include response_type=code', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl()).assertContain('response_type=code');
      });

      it('should include encoded client_id', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl())
          .assertContain('client_id=' + encodeURIComponent(BuildProfile.HUAWEI_DRIVE_CLIENT_ID));
      });

      it('should include encoded redirect_uri', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl())
          .assertContain('redirect_uri=' + encodeURIComponent(BuildProfile.HUAWEI_DRIVE_REDIRECT_URI));
      });

      it('should include encoded scope', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl())
          .assertContain('scope=' + encodeURIComponent(HuaweiDriveScope.FULL));
      });

      it('should include access_type=offline from authExtraParams', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl())
          .assertContain('access_type=' + encodeURIComponent('offline'));
      });

      it('should use ? separator before params', 0, () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        const url: string = provider.getAuthorizationUrl();
        expect(url.includes('v3/authorize?client_id=')).assertTrue();
      });
    });

    describe('getUserInfo', () => {
      // 华为云盘 API 不提供用户信息接口，provider 返回静态信息（无网络）
      it('should return static user info for any access token', 0, async () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        const info = await provider.getUserInfo('any-token');
        expect(info.userId).assertEqual('huawei_drive_user');
        expect(info.userName).assertEqual('Huawei Drive User');
      });

      it('should return static user info even for empty access token', 0, async () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        const info = await provider.getUserInfo('');
        expect(info.userId).assertEqual('huawei_drive_user');
        expect(info.userName).assertEqual('Huawei Drive User');
      });

      it('validateToken should return true for non-empty token (static getUserInfo)', 0, async () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        const result: boolean = await provider.validateToken({ accessToken: 'any', tokenType: 'Bearer' });
        expect(result).assertTrue();
      });

      it('validateToken should return false for empty token', 0, async () => {
        const cfg: HuaweiDriveOAuth2Config = HuaweiDriveOAuth2Provider.getConfig(HuaweiDriveScope.FULL);
        const provider: HuaweiDriveOAuth2Provider = new HuaweiDriveOAuth2Provider(cfg);
        const result: boolean = await provider.validateToken({ accessToken: '', tokenType: 'Bearer' });
        expect(result).assertFalse();
      });
    });
  });
}
