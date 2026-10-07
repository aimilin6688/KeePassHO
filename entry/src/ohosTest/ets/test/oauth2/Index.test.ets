import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  OAuth2Provider,
  OAuth2Token,
  OAuth2Config,
  OAuth2AuthRequest,
  OAuth2RefreshRequest,
  OAuth2Response,
  OAuth2AuthResponse,
  OAuth2UserInfo,
  OAuth2StorageConfig,
  IOAuth2Provider,
  OAuth2Error,
  OAuth2ErrorCodes,
  BaseOAuth2Provider,
  OAuth2TokenStorageService,
  OAuth2TokenStorageConfig,
  OAuth2AuthService
} from '../../../../main/ets/common/oauth2/index';

class IndexBarrelProvider extends BaseOAuth2Provider {
  public async getUserInfo(accessToken: string): Promise<OAuth2UserInfo> {
    const info: OAuth2UserInfo = { userId: accessToken, userName: 'barrel-user' };
    return info;
  }

  public getProviderName(): string {
    return 'IndexBarrel';
  }

  protected getUserInfoEndpoint(): string {
    return 'https://example.com/userinfo';
  }
}

class IndexInterfaceStub implements IOAuth2Provider {
  public cannedToken: OAuth2Token;

  constructor() {
    this.cannedToken = { accessToken: 'idx_at', tokenType: 'Bearer' };
  }

  public getAuthorizationUrl(): string {
    return 'https://example.com/authorize';
  }

  public async authorize(authRequest: OAuth2AuthRequest): Promise<OAuth2Token> {
    return this.cannedToken;
  }

  public async refreshToken(refreshRequest: OAuth2RefreshRequest): Promise<OAuth2Token> {
    return this.cannedToken;
  }

  public async getUserInfo(accessToken: string): Promise<OAuth2UserInfo> {
    const info: OAuth2UserInfo = { userId: 'u', userName: 'n' };
    return info;
  }

  public async revokeToken(accessToken: string): Promise<void> {
  }

  public async validateToken(token: OAuth2Token): Promise<boolean> {
    return true;
  }

  public getProviderName(): string {
    return 'IndexStub';
  }

  public getConfig(): OAuth2Config {
    return {
      clientId: 'cid',
      clientSecret: 'cst',
      authorizationEndpoint: 'https://example.com/authorize',
      tokenEndpoint: 'https://example.com/token',
      redirectUri: 'keepassho://callback'
    };
  }

  public setConfig(config: OAuth2Config): void {
  }
}

export default function OAuth2IndexTest() {
  describe('OAuth2IndexTest', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('re-exports the OAuth2Provider and OAuth2ErrorCodes enums', 0, () => {
      expect(OAuth2Provider.GITHUB).assertEqual('GITHUB');
      expect(OAuth2Provider.PCLOUD).assertEqual('PCLOUD');
      expect(OAuth2ErrorCodes.CONFIG_ERROR).assertEqual('CONFIG_ERROR');
      expect(OAuth2ErrorCodes.NETWORK_ERROR).assertEqual('NETWORK_ERROR');
      expect(OAuth2ErrorCodes.ACCESS_DENIED).assertEqual('ACCESS_DENIED');
    });

    it('re-exports the OAuth2Error class', 0, () => {
      const err = new OAuth2Error(OAuth2ErrorCodes.TOKEN_EXPIRED, 'too old');
      expect(err.name).assertEqual('OAuth2Error');
      expect(err.code).assertEqual(OAuth2ErrorCodes.TOKEN_EXPIRED);
      expect(err.message).assertContain('too old');
    });

    it('re-exports the BaseOAuth2Provider abstract class', 0, () => {
      const config: OAuth2Config = {
        clientId: 'barrel_client',
        clientSecret: 'barrel_secret',
        authorizationEndpoint: 'https://example.com/authorize',
        tokenEndpoint: 'https://example.com/token',
        redirectUri: 'keepassho://callback'
      };
      const provider = new IndexBarrelProvider(config);
      expect(provider.getProviderName()).assertEqual('IndexBarrel');
      expect(provider.getAuthorizationUrl()).assertContain('response_type=code');
      expect(provider.getConfig().clientId).assertEqual('barrel_client');
    });

    it('re-exports the OAuth2TokenStorageService singleton', 0, () => {
      const a = OAuth2TokenStorageService.getInstance();
      const b = OAuth2TokenStorageService.getInstance();
      expect(a === b).assertTrue();
    });

    it('re-exports the OAuth2AuthService static facade', 0, async () => {
      expect(typeof OAuth2AuthService.loadToken).assertEqual('function');
      expect(typeof OAuth2AuthService.saveToken).assertEqual('function');
      expect(typeof OAuth2AuthService.deleteToken).assertEqual('function');
      expect(typeof OAuth2AuthService.exchangeCodeForToken).assertEqual('function');
      expect(await OAuth2AuthService.loadToken(OAuth2Provider.BAIDU_NETDISK)).assertNull();
    });

    it('re-exports the IOAuth2Provider interface contract', 0, async () => {
      const provider: IOAuth2Provider = new IndexInterfaceStub();
      expect(provider.getProviderName()).assertEqual('IndexStub');
      const token = await provider.authorize({ code: 'c', state: 's' });
      expect(token.accessToken).assertEqual('idx_at');
    });

    it('re-exports all OAuth2 type definitions', 0, () => {
      const token: OAuth2Token = { accessToken: 'at', tokenType: 'Bearer' };
      const config: OAuth2Config = {
        clientId: 'cid',
        clientSecret: 'cst',
        authorizationEndpoint: 'https://a',
        tokenEndpoint: 'https://t',
        redirectUri: 'keepassho://cb'
      };
      const authRequest: OAuth2AuthRequest = { code: 'c', state: 's' };
      const refreshRequest: OAuth2RefreshRequest = { refreshToken: 'rt' };
      const response: OAuth2Response = { success: true };
      const authResponse: OAuth2AuthResponse = { success: true, token: token };
      const userInfo: OAuth2UserInfo = { userId: 'u', userName: 'n' };
      const storageConfig: OAuth2StorageConfig = { provider: OAuth2Provider.DROPBOX, oauth2Config: config };
      const tokenStorageConfig: OAuth2TokenStorageConfig = { provider: OAuth2Provider.GITHUB };
      expect(token.accessToken).assertEqual('at');
      expect(config.clientId).assertEqual('cid');
      expect(authRequest.code).assertEqual('c');
      expect(refreshRequest.refreshToken).assertEqual('rt');
      expect(response.success).assertTrue();
      expect(authResponse.token!.accessToken).assertEqual('at');
      expect(userInfo.userName).assertEqual('n');
      expect(storageConfig.provider).assertEqual(OAuth2Provider.DROPBOX);
      expect(tokenStorageConfig.provider).assertEqual(OAuth2Provider.GITHUB);
    });
  });
}
