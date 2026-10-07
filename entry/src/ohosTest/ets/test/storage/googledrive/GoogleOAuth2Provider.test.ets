import { describe, expect, it } from '@ohos/hypium';
import {
  createGoogleOAuth2Config,
  GoogleOAuth2Config,
  GoogleOAuth2Provider
} from '../../../../../main/ets/storage/googledrive/GoogleOAuth2Provider';
import { OAuth2Error, OAuth2ErrorCodes, OAuth2Token } from '../../../../../main/ets/common/oauth2';

const CLIENT_ID: string = 'g-client-id';
const CLIENT_SECRET: string = 'g-client-secret';
const REDIRECT_URI: string = 'keepassho://g/callback';

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

export default function GoogleOAuth2ProviderTest() {
  describe('GoogleOAuth2ProviderTest', () => {

    describe('createGoogleOAuth2Config', () => {
      it('should populate clientId/clientSecret/redirectUri', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.clientId).assertEqual(CLIENT_ID);
        expect(cfg.clientSecret).assertEqual(CLIENT_SECRET);
        expect(cfg.redirectUri).assertEqual(REDIRECT_URI);
      });

      it('should set Google authorize endpoint', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.authorizationEndpoint).assertEqual('https://accounts.google.com/o/oauth2/v2/auth');
      });

      it('should set Google token endpoint', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.tokenEndpoint).assertEqual('https://oauth2.googleapis.com/token');
      });

      it('should default scope to openid email profile', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.scope).assertEqual('openid email profile');
      });

      it('should default apiBaseUrl to googleapis.com', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        expect(cfg.apiBaseUrl).assertEqual('https://www.googleapis.com');
      });

      it('should accept custom scope', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI, 'https://www.googleapis.com/auth/drive.file'
        );
        expect(cfg.scope).assertEqual('https://www.googleapis.com/auth/drive.file');
      });
    });

    describe('GoogleOAuth2Provider', () => {
      it('should construct with config', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider).not().assertUndefined();
      });

      it('getProviderName should return Google', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider.getProviderName()).assertEqual('Google');
      });

      it('getConfig should return the supplied clientId', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider.getConfig().clientId).assertEqual(CLIENT_ID);
      });

      it('setConfig should replace the config', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        const cfg2: GoogleOAuth2Config = createGoogleOAuth2Config(
          'g-other', CLIENT_SECRET, REDIRECT_URI
        );
        provider.setConfig(cfg2);
        expect(provider.getConfig().clientId).assertEqual('g-other');
      });

      it('should default apiBaseUrl when not provided', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        cfg.apiBaseUrl = undefined;
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider.getProviderName()).assertEqual('Google');
      });

      it('should accept custom apiBaseUrl', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        cfg.apiBaseUrl = 'https://www.googleapis.com/v1';
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider.getProviderName()).assertEqual('Google');
      });
    });

    describe('getAuthorizationUrl', () => {
      it('should start with the Google authorize endpoint', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        const url: string = provider.getAuthorizationUrl();
        expect(url).assertContain('https://accounts.google.com/o/oauth2/v2/auth');
      });

      it('should include response_type=code', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl()).assertContain('response_type=code');
      });

      it('should include encoded client_id', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl()).assertContain('client_id=' + encodeURIComponent(CLIENT_ID));
      });

      it('should include encoded redirect_uri', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl()).assertContain('redirect_uri=' + encodeURIComponent(REDIRECT_URI));
      });

      it('should include encoded scope', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl()).assertContain('scope=' + encodeURIComponent('openid email profile'));
      });

      it('should use ? separator before params', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        const url: string = provider.getAuthorizationUrl();
        expect(url.includes('v2/auth?client_id=')).assertTrue();
      });

      it('should include state when configured', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        cfg.state = 'g-state';
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl()).assertContain('state=' + encodeURIComponent('g-state'));
      });

      it('should not include state when none configured', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        expect(provider.getAuthorizationUrl().includes('state=')).assertFalse();
      });

      it('should include authExtraParams when configured', 0, () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        cfg.authExtraParams = { 'access_type': 'offline', 'prompt': 'consent' };
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        const url: string = provider.getAuthorizationUrl();
        expect(url).assertContain('access_type=' + encodeURIComponent('offline'));
        expect(url).assertContain('prompt=' + encodeURIComponent('consent'));
      });
    });

    describe('google_getUserInfo_validation', () => {
      it('should throw OAuth2Error INVALID_PARAMETERS for empty token', 0, async () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
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
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        try {
          await provider.getUserInfo('\t  \n');
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
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        const token: TestToken = new TestToken('');
        const result: boolean = await provider.validateToken(token);
        expect(result).assertFalse();
      });

      it('should return false for expired token (no network)', 0, async () => {
        const cfg: GoogleOAuth2Config = createGoogleOAuth2Config(
          CLIENT_ID, CLIENT_SECRET, REDIRECT_URI
        );
        const provider: GoogleOAuth2Provider = new GoogleOAuth2Provider(cfg);
        const token: TestToken = new TestToken('x', Date.now() - 1000);
        const result: boolean = await provider.validateToken(token);
        expect(result).assertFalse();
      });
    });

  });
}
