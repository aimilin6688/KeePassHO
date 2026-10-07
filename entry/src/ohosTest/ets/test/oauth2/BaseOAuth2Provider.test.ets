import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { http } from '@kit.NetworkKit';
import { BaseOAuth2Provider } from '../../../../main/ets/common/oauth2/BaseOAuth2Provider';
import { OAuth2Config, OAuth2Token, OAuth2UserInfo, OAuth2AuthRequest, OAuth2RefreshRequest } from '../../../../main/ets/common/oauth2/OAuth2Types';
import { OAuth2Error, OAuth2ErrorCodes } from '../../../../main/ets/common/oauth2/OAuth2Error';

function makeConfig(): OAuth2Config {
  return {
    clientId: 'test_client_id',
    clientSecret: 'test_client_secret',
    authorizationEndpoint: 'https://example.com/oauth2/authorize',
    tokenEndpoint: 'https://example.com/oauth2/token',
    redirectUri: 'keepassho://oauth2/callback'
  };
}

class TestableOAuth2Provider extends BaseOAuth2Provider {
  public cannedResponse: Record<string, Object> = {};
  public cannedError: Error | null = null;
  public cannedRevokeUrl: string | undefined = undefined;
  public cannedUserInfoError: Error | null = null;
  public lastRequestUrl: string = '';
  public lastRequestMethod: http.RequestMethod | null = null;
  public lastRequestBody: Record<string, string> | null = null;

  public async getUserInfo(accessToken: string): Promise<OAuth2UserInfo> {
    if (this.cannedUserInfoError !== null) {
      throw this.cannedUserInfoError;
    }
    const info: OAuth2UserInfo = { userId: 'user-1', userName: 'tester', email: 'tester@example.com' };
    return info;
  }

  public getProviderName(): string {
    return 'Testable';
  }

  protected getUserInfoEndpoint(): string {
    return 'https://example.com/oauth2/userinfo';
  }

  protected getRevokeUrl(): string | undefined {
    return this.cannedRevokeUrl;
  }

  protected async sendHttpRequest(url: string, method: http.RequestMethod,
    body?: Record<string, string>): Promise<Record<string, Object>> {
    this.lastRequestUrl = url;
    this.lastRequestMethod = method;
    this.lastRequestBody = body === undefined ? null : body;
    if (this.cannedError !== null) {
      throw this.cannedError;
    }
    return this.cannedResponse;
  }

  public parseTokenForTest(response: Record<string, Object>): OAuth2Token {
    return this.parseTokenResponse(response);
  }

  public urlEncodeForTest(data: Record<string, string>): string {
    return this.urlEncode(data);
  }

  public extractStringForTest(obj: Record<string, Object>, key: string, defaultValue: string = ''): string {
    return this.extractStringFromObject(obj, key, defaultValue);
  }

  public extractOptionalStringForTest(obj: Record<string, Object>, key: string): string | undefined {
    return this.extractOptionalStringFromObject(obj, key);
  }

  public extractOptionalNumberForTest(obj: Record<string, Object>, key: string): number | undefined {
    return this.extractOptionalNumberFromObject(obj, key);
  }
}

class RealNetworkOAuth2Provider extends BaseOAuth2Provider {
  public async getUserInfo(accessToken: string): Promise<OAuth2UserInfo> {
    throw new Error('getUserInfo not available in test');
  }

  public getProviderName(): string {
    return 'RealNetwork';
  }

  protected getUserInfoEndpoint(): string {
    return 'http://127.0.0.1:1/userinfo';
  }

  protected getRevokeUrl(): string | undefined {
    return 'http://127.0.0.1:1/revoke';
  }
}

async function expectOAuth2ErrorCode(promise: Promise<OAuth2Token>, expectedCode: string): Promise<void> {
  let caught: OAuth2Error | null = null;
  try {
    await promise;
  } catch (error) {
    if (error instanceof OAuth2Error) {
      caught = error;
    }
  }
  if (caught === null) {
    expect(caught).not().assertNull();
    return;
  }
  expect(caught.code).assertEqual(expectedCode);
}

export default function BaseOAuth2ProviderTest() {
  describe('BaseOAuth2ProviderTest', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    describe('GetAuthorizationUrl', () => {
      it('builds URL with required params only', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const expected = 'https://example.com/oauth2/authorize?client_id=test_client_id&redirect_uri=' +
          encodeURIComponent('keepassho://oauth2/callback') + '&response_type=code';
        expect(provider.getAuthorizationUrl()).assertEqual(expected);
      });

      it('includes encoded scope when configured', 0, () => {
        const config = makeConfig();
        config.scope = 'read write';
        const provider = new TestableOAuth2Provider(config);
        expect(provider.getAuthorizationUrl()).assertContain('&scope=' + encodeURIComponent('read write'));
      });

      it('includes encoded state when configured', 0, () => {
        const config = makeConfig();
        config.state = 'st a+te';
        const provider = new TestableOAuth2Provider(config);
        expect(provider.getAuthorizationUrl()).assertContain('&state=' + encodeURIComponent('st a+te'));
      });

      it('appends extra auth params after the standard ones', 0, () => {
        const config = makeConfig();
        const extras: Record<string, string> = {};
        extras['access_type'] = 'offline';
        extras['hd'] = 'example.com';
        config.authExtraParams = extras;
        const provider = new TestableOAuth2Provider(config);
        const url = provider.getAuthorizationUrl();
        expect(url).assertContain('&access_type=offline&hd=example.com');
        expect(url.indexOf('&access_type=offline&hd=example.com'))
          .assertLarger(url.indexOf('response_type=code'));
      });

      it('uses & separator when endpoint already contains a query', 0, () => {
        const config = makeConfig();
        config.authorizationEndpoint = 'https://example.com/oauth2/authorize?prompt=login';
        const provider = new TestableOAuth2Provider(config);
        const url = provider.getAuthorizationUrl();
        expect(url).assertContain('authorize?prompt=login&client_id=');
      });

      it('encodes special characters in client_id', 0, () => {
        const config = makeConfig();
        config.clientId = 'a b&c=d';
        const provider = new TestableOAuth2Provider(config);
        expect(provider.getAuthorizationUrl()).assertContain('client_id=' + encodeURIComponent('a b&c=d'));
      });
    });

    describe('Authorize', () => {
      it('rejects an empty authorization code with INVALID_PARAMETERS', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const req: OAuth2AuthRequest = { code: '', state: '' };
        await expectOAuth2ErrorCode(provider.authorize(req), OAuth2ErrorCodes.INVALID_PARAMETERS);
      });

      it('rejects a whitespace-only authorization code with INVALID_PARAMETERS', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const req: OAuth2AuthRequest = { code: '   ', state: '' };
        await expectOAuth2ErrorCode(provider.authorize(req), OAuth2ErrorCodes.INVALID_PARAMETERS);
      });

      it('rejects a mismatched state with STATE_MISMATCH', 0, async () => {
        const config = makeConfig();
        config.state = 'expected_state';
        const provider = new TestableOAuth2Provider(config);
        const req: OAuth2AuthRequest = { code: 'c', state: 'wrong_state' };
        await expectOAuth2ErrorCode(provider.authorize(req), OAuth2ErrorCodes.STATE_MISMATCH);
      });

      it('accepts a matching state and proceeds to the token endpoint', 0, async () => {
        const config = makeConfig();
        config.state = 'expected_state';
        const provider = new TestableOAuth2Provider(config);
        provider.cannedResponse['access_token'] = 'at_state';
        const token = await provider.authorize({ code: 'c', state: 'expected_state' });
        expect(token.accessToken).assertEqual('at_state');
      });

      it('exchanges the code for a parsed token and posts the full body', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedResponse['access_token'] = 'at_1';
        provider.cannedResponse['token_type'] = 'Bearer';
        provider.cannedResponse['refresh_token'] = 'rt_1';
        provider.cannedResponse['expires_in'] = 3600;
        provider.cannedResponse['scope'] = 'read';
        const req: OAuth2AuthRequest = { code: 'auth_code_1', state: '' };
        const token = await provider.authorize(req);
        expect(token.accessToken).assertEqual('at_1');
        expect(token.tokenType).assertEqual('Bearer');
        expect(token.refreshToken).assertEqual('rt_1');
        expect(token.scope).assertEqual('read');
        expect(token.expiresAt !== undefined).assertTrue();
        expect(provider.lastRequestUrl).assertEqual('https://example.com/oauth2/token');
        expect(provider.lastRequestMethod).assertEqual(http.RequestMethod.POST);
        expect(provider.lastRequestBody!['grant_type']).assertEqual('authorization_code');
        expect(provider.lastRequestBody!['code']).assertEqual('auth_code_1');
        expect(provider.lastRequestBody!['redirect_uri']).assertEqual('keepassho://oauth2/callback');
        expect(provider.lastRequestBody!['client_id']).assertEqual('test_client_id');
        expect(provider.lastRequestBody!['client_secret']).assertEqual('test_client_secret');
      });

      it('omits client_secret for a public client', 0, async () => {
        const config = makeConfig();
        config.isPublicClient = true;
        const provider = new TestableOAuth2Provider(config);
        provider.cannedResponse['access_token'] = 'at_pub';
        const token = await provider.authorize({ code: 'c', state: '' });
        expect(token.accessToken).assertEqual('at_pub');
        expect(provider.lastRequestBody!['client_secret']).assertUndefined();
      });

      it('wraps HTTP failures into AUTHORIZATION_FAILED', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedError = new Error('boom');
        await expectOAuth2ErrorCode(provider.authorize({ code: 'c', state: '' }),
          OAuth2ErrorCodes.AUTHORIZATION_FAILED);
      });

      it('re-wraps token fetch failures as AUTHORIZATION_FAILED', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedResponse['error'] = 'invalid_grant';
        provider.cannedResponse['error_description'] = 'bad code';
        await expectOAuth2ErrorCode(provider.authorize({ code: 'c', state: '' }),
          OAuth2ErrorCodes.AUTHORIZATION_FAILED);
      });
    });

    describe('RefreshToken', () => {
      it('rejects an empty refresh token with INVALID_PARAMETERS', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const req: OAuth2RefreshRequest = { refreshToken: '' };
        await expectOAuth2ErrorCode(provider.refreshToken(req), OAuth2ErrorCodes.INVALID_PARAMETERS);
      });

      it('rejects a whitespace-only refresh token with INVALID_PARAMETERS', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const req: OAuth2RefreshRequest = { refreshToken: '  ' };
        await expectOAuth2ErrorCode(provider.refreshToken(req), OAuth2ErrorCodes.INVALID_PARAMETERS);
      });

      it('posts the refresh token body with client credentials', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedResponse['access_token'] = 'at_new';
        provider.cannedResponse['refresh_token'] = 'rt_new';
        const req: OAuth2RefreshRequest = { refreshToken: 'rt_old' };
        const token = await provider.refreshToken(req);
        expect(token.accessToken).assertEqual('at_new');
        expect(token.refreshToken).assertEqual('rt_new');
        expect(provider.lastRequestBody!['grant_type']).assertEqual('refresh_token');
        expect(provider.lastRequestBody!['refresh_token']).assertEqual('rt_old');
        expect(provider.lastRequestBody!['client_id']).assertEqual('test_client_id');
        expect(provider.lastRequestBody!['client_secret']).assertEqual('test_client_secret');
        expect(provider.lastRequestBody!['scope']).assertUndefined();
      });

      it('includes scope in the body when provided', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedResponse['access_token'] = 'at_scoped';
        const req: OAuth2RefreshRequest = { refreshToken: 'rt', scope: 'drive.read' };
        await provider.refreshToken(req);
        expect(provider.lastRequestBody!['scope']).assertEqual('drive.read');
      });

      it('omits client_secret for a public client', 0, async () => {
        const config = makeConfig();
        config.isPublicClient = true;
        const provider = new TestableOAuth2Provider(config);
        provider.cannedResponse['access_token'] = 'at_pub2';
        const req: OAuth2RefreshRequest = { refreshToken: 'rt' };
        await provider.refreshToken(req);
        expect(provider.lastRequestBody!['client_secret']).assertUndefined();
      });

      it('wraps HTTP failures into TOKEN_REFRESH_FAILED', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedError = new Error('expired');
        const req: OAuth2RefreshRequest = { refreshToken: 'rt' };
        await expectOAuth2ErrorCode(provider.refreshToken(req), OAuth2ErrorCodes.TOKEN_REFRESH_FAILED);
      });

      it('re-wraps token fetch failures as TOKEN_REFRESH_FAILED', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedResponse['error'] = 'invalid_grant';
        const req: OAuth2RefreshRequest = { refreshToken: 'rt' };
        await expectOAuth2ErrorCode(provider.refreshToken(req), OAuth2ErrorCodes.TOKEN_REFRESH_FAILED);
      });
    });

    describe('RevokeToken', () => {
      it('skips the HTTP call when no revoke URL is configured', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedRevokeUrl = undefined;
        await provider.revokeToken('tok');
        expect(provider.lastRequestUrl).assertEqual('');
        expect(provider.lastRequestMethod).assertNull();
      });

      it('posts the token and client credentials to the revoke URL', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedRevokeUrl = 'https://example.com/oauth2/revoke';
        await provider.revokeToken('tok-1');
        expect(provider.lastRequestUrl).assertEqual('https://example.com/oauth2/revoke');
        expect(provider.lastRequestMethod).assertEqual(http.RequestMethod.POST);
        expect(provider.lastRequestBody!['token']).assertEqual('tok-1');
        expect(provider.lastRequestBody!['client_id']).assertEqual('test_client_id');
        expect(provider.lastRequestBody!['client_secret']).assertEqual('test_client_secret');
      });

      it('wraps HTTP failures into TOKEN_REVOKE_FAILED', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedRevokeUrl = 'https://example.com/oauth2/revoke';
        provider.cannedError = new Error('revoke boom');
        let caught: OAuth2Error | null = null;
        try {
          await provider.revokeToken('tok');
        } catch (error) {
          if (error instanceof OAuth2Error) {
            caught = error;
          }
        }
        expect(caught !== null).assertTrue();
        expect(caught!.code).assertEqual(OAuth2ErrorCodes.TOKEN_REVOKE_FAILED);
        expect(caught!.message).assertContain('revoke boom');
      });
    });

    describe('ValidateToken', () => {
      it('returns false for an empty access token', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const token: OAuth2Token = { accessToken: '', tokenType: 'Bearer' };
        expect(await provider.validateToken(token)).assertFalse();
      });

      it('returns false for a whitespace-only access token', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const token: OAuth2Token = { accessToken: '   ', tokenType: 'Bearer' };
        expect(await provider.validateToken(token)).assertFalse();
      });

      it('returns false for an expired token', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const token: OAuth2Token = { accessToken: 'at', tokenType: 'Bearer', expiresAt: Date.now() - 1000 };
        expect(await provider.validateToken(token)).assertFalse();
      });

      it('returns true when user info can be fetched', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const token: OAuth2Token = { accessToken: 'at-valid', tokenType: 'Bearer', expiresAt: Date.now() + 60000 };
        expect(await provider.validateToken(token)).assertTrue();
      });

      it('returns false when fetching user info fails', 0, async () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        provider.cannedUserInfoError = new Error('userinfo boom');
        const token: OAuth2Token = { accessToken: 'at-valid', tokenType: 'Bearer' };
        expect(await provider.validateToken(token)).assertFalse();
      });
    });

    describe('ParseTokenResponse', () => {
      it('maps a full token response', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const before = Date.now();
        const response: Record<string, Object> = {};
        response['access_token'] = 'at_full';
        response['token_type'] = 'bearer';
        response['refresh_token'] = 'rt_full';
        response['expires_in'] = 3600;
        response['scope'] = 'drive.read';
        const token = provider.parseTokenForTest(response);
        expect(token.accessToken).assertEqual('at_full');
        expect(token.tokenType).assertEqual('bearer');
        expect(token.refreshToken).assertEqual('rt_full');
        expect(token.scope).assertEqual('drive.read');
        expect(token.expiresAt !== undefined).assertTrue();
        expect(token.expiresAt! >= before + 3600000).assertTrue();
      });

      it('applies defaults for a minimal response', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const response: Record<string, Object> = {};
        response['access_token'] = 'at_min';
        const token = provider.parseTokenForTest(response);
        expect(token.accessToken).assertEqual('at_min');
        expect(token.tokenType).assertEqual('Bearer');
        expect(token.refreshToken).assertUndefined();
        expect(token.scope).assertUndefined();
        expect(token.expiresAt).assertUndefined();
      });

      it('throws TOKEN_FETCH_FAILED with server error details when access_token is missing', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const response: Record<string, Object> = {};
        response['error'] = 'invalid_grant';
        response['error_description'] = 'code expired';
        let caught: OAuth2Error | null = null;
        try {
          provider.parseTokenForTest(response);
        } catch (error) {
          if (error instanceof OAuth2Error) {
            caught = error;
          }
        }
        expect(caught !== null).assertTrue();
        expect(caught!.code).assertEqual(OAuth2ErrorCodes.TOKEN_FETCH_FAILED);
        expect(caught!.message).assertContain('invalid_grant');
        expect(caught!.message).assertContain('code expired');
      });

      it('throws TOKEN_FETCH_FAILED with Unknown error when no error fields exist', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const response: Record<string, Object> = {};
        let caught: OAuth2Error | null = null;
        try {
          provider.parseTokenForTest(response);
        } catch (error) {
          if (error instanceof OAuth2Error) {
            caught = error;
          }
        }
        expect(caught !== null).assertTrue();
        expect(caught!.code).assertEqual(OAuth2ErrorCodes.TOKEN_FETCH_FAILED);
        expect(caught!.message).assertContain('Unknown error');
      });

      it('throws TOKEN_FETCH_FAILED for a blank access_token', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const response: Record<string, Object> = {};
        response['access_token'] = '   ';
        let caught: OAuth2Error | null = null;
        try {
          provider.parseTokenForTest(response);
        } catch (error) {
          if (error instanceof OAuth2Error) {
            caught = error;
          }
        }
        expect(caught !== null).assertTrue();
        expect(caught!.code).assertEqual(OAuth2ErrorCodes.TOKEN_FETCH_FAILED);
      });

      it('ignores expires_in of zero or negative', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const zero: Record<string, Object> = {};
        zero['access_token'] = 'at';
        zero['expires_in'] = 0;
        expect(provider.parseTokenForTest(zero).expiresAt).assertUndefined();
        const negative: Record<string, Object> = {};
        negative['access_token'] = 'at';
        negative['expires_in'] = -5;
        expect(provider.parseTokenForTest(negative).expiresAt).assertUndefined();
      });

      it('ignores a non-numeric expires_in', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const response: Record<string, Object> = {};
        response['access_token'] = 'at';
        response['expires_in'] = 'abc';
        expect(provider.parseTokenForTest(response).expiresAt).assertUndefined();
      });

      it('accepts a numeric-string expires_in', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const before = Date.now();
        const response: Record<string, Object> = {};
        response['access_token'] = 'at';
        response['expires_in'] = '120';
        const token = provider.parseTokenForTest(response);
        expect(token.expiresAt !== undefined).assertTrue();
        expect(token.expiresAt! >= before + 120000).assertTrue();
      });
    });

    describe('ExtractHelpers', () => {
      it('extractStringFromObject returns values and defaults', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const obj: Record<string, Object> = {};
        obj['k'] = 'v';
        obj['n'] = 42;
        const nullable: Record<string, Object | null> = obj;
        nullable['nil'] = null;
        expect(provider.extractStringForTest(obj, 'k')).assertEqual('v');
        expect(provider.extractStringForTest(obj, 'n')).assertEqual('42');
        expect(provider.extractStringForTest(obj, 'nil')).assertEqual('');
        expect(provider.extractStringForTest(obj, 'missing')).assertEqual('');
        expect(provider.extractStringForTest(obj, 'missing', 'def')).assertEqual('def');
      });

      it('extractOptionalStringFromObject returns undefined for absent or null values', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const obj: Record<string, Object> = {};
        obj['k'] = 'v';
        obj['n'] = 7;
        const nullable: Record<string, Object | null> = obj;
        nullable['nil'] = null;
        expect(provider.extractOptionalStringForTest(obj, 'k')).assertEqual('v');
        expect(provider.extractOptionalStringForTest(obj, 'n')).assertEqual('7');
        expect(provider.extractOptionalStringForTest(obj, 'nil')).assertUndefined();
        expect(provider.extractOptionalStringForTest(obj, 'missing')).assertUndefined();
      });

      it('extractOptionalNumberFromObject coerces numerics and rejects NaN', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const obj: Record<string, Object> = {};
        obj['num'] = 3600;
        obj['str'] = '42';
        obj['bad'] = 'abc';
        const nullable: Record<string, Object | null> = obj;
        nullable['nil'] = null;
        expect(provider.extractOptionalNumberForTest(obj, 'num')).assertEqual(3600);
        expect(provider.extractOptionalNumberForTest(obj, 'str')).assertEqual(42);
        expect(provider.extractOptionalNumberForTest(obj, 'bad')).assertUndefined();
        expect(provider.extractOptionalNumberForTest(obj, 'nil')).assertUndefined();
        expect(provider.extractOptionalNumberForTest(obj, 'missing')).assertUndefined();
      });
    });

    describe('UrlEncode', () => {
      it('produces an empty string for empty data', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const data: Record<string, string> = {};
        expect(provider.urlEncodeForTest(data)).assertEqual('');
      });

      it('encodes keys and values and joins pairs with &', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const data: Record<string, string> = {};
        data['a b'] = 'c&d';
        data['grant_type'] = 'authorization_code';
        expect(provider.urlEncodeForTest(data)).assertEqual('a%20b=c%26d&grant_type=authorization_code');
      });
    });

    describe('ConfigAccessors', () => {
      it('getConfig returns the active config', 0, () => {
        const config = makeConfig();
        const provider = new TestableOAuth2Provider(config);
        expect(provider.getConfig().clientId).assertEqual('test_client_id');
        expect(provider.getConfig().redirectUri).assertEqual('keepassho://oauth2/callback');
      });

      it('setConfig replaces the active config', 0, () => {
        const provider = new TestableOAuth2Provider(makeConfig());
        const next = makeConfig();
        next.clientId = 'next_client';
        provider.setConfig(next);
        expect(provider.getConfig().clientId).assertEqual('next_client');
      });
    });

    describe('RealNetworkFailures', () => {
      it('authorize wraps unreachable-endpoint failures into AUTHORIZATION_FAILED', 0, async () => {
        const config = makeConfig();
        config.tokenEndpoint = 'http://127.0.0.1:1/token';
        const provider = new RealNetworkOAuth2Provider(config);
        const req: OAuth2AuthRequest = { code: 'c', state: '' };
        await expectOAuth2ErrorCode(provider.authorize(req), OAuth2ErrorCodes.AUTHORIZATION_FAILED);
      });

      it('refreshToken wraps unreachable-endpoint failures into TOKEN_REFRESH_FAILED', 0, async () => {
        const config = makeConfig();
        config.tokenEndpoint = 'http://127.0.0.1:1/token';
        const provider = new RealNetworkOAuth2Provider(config);
        const req: OAuth2RefreshRequest = { refreshToken: 'rt' };
        await expectOAuth2ErrorCode(provider.refreshToken(req), OAuth2ErrorCodes.TOKEN_REFRESH_FAILED);
      });

      it('revokeToken wraps unreachable-endpoint failures into TOKEN_REVOKE_FAILED', 0, async () => {
        const provider = new RealNetworkOAuth2Provider(makeConfig());
        let caught: OAuth2Error | null = null;
        try {
          await provider.revokeToken('tok');
        } catch (error) {
          if (error instanceof OAuth2Error) {
            caught = error;
          }
        }
        expect(caught !== null).assertTrue();
        expect(caught!.code).assertEqual(OAuth2ErrorCodes.TOKEN_REVOKE_FAILED);
      });

      it('validateToken returns false when user info cannot be fetched', 0, async () => {
        const provider = new RealNetworkOAuth2Provider(makeConfig());
        const token: OAuth2Token = { accessToken: 'looks-valid', tokenType: 'Bearer' };
        expect(await provider.validateToken(token)).assertFalse();
      });
    });
  });
}
