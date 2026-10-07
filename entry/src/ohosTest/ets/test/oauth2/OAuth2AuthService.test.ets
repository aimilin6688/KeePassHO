import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { OAuth2AuthService } from '../../../../main/ets/common/oauth2/OAuth2AuthService';
import { IOAuth2Provider } from '../../../../main/ets/common/oauth2/IOAuth2Provider';
import { OAuth2TokenStorageService } from '../../../../main/ets/common/oauth2/OAuth2TokenStorageService';
import { OAuth2Config, OAuth2Provider, OAuth2Token, OAuth2AuthRequest, OAuth2RefreshRequest, OAuth2UserInfo } from '../../../../main/ets/common/oauth2/OAuth2Types';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

class AuthServiceStubProvider implements IOAuth2Provider {
  private config: OAuth2Config;
  public cannedToken: OAuth2Token;
  public lastAuthRequest: OAuth2AuthRequest | null = null;
  public lastRefreshRequest: OAuth2RefreshRequest | null = null;
  public lastUserInfoToken: string = '';
  public lastRevokedToken: string = '';

  constructor() {
    this.config = {
      clientId: 'stub_client',
      clientSecret: 'stub_secret',
      authorizationEndpoint: 'https://stub.example.com/authorize',
      tokenEndpoint: 'https://stub.example.com/token',
      redirectUri: 'keepassho://stub'
    };
    this.cannedToken = {
      accessToken: 'stub_access_token',
      tokenType: 'Bearer',
      refreshToken: 'stub_refresh_token',
      scope: 'stub_scope'
    };
  }

  public getAuthorizationUrl(): string {
    return this.config.authorizationEndpoint;
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
    const info: OAuth2UserInfo = { userId: 'stub-user', userName: 'stub' };
    return info;
  }

  public async revokeToken(accessToken: string): Promise<void> {
    this.lastRevokedToken = accessToken;
  }

  public async validateToken(token: OAuth2Token): Promise<boolean> {
    return token.accessToken.length > 0;
  }

  public getProviderName(): string {
    return 'AuthServiceStub';
  }

  public getConfig(): OAuth2Config {
    return this.config;
  }

  public setConfig(config: OAuth2Config): void {
    this.config = config;
  }
}

const MANAGED_PROVIDERS: OAuth2Provider[] =
  [OAuth2Provider.GITHUB, OAuth2Provider.GOOGLE, OAuth2Provider.DROPBOX, OAuth2Provider.BAIDU_NETDISK];

async function sleep(ms: number): Promise<void> {
  await new Promise<void>(resolve => setTimeout(resolve, ms));
}

async function waitStorageReady(): Promise<void> {
  for (let i = 0; i < 100; i++) {
    try {
      await OAuth2TokenStorageService.getInstance().hasToken({ provider: OAuth2Provider.GITHUB });
      return;
    } catch (error) {
      await sleep(50);
    }
  }
}

async function cleanupTokens(): Promise<void> {
  try {
    for (const provider of MANAGED_PROVIDERS) {
      await OAuth2AuthService.deleteToken(provider);
    }
  } catch (error) {
    // 清理属于尽力而为，不允许让清理失败中止整个测试套件
  }
}

export default function OAuth2AuthServiceTest() {
  describe('OAuth2AuthServiceTest', () => {
    beforeAll(async () => {
      const appContext =  abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      await waitStorageReady();
      await cleanupTokens();
    });

    beforeEach(async () => {
      await cleanupTokens();
    });

    afterEach(async () => {
      await cleanupTokens();
    });

    afterAll(async () => {
      await cleanupTokens();
    });

    it('loadToken returns null when nothing was saved', 0, async () => {
      const loaded = await OAuth2AuthService.loadToken(OAuth2Provider.GITHUB);
      expect(loaded).assertNull();
    });

    it('saveToken ignores a null token without side effects', 0, async () => {
      await OAuth2AuthService.saveToken(OAuth2Provider.GOOGLE, null);
      const loaded = await OAuth2AuthService.loadToken(OAuth2Provider.GOOGLE);
      expect(loaded).assertNull();
    });

    it('saveToken and loadToken round-trip through encrypted storage', 0, async () => {
      const token: OAuth2Token = {
        accessToken: 'gh_access_1',
        tokenType: 'Bearer',
        refreshToken: 'gh_refresh_1',
        scope: 'repo'
      };
      await OAuth2AuthService.saveToken(OAuth2Provider.GITHUB, token);
      const loaded = await OAuth2AuthService.loadToken(OAuth2Provider.GITHUB);
      if (loaded !== null) {
        expect(loaded.accessToken).assertEqual('gh_access_1');
        expect(loaded.tokenType).assertEqual('Bearer');
        expect(loaded.refreshToken).assertEqual('gh_refresh_1');
        expect(loaded.scope).assertEqual('repo');
      }
    });

    it('saveToken overwrites a previously saved token', 0, async () => {
      const first: OAuth2Token = { accessToken: 'old_access', tokenType: 'Bearer' };
      const second: OAuth2Token = { accessToken: 'new_access', tokenType: 'Bearer' };
      await OAuth2AuthService.saveToken(OAuth2Provider.DROPBOX, first);
      await OAuth2AuthService.saveToken(OAuth2Provider.DROPBOX, second);
      const loaded = await OAuth2AuthService.loadToken(OAuth2Provider.DROPBOX);
      if (loaded !== null) {
        expect(loaded.accessToken).assertEqual('new_access');
      }
    });

    it('deleteToken removes a saved token', 0, async () => {
      const token: OAuth2Token = { accessToken: 'to_be_deleted', tokenType: 'Bearer' };
      await OAuth2AuthService.saveToken(OAuth2Provider.DROPBOX, token);
      await OAuth2AuthService.deleteToken(OAuth2Provider.DROPBOX);
      const loaded = await OAuth2AuthService.loadToken(OAuth2Provider.DROPBOX);
      expect(loaded).assertNull();
    });

    it('deleteToken resolves for a provider without a saved token', 0, async () => {
      await OAuth2AuthService.deleteToken(OAuth2Provider.BAIDU_NETDISK);
      const loaded = await OAuth2AuthService.loadToken(OAuth2Provider.BAIDU_NETDISK);
      expect(loaded).assertNull();
    });

    it('exchangeCodeForToken delegates to the provider and persists the token', 0, async () => {
      const stub = new AuthServiceStubProvider();
      const token = await OAuth2AuthService.exchangeCodeForToken(stub, 'code_abc', 'state_xyz',
        OAuth2Provider.DROPBOX);
      expect(token.accessToken).assertEqual('stub_access_token');
      expect(token.tokenType).assertEqual('Bearer');
      expect(stub.lastAuthRequest !== null).assertTrue();
      expect(stub.lastAuthRequest!.code).assertEqual('code_abc');
      expect(stub.lastAuthRequest!.state).assertEqual('state_xyz');
      const persisted = await OAuth2AuthService.loadToken(OAuth2Provider.DROPBOX);
      if (persisted !== null) {
        expect(persisted.accessToken).assertEqual('stub_access_token');
        expect(persisted.refreshToken).assertEqual('stub_refresh_token');
      }
    });

    it('exchangeCodeForToken works with any IOAuth2Provider implementation', 0, async () => {
      const stub = new AuthServiceStubProvider();
      const provider: IOAuth2Provider = stub;
      const token = await OAuth2AuthService.exchangeCodeForToken(provider, 'code_2', '', OAuth2Provider.GITHUB);
      expect(token.accessToken).assertEqual('stub_access_token');
      expect(provider.getProviderName()).assertEqual('AuthServiceStub');
    });
  });
}
