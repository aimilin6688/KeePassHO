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
  OAuth2StorageConfig
} from '../../../../main/ets/common/oauth2/OAuth2Types';

export default function OAuth2TypesTest() {
  describe('OAuth2TypesTest', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    describe('OAuth2ProviderEnum', () => {
      it('exposes all provider values', 0, () => {
        expect(OAuth2Provider.GITHUB).assertEqual('GITHUB');
        expect(OAuth2Provider.GOOGLE).assertEqual('GOOGLE');
        expect(OAuth2Provider.ONEDRIVE).assertEqual('ONEDRIVE');
        expect(OAuth2Provider.DROPBOX).assertEqual('DROPBOX');
        expect(OAuth2Provider.PCLOUD).assertEqual('PCLOUD');
        expect(OAuth2Provider.HUAWEI_DRIVE).assertEqual('HUAWEI_DRIVE');
        expect(OAuth2Provider.BAIDU_NETDISK).assertEqual('BAIDU_NETDISK');
      });

      it('supports lowercase conversion used for storage keys', 0, () => {
        expect(OAuth2Provider.GITHUB.toLowerCase()).assertEqual('github');
        expect(OAuth2Provider.ONEDRIVE.toLowerCase()).assertEqual('onedrive');
        expect(OAuth2Provider.PCLOUD.toLowerCase()).assertEqual('pcloud');
        expect(OAuth2Provider.HUAWEI_DRIVE.toLowerCase()).assertEqual('huawei_drive');
        expect(OAuth2Provider.BAIDU_NETDISK.toLowerCase()).assertEqual('baidu_netdisk');
      });
    });

    describe('OAuth2Token', () => {
      it('constructs with required fields only', 0, () => {
        const token: OAuth2Token = {
          accessToken: 'at-1',
          tokenType: 'Bearer'
        };
        expect(token.accessToken).assertEqual('at-1');
        expect(token.tokenType).assertEqual('Bearer');
        expect(token.refreshToken).assertUndefined();
        expect(token.expiresAt).assertUndefined();
        expect(token.scope).assertUndefined();
        expect(token.extraParams).assertUndefined();
      });

      it('constructs with all optional fields', 0, () => {
        const extras: Record<string, string> = {};
        extras['region'] = 'cn-north-4';
        const token: OAuth2Token = {
          accessToken: 'at-2',
          tokenType: 'bearer',
          refreshToken: 'rt-2',
          expiresAt: 1700000000000,
          scope: 'drive.read',
          extraParams: extras
        };
        expect(token.refreshToken).assertEqual('rt-2');
        expect(token.expiresAt).assertEqual(1700000000000);
        expect(token.scope).assertEqual('drive.read');
        expect(token.extraParams!['region']).assertEqual('cn-north-4');
      });
    });

    describe('OAuth2Config', () => {
      it('constructs with required fields only', 0, () => {
        const config: OAuth2Config = {
          clientId: 'cid',
          clientSecret: 'cst',
          authorizationEndpoint: 'https://example.com/authorize',
          tokenEndpoint: 'https://example.com/token',
          redirectUri: 'keepassho://callback'
        };
        expect(config.clientId).assertEqual('cid');
        expect(config.clientSecret).assertEqual('cst');
        expect(config.authorizationEndpoint).assertEqual('https://example.com/authorize');
        expect(config.tokenEndpoint).assertEqual('https://example.com/token');
        expect(config.redirectUri).assertEqual('keepassho://callback');
        expect(config.scope).assertUndefined();
        expect(config.state).assertUndefined();
        expect(config.authExtraParams).assertUndefined();
        expect(config.isPublicClient).assertUndefined();
      });

      it('constructs with all optional fields', 0, () => {
        const extras: Record<string, string> = {};
        extras['access_type'] = 'offline';
        const config: OAuth2Config = {
          clientId: 'cid2',
          clientSecret: '',
          authorizationEndpoint: 'https://example.com/authorize2',
          tokenEndpoint: 'https://example.com/token2',
          redirectUri: 'keepassho://callback2',
          scope: 'read write',
          state: 'csrf-state',
          authExtraParams: extras,
          isPublicClient: true
        };
        expect(config.scope).assertEqual('read write');
        expect(config.state).assertEqual('csrf-state');
        expect(config.authExtraParams!['access_type']).assertEqual('offline');
        expect(config.isPublicClient).assertTrue();
      });
    });

    describe('RequestTypes', () => {
      it('constructs OAuth2AuthRequest', 0, () => {
        const req: OAuth2AuthRequest = { code: 'abc', state: 'st' };
        expect(req.code).assertEqual('abc');
        expect(req.state).assertEqual('st');
      });

      it('constructs OAuth2RefreshRequest with and without scope', 0, () => {
        const req: OAuth2RefreshRequest = { refreshToken: 'rt' };
        expect(req.refreshToken).assertEqual('rt');
        expect(req.scope).assertUndefined();
        const req2: OAuth2RefreshRequest = { refreshToken: 'rt2', scope: 's' };
        expect(req2.refreshToken).assertEqual('rt2');
        expect(req2.scope).assertEqual('s');
      });
    });

    describe('ResponseTypes', () => {
      it('constructs a failed OAuth2Response', 0, () => {
        const resp: OAuth2Response = { success: false, error: 'invalid_grant', errorDescription: 'bad code' };
        expect(resp.success).assertFalse();
        expect(resp.error).assertEqual('invalid_grant');
        expect(resp.errorDescription).assertEqual('bad code');
      });

      it('constructs a successful OAuth2Response without error fields', 0, () => {
        const resp: OAuth2Response = { success: true };
        expect(resp.success).assertTrue();
        expect(resp.error).assertUndefined();
        expect(resp.errorDescription).assertUndefined();
      });

      it('constructs OAuth2AuthResponse with a token', 0, () => {
        const token: OAuth2Token = { accessToken: 'at', tokenType: 'Bearer' };
        const resp: OAuth2AuthResponse = { success: true, token: token };
        expect(resp.success).assertTrue();
        expect(resp.token!.accessToken).assertEqual('at');
        expect(resp.error).assertUndefined();
      });

      it('constructs OAuth2AuthResponse without a token', 0, () => {
        const resp: OAuth2AuthResponse = { success: false, error: 'e' };
        expect(resp.success).assertFalse();
        expect(resp.token).assertUndefined();
      });
    });

    describe('UserInfoAndStorageConfig', () => {
      it('constructs OAuth2UserInfo with required fields only', 0, () => {
        const info: OAuth2UserInfo = { userId: 'u1', userName: 'alice' };
        expect(info.userId).assertEqual('u1');
        expect(info.userName).assertEqual('alice');
        expect(info.email).assertUndefined();
        expect(info.avatarUrl).assertUndefined();
        expect(info.extraInfo).assertUndefined();
      });

      it('constructs OAuth2UserInfo with all optional fields', 0, () => {
        const extra: Record<string, Object> = {};
        extra['plan'] = 'pro';
        const info: OAuth2UserInfo = {
          userId: 'u2',
          userName: 'bob',
          email: 'bob@example.com',
          avatarUrl: 'https://example.com/a.png',
          extraInfo: extra
        };
        expect(info.email).assertEqual('bob@example.com');
        expect(info.avatarUrl).assertEqual('https://example.com/a.png');
        expect(info.extraInfo!['plan']).assertEqual('pro');
      });

      it('constructs OAuth2StorageConfig', 0, () => {
        const config: OAuth2Config = {
          clientId: 'cid',
          clientSecret: 'cst',
          authorizationEndpoint: 'https://example.com/authorize',
          tokenEndpoint: 'https://example.com/token',
          redirectUri: 'keepassho://callback'
        };
        const storageConfig: OAuth2StorageConfig = { provider: OAuth2Provider.ONEDRIVE, oauth2Config: config };
        expect(storageConfig.provider).assertEqual(OAuth2Provider.ONEDRIVE);
        expect(storageConfig.oauth2Config.clientId).assertEqual('cid');
        expect(storageConfig.oauth2Config.redirectUri).assertEqual('keepassho://callback');
      });
    });
  });
}
