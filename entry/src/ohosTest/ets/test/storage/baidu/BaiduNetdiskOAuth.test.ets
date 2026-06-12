import { describe, expect, it } from '@ohos/hypium';
import { BaiduNetdiskConfig } from '../../../../../main/ets/storage/baidu/BaiduNetdiskConfig';
import { BaiduNetdiskOAuth2Provider } from '../../../../../main/ets/storage/baidu/BaiduNetdiskOAuth2Provider';
import { BaiduNetdiskClient } from '../../../../../main/ets/storage/baidu/BaiduNetdiskClient';

export default function BaiduNetdiskOAuthTest() {
  describe('BaiduNetdiskOAuthTest', () => {

    it('BaiduNetdiskConfig_should_store_appKey_and_appSecret', 0, () => {
      const config = new BaiduNetdiskConfig();
      config.appKey = 'test_app_key';
      config.appSecret = 'test_app_secret';
      config.redirectUri = 'https://localhost/callback';
      expect(config.appKey).assertEqual('test_app_key');
      expect(config.appSecret).assertEqual('test_app_secret');
      expect(config.redirectUri).assertEqual('https://localhost/callback');
    });

    it('BaiduNetdiskConfig_isConfigured_should_return_false_when_empty', 0, () => {
      const config = new BaiduNetdiskConfig();
      expect(config.isConfigured()).assertFalse();
    });

    it('getAuthorizationUrl_should_contain_app_key_and_scope', 0, () => {
      const config = new BaiduNetdiskConfig();
      config.appKey = 'my_app_key_123';
      config.redirectUri = 'https://localhost/callback';
      const client = new BaiduNetdiskClient(config);
      const url = client.getAuthorizationUrl(config.redirectUri, 'test_state_xyz');
      expect(url.indexOf('my_app_key_123') > 0).assertTrue();
      expect(url.indexOf('response_type=code') > 0).assertTrue();
      expect(url.indexOf('scope=basic') > 0).assertTrue();
      expect(url.indexOf('state=test_state_xyz') > 0).assertTrue();
    });

    it('BaiduNetdiskClient_should_initialize_with_config', 0, () => {
      const config = new BaiduNetdiskConfig();
      config.appKey = 'key123';
      config.appSecret = 'secret456';
      const client = new BaiduNetdiskClient(config);
      expect(client !== null).assertTrue();
    });

  });
}
