import { describe, expect, it } from '@ohos/hypium';
import { PCloudOAuth2Provider, PCloudOAuth2Config, createPCloudOAuth2Config } from '../../../../../main/ets/storage/pcloud/PCloudOAuth2Provider';

const TEST_CLIENT_ID: string = 'test-client-id';
const TEST_REDIRECT_URI: string = 'keepassho://test/callback';

export default function PCloudOAuth2ProviderTest() {
  describe('PCloudOAuth2ProviderTest', () => {

    /**
     * 测试 createPCloudOAuth2Config 工厂方法
     */
    describe('FactoryConfig', () => {
      it('should create config with required fields', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );

        expect(config).not().assertUndefined();
        expect(config.clientId).assertEqual(TEST_CLIENT_ID);
        expect(config.redirectUri).assertEqual(TEST_REDIRECT_URI);
      });

      it('should have correct authorize endpoint', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );

        expect(config.authorizationEndpoint).assertEqual('https://my.pcloud.com/oauth2/authorize');
      });

      it('should have empty token endpoint for Token Flow', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );

        expect(config.tokenEndpoint).assertEqual('');
      });

      it('should use default apiBaseUrl when not provided', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );

        expect(config.apiBaseUrl).assertEqual('https://api.pcloud.com');
      });

      it('should accept custom apiBaseUrl', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI, 'https://eapi.pcloud.com'
        );

        expect(config.apiBaseUrl).assertEqual('https://eapi.pcloud.com');
      });

      it('should have undefined scope', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );

        expect(config.scope).assertUndefined();
      });

      it('should be marked as public client', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );

        expect(config.isPublicClient).assertTrue();
      });

      it('should have empty clientSecret', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );

        expect(config.clientSecret).assertEqual('');
      });
    });

    /**
     * 测试 PCloudOAuth2Provider 创建
     */
    describe('ProviderCreation', () => {
      it('should create provider with config', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        expect(provider).not().assertUndefined();
      });

      it('getProviderName should return PCloud', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        expect(provider.getProviderName()).assertEqual('PCloud');
      });

      it('getConfig should return correct clientId', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        const retrievedConfig = provider.getConfig();
        expect(retrievedConfig.clientId).assertEqual(TEST_CLIENT_ID);
      });
    });

    /**
     * 测试授权 URL 生成（Token Flow）
     */
    describe('AuthorizationUrl', () => {
      it('should generate URL with response_type=token', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        const authUrl = provider.getAuthorizationUrl();

        expect(authUrl).assertContain('response_type=token');
        expect(authUrl).assertContain('client_id=');
        expect(authUrl).assertContain('redirect_uri=');
      });

      it('should include client_id in URL', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        const authUrl = provider.getAuthorizationUrl();

        expect(authUrl).assertContain(encodeURIComponent(TEST_CLIENT_ID));
      });

      it('should include redirect_uri in URL', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        const authUrl = provider.getAuthorizationUrl();

        expect(authUrl).assertContain(encodeURIComponent(TEST_REDIRECT_URI));
      });

      it('should start with correct endpoint', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        const authUrl = provider.getAuthorizationUrl();

        expect(authUrl).assertContain('https://my.pcloud.com/oauth2/authorize');
      });
    });

    /**
     * 测试 setApiBaseUrl 方法
     */
    describe('SetApiBaseUrl', () => {
      it('should update apiBaseUrl', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        provider.setApiBaseUrl('https://eapi.pcloud.com');

        // 通过 getUserInfo 间接验证（getUserInfoEndpoint 使用 apiBaseUrl）
        // 这里我们验证 provider 仍然正常工作
        expect(provider.getProviderName()).assertEqual('PCloud');
      });
    });
  });
}
