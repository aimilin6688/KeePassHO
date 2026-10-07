import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { IOAuth2Provider } from '../../../../main/ets/common/oauth2/IOAuth2Provider';
import { OAuth2Config, OAuth2Token, OAuth2UserInfo, OAuth2AuthRequest, OAuth2RefreshRequest } from '../../../../main/ets/common/oauth2/OAuth2Types';

class IOAuth2ProviderStub implements IOAuth2Provider {
  private config: OAuth2Config;
  public cannedToken: OAuth2Token;
  public cannedValidateResult: boolean = true;
  public lastAuthRequest: OAuth2AuthRequest | null = null;
  public lastRefreshRequest: OAuth2RefreshRequest | null = null;
  public lastUserInfoToken: string = '';
  public lastRevokedToken: string = '';
  public lastValidatedToken: OAuth2Token | null = null;
  public lastSetConfig: OAuth2Config | null = null;

  constructor(config: OAuth2Config, cannedToken: OAuth2Token) {
    this.config = config;
    this.cannedToken = cannedToken;
  }

  public getAuthorizationUrl(): string {
    return this.config.authorizationEndpoint + '?client_id=' + this.config.clientId;
  }

  public async authorize(authRequest: OAuth2AuthRequest): Promise<OAuth2Token> {
    this.lastAuthRequest = authRequest;
    return this.cannedToken;
  }

  public async refreshToken(refreshRequest: OAuth2RefreshRequest): Promise<OAuth2Token> {
    this.lastRefreshRequest = refreshRequest;
    return this.cannedToken;
  }

  public async getUserInfo(accessToken: string): Promise<OAuth2UserInfo> {
    this.lastUserInfoToken = accessToken;
    const info: OAuth2UserInfo = { userId: 'u-1', userName: 'stub-user' };
    return info;
  }

  public async revokeToken(accessToken: string): Promise<void> {
    this.lastRevokedToken = accessToken;
  }

  public async validateToken(token: OAuth2Token): Promise<boolean> {
    this.lastValidatedToken = token;
    return this.cannedValidateResult;
  }

  public getProviderName(): string {
    return 'StubProvider';
  }

  public getConfig(): OAuth2Config {
    return this.config;
  }

  public setConfig(config: OAuth2Config): void {
    this.lastSetConfig = config;
    this.config = config;
  }
}

function makeConfig(): OAuth2Config {
  return {
    clientId: 'cid',
    clientSecret: 'secret',
    authorizationEndpoint: 'https://example.com/authorize',
    tokenEndpoint: 'https://example.com/token',
    redirectUri: 'keepassho://callback'
  };
}

function makeStub(): IOAuth2ProviderStub {
  const token: OAuth2Token = { accessToken: 'canned_at', tokenType: 'Bearer', refreshToken: 'canned_rt' };
  return new IOAuth2ProviderStub(makeConfig(), token);
}

export default function IOAuth2ProviderTest() {
  describe('IOAuth2ProviderTest', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('stub implementation can be assigned to the interface type', 0, () => {
      const provider: IOAuth2Provider = makeStub();
      expect(provider.getProviderName()).assertEqual('StubProvider');
    });

    it('getAuthorizationUrl builds the URL from the active config', 0, () => {
      const provider: IOAuth2Provider = makeStub();
      expect(provider.getAuthorizationUrl()).assertEqual('https://example.com/authorize?client_id=cid');
    });

    it('authorize returns the canned token and records the request', 0, async () => {
      const stub = makeStub();
      const provider: IOAuth2Provider = stub;
      const req: OAuth2AuthRequest = { code: 'c1', state: 's1' };
      const token = await provider.authorize(req);
      expect(token.accessToken).assertEqual('canned_at');
      expect(token.refreshToken).assertEqual('canned_rt');
      expect(stub.lastAuthRequest !== null).assertTrue();
      expect(stub.lastAuthRequest!.code).assertEqual('c1');
      expect(stub.lastAuthRequest!.state).assertEqual('s1');
    });

    it('refreshToken returns the canned token and records the request', 0, async () => {
      const stub = makeStub();
      const provider: IOAuth2Provider = stub;
      const req: OAuth2RefreshRequest = { refreshToken: 'rt-1', scope: 'read' };
      const token = await provider.refreshToken(req);
      expect(token.accessToken).assertEqual('canned_at');
      expect(stub.lastRefreshRequest !== null).assertTrue();
      expect(stub.lastRefreshRequest!.refreshToken).assertEqual('rt-1');
      expect(stub.lastRefreshRequest!.scope).assertEqual('read');
    });

    it('getUserInfo returns user info for the given access token', 0, async () => {
      const provider: IOAuth2Provider = makeStub();
      const info: OAuth2UserInfo = await provider.getUserInfo('at-9');
      expect(info.userId).assertEqual('u-1');
      expect(info.userName).assertEqual('stub-user');
    });

    it('revokeToken resolves and records the access token', 0, async () => {
      const stub = makeStub();
      const provider: IOAuth2Provider = stub;
      await provider.revokeToken('at-revoke');
      expect(stub.lastRevokedToken).assertEqual('at-revoke');
    });

    it('validateToken returns the canned positive result', 0, async () => {
      const stub = makeStub();
      const provider: IOAuth2Provider = stub;
      const token: OAuth2Token = { accessToken: 'at-ok', tokenType: 'Bearer' };
      const ok = await provider.validateToken(token);
      expect(ok).assertTrue();
      expect(stub.lastValidatedToken!.accessToken).assertEqual('at-ok');
    });

    it('validateToken returns the canned negative result', 0, async () => {
      const stub = makeStub();
      stub.cannedValidateResult = false;
      const provider: IOAuth2Provider = stub;
      const token: OAuth2Token = { accessToken: 'at-bad', tokenType: 'Bearer' };
      const ok = await provider.validateToken(token);
      expect(ok).assertFalse();
    });

    it('getConfig returns the config supplied at construction', 0, () => {
      const provider: IOAuth2Provider = makeStub();
      const config = provider.getConfig();
      expect(config.clientId).assertEqual('cid');
      expect(config.clientSecret).assertEqual('secret');
      expect(config.tokenEndpoint).assertEqual('https://example.com/token');
      expect(config.redirectUri).assertEqual('keepassho://callback');
    });

    it('setConfig replaces the active config', 0, () => {
      const stub = makeStub();
      const provider: IOAuth2Provider = stub;
      const next = makeConfig();
      next.clientId = 'next-cid';
      provider.setConfig(next);
      expect(provider.getConfig().clientId).assertEqual('next-cid');
      expect(provider.getAuthorizationUrl()).assertEqual('https://example.com/authorize?client_id=next-cid');
      expect(stub.lastSetConfig!.clientId).assertEqual('next-cid');
    });
  });
}
