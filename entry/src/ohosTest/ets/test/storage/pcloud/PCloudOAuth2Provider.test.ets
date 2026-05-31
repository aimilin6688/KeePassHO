import { describe, expect, it } from '@ohos/hypium';
import { PCloudOAuth2Provider, PCloudOAuth2Config, createPCloudOAuth2Config } from '../../../../../main/ets/storage/pcloud/PCloudOAuth2Provider';

const TEST_CLIENT_ID: string = 'test-client-id';
const TEST_CLIENT_SECRET: string = 'test-client-secret';
const TEST_REDIRECT_URI: string = 'keepassho://test/callback';

export default function PCloudOAuth2ProviderTest() {
  describe('PCloudOAuth2ProviderTest', () => {

    /**
     * 测试 createPCloudOAuth2Config 工厂方法
     */
    describe('FactoryConfig', () => {
      it('should create config with required fields', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_CLIENT_SECRET, TEST_REDIRECT_URI
        );

        expect(config).not().assertUndefined();
        expect(config.clientId).assertEqual(TEST_CLIENT_ID);
        expect(config.clientSecret).assertEqual(TEST_CLIENT_SECRET);
        expect(config.redirectUri).assertEqual(TEST_REDIRECT_URI);
      });

      it('should have correct authorize endpoint', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_CLIENT_SECRET, TEST_REDIRECT_URI
        );

        expect(config.authorizationEndpoint).assertEqual('https://my.pcloud.com/oauth2/authorize');
      });

      it('should have correct token endpoint', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_CLIENT_SECRET, TEST_REDIRECT_URI
        );

        expect(config.tokenEndpoint).assertEqual('https://api.pcloud.com/oauth2_token');
      });

      it('should use default apiBaseUrl when not provided', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_CLIENT_SECRET, TEST_REDIRECT_URI
        );

        expect(config.apiBaseUrl).assertEqual('https://api.pcloud.com');
      });

      it('should accept custom apiBaseUrl', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_CLIENT_SECRET, TEST_REDIRECT_URI, 'https://eapi.pcloud.com'
        );

        expect(config.apiBaseUrl).assertEqual('https://eapi.pcloud.com');
      });

      it('should have undefined scope', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_CLIENT_SECRET, TEST_REDIRECT_URI
        );

        expect(config.scope).assertUndefined();
      });
    });

    /**
     * 测试 PCloudOAuth2Provider 创建
     */
    describe('ProviderCreation', () => {
      it('should create provider with config', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_CLIENT_SECRET, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        expect(provider).not().assertUndefined();
      });

      it('getProviderName should return PCloud', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_CLIENT_SECRET, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        expect(provider.getProviderName()).assertEqual('PCloud');
      });

      it('getConfig should return correct clientId', 0, () => {
        const config: PCloudOAuth2Config = createPCloudOAuth2Config(
          TEST_CLIENT_ID, TEST_CLIENT_SECRET, TEST_REDIRECT_URI
        );
        const provider: PCloudOAuth2Provider = new PCloudOAuth2Provider(config);

        const retrievedConfig = provider.getConfig();
        expect(retrievedConfig.clientId).assertEqual(TEST_CLIENT_ID);
      });
    });
  });
}
