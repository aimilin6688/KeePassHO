import { describe, expect, it } from '@ohos/hypium';
import { BaiduNetdiskConfig } from '../../../../../main/ets/storage/baidunetdisk/BaiduNetdiskConfig';
import { BaiduNetdiskOAuth2Provider } from '../../../../../main/ets/storage/baidunetdisk/BaiduNetdiskOAuth2Provider';
import { BaiduNetdiskClient } from '../../../../../main/ets/storage/baidunetdisk/BaiduNetdiskClient';

export default function BaiduNetdiskAuthTest() {
  describe('BaiduNetdiskAuthTest', () => {

    it('getAuthorizationUrl_should_contain_app_key', 0, () => {
      const config: BaiduNetdiskConfig = new BaiduNetdiskConfig();
      config.appKey = 'test_key_123';
      config.redirectUri = 'https://localhost:8080/callback';
      const client: BaiduNetdiskClient = new BaiduNetdiskClient(config);
      const url: string = client.getAuthorizationUrl(config.redirectUri, 'test_state');
      expect(url.indexOf('test_key_123') >= 0).assertTrue();
      expect(url.indexOf('response_type=code') >= 0).assertTrue();
      expect(url.indexOf('scope=basic') >= 0).assertTrue();
    });

    it('BaiduNetdiskConfig_should_store_fields', 0, () => {
      const config: BaiduNetdiskConfig = new BaiduNetdiskConfig();
      config.appKey = 'key1';
      config.appSecret = 'secret1';
      config.redirectUri = 'https://example.com/callback';
      config.rootPath = '/apps/test/';
      expect(config.appKey === 'key1').assertTrue();
      expect(config.appSecret === 'secret1').assertTrue();
      expect(config.redirectUri === 'https://example.com/callback').assertTrue();
      expect(config.rootPath === '/apps/test/').assertTrue();
    });

    it('BaiduNetdiskConfig_isConfigured_should_return_false_when_no_appKey', 0, async () => {
      const config: BaiduNetdiskConfig = new BaiduNetdiskConfig();
      config.appKey = '';
      const result: boolean = await config.isConfigured();
      expect(result === false).assertTrue();
    });

    it('extractAuthorizationCode_should_return_code', 0, () => {
      const config: BaiduNetdiskConfig = new BaiduNetdiskConfig();
      const provider: BaiduNetdiskOAuth2Provider = new BaiduNetdiskOAuth2Provider(config);
      const url: string = 'https://localhost:8080/callback?code=test_code_xyz&state=abc';
      const code: string = provider.extractAuthorizationCode(url);
      expect(code === 'test_code_xyz').assertTrue();
    });

    it('extractAuthorizationCode_should_return_empty_when_no_query', 0, () => {
      const config: BaiduNetdiskConfig = new BaiduNetdiskConfig();
      const provider: BaiduNetdiskOAuth2Provider = new BaiduNetdiskOAuth2Provider(config);
      const code: string = provider.extractAuthorizationCode('https://localhost:8080/callback');
      expect(code === '').assertTrue();
    });
  });
}
