import { describe, expect, it } from '@ohos/hypium';
import {
  createOneDriveOAuth2Config,
  OneDriveOAuth2Config,
  OneDriveOAuth2Provider
} from '../../../../../main/ets/storage/onedrive/OneDriveOAuth2Provider';
import { OAuth2Error, OAuth2ErrorCodes, OAuth2Token } from '../../../../../main/ets/common/oauth2';

const CLIENT_ID: string = 'od-client-id';
const CLIENT_SECRET: string = 'od-client-secret';
const REDIRECT_URI: string = 'keepassho://od/callback';

class TestToken implements OAuth2Token {
  accessToken: string;
  tokenType: string;
  refreshToken?: string;
  expiresAt?: number;
  scope?: string;
  extraParams?: Record<string, string>;

  constructor(accessToken: string, expiresAt?: number) {
    this.accessToken = accessToken;
    this.tokenType = 'Bearer';
    this.expiresAt = expiresAt;
  }
}

export default function OneDriveOAuth2ProviderTest() {
  describe('OneDriveOAuth2ProviderTest', () => {

    describe('createOneDriveOAuth2Config', () => {
      it('should populate clientId/clientSecret/redirectUri', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.clientId).assertEqual(CLIENT_ID);
        expect(cfg.clientSecret).assertEqual(CLIENT_SECRET);
        expect(cfg.redirectUri).assertEqual(REDIRECT_URI);
      });

      it('should default authorize endpoint to common tenant', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.authorizationEndpoint)
          .assertEqual('https://login.microsoftonline.com/common/oauth2/v2.0/authorize');
      });

      it('should default token endpoint to common tenant', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.tokenEndpoint)
          .assertEqual('https://login.microsoftonline.com/common/oauth2/v2.0/token');
      });

      it('should default scope to Files.ReadWrite User.Read offline_access', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.scope).assertEqual('Files.ReadWrite User.Read offline_access');
      });

      it('should default apiBaseUrl to graph.microsoft.com/v1.0', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.apiBaseUrl).assertEqual('https://graph.microsoft.com/v1.0');
      });

      it('should default tenantId to common', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.tenantId).assertEqual('common');
      });

      it('should be marked as public client', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.isPublicClient).assertTrue();
      });

      it('should accept custom scope', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI, 'Files.Read'
        );
        expect(cfg.scope).assertEqual('Files.Read');
      });

      it('should accept custom tenantId and thread it into endpoints', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI, undefined, 'consumers'
        );
        expect(cfg.tenantId).assertEqual('consumers');
        expect(cfg.authorizationEndpoint)
          .assertEqual('https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize');
        expect(cfg.tokenEndpoint)
          .assertEqual('https://login.microsoftonline.com/consumers/oauth2/v2.0/token');
      });
    });

    describe('OneDriveOAuth2Provider', () => {
      it('should construct with config', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider).not().assertUndefined();
      });

      it('getProviderName should return OneDrive', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getProviderName()).assertEqual('OneDrive');
      });

      it('getConfig should return the supplied clientId', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getConfig().clientId).assertEqual(CLIENT_ID);
      });

      it('setConfig should replace the config', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        const cfg2: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          'other-id', 'other-secret', REDIRECT_URI
        );
        provider.setConfig(cfg2);
        expect(provider.getConfig().clientId).assertEqual('other-id');
      });

      it('should default apiBaseUrl when not provided', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        cfg.apiBaseUrl = undefined;
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getProviderName()).assertEqual('OneDrive');
      });

      it('should accept custom apiBaseUrl', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        cfg.apiBaseUrl = 'https://graph.microsoft.com/beta';
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getProviderName()).assertEqual('OneDrive');
      });

      it('should default tenantId when not provided', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        cfg.tenantId = undefined;
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getProviderName()).assertEqual('OneDrive');
      });
    });

    describe('getAuthorizationUrl', () => {
      it('should start with the OneDrive authorize endpoint', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        const url: string = provider.getAuthorizationUrl();
        expect(url).assertContain('https://login.microsoftonline.com/common/oauth2/v2.0/authorize');
      });

      it('should include response_type=code', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl()).assertContain('response_type=code');
      });

      it('should include encoded client_id', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl()).assertContain('client_id=' + encodeURIComponent(CLIENT_ID));
      });

      it('should include encoded redirect_uri', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl()).assertContain('redirect_uri=' + encodeURIComponent(REDIRECT_URI));
      });

      it('should include encoded scope', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI, 'Files.ReadWrite User.Read offline_access'
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl())
          .assertContain('scope=' + encodeURIComponent('Files.ReadWrite User.Read offline_access'));
      });

      it('should include ? separator before params', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        const url: string = provider.getAuthorizationUrl();
        expect(url.includes('authorize?client_id=')).assertTrue();
      });

      it('should not include state when none configured', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl().includes('state=')).assertFalse();
      });

      it('should include state when configured', 0, () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        cfg.state = 'csrf-token-123';
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl()).assertContain('state=' + encodeURIComponent('csrf-token-123'));
      });
    });

    describe('OneDrive_getUserInfo_validation', () => {
      it('should throw OAuth2Error INVALID_PARAMETERS for empty token', 0, async () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        try {
          await provider.getUserInfo('');
          expect(false).assertTrue();
        } catch (e) {
          expect(e instanceof OAuth2Error).assertTrue();
          if (e instanceof OAuth2Error) {
            expect(e.code).assertEqual(OAuth2ErrorCodes.INVALID_PARAMETERS);
          }
        }
      });

      it('should throw OAuth2Error INVALID_PARAMETERS for whitespace-only token', 0, async () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        try {
          await provider.getUserInfo('   ');
          expect(false).assertTrue();
        } catch (e) {
          expect(e instanceof OAuth2Error).assertTrue();
          if (e instanceof OAuth2Error) {
            expect(e.code).assertEqual(OAuth2ErrorCodes.INVALID_PARAMETERS);
          }
        }
      });
    });

    describe('validateToken_deterministic_branches', () => {
      it('should return false for empty access token (no network)', 0, async () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        const result: boolean = await provider.validateToken({ accessToken: '', tokenType: 'Bearer' });
        expect(result).assertFalse();
      });

      it('should return false for expired token (no network)', 0, async () => {
        const cfg: OneDriveOAuth2Config = createOneDriveOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: OneDriveOAuth2Provider = new OneDriveOAuth2Provider(cfg);
        const result: boolean = await provider.validateToken({
          accessToken: 'x',
          tokenType: 'Bearer',
          expiresAt: Date.now() - 1000
        });
        expect(result).assertFalse();
      });
    });
  });
}
