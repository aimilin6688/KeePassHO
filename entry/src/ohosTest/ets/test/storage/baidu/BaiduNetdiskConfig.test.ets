import { describe, expect, it } from '@ohos/hypium';
import { BaiduNetdiskPageConfig, BaiduNetdiskStorageConfig } from '../../../../../main/ets/storage/baidu/BaiduNetdiskConfig';
import { StorageType } from '../../../../../main/ets/storage/StorageType';

/**
 * 百度网盘存储配置单元测试（离线，SM4 依赖真机 Asset Kit）：
 * 镜像 OneDriveConfig.test.ets 契约 —— 加密往返、密文不含明文、
 * isTokenExpired 语义（5 分钟提前窗口 + 严格 >）、PageConfig 字段。
 */
export default function BaiduNetdiskConfigTest() {
  describe('BaiduNetdiskConfigTest', () => {

    describe('BaiduNetdiskStorageConfig', () => {
      it('should encrypt tokens and decrypt back to original', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig(
          'access-123', 'refresh-456', Date.now() + 3600000
        );
        expect(cfg.getAccessTokenText()).assertEqual('access-123');
        expect(cfg.getRefreshTokenText()).assertEqual('refresh-456');
      });

      it('should not store plaintext tokens', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig(
          'plain-access', 'plain-refresh', 0
        );
        expect(cfg.accessToken !== 'plain-access').assertTrue();
        expect(cfg.refreshToken !== 'plain-refresh').assertTrue();
      });

      it('should store expiresAt as provided', 0, () => {
        const ts: number = 1800000000000;
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', ts);
        expect(cfg.expiresAt).assertEqual(ts);
      });

      it('should default optional fields to undefined', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', 0);
        expect(cfg.timeout).assertUndefined();
        expect(cfg.tokenType).assertUndefined();
        expect(cfg.scope).assertUndefined();
      });

      it('should accept optional timeout/tokenType/scope', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', 0,
          { timeout: 60000, tokenType: 'Bearer', scope: 'basic_netdisk' });
        expect(cfg.timeout).assertEqual(60000);
        expect(cfg.tokenType).assertEqual('Bearer');
        expect(cfg.scope).assertEqual('basic_netdisk');
      });

      it('should support unicode token round-trip', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('访问令牌', '刷新令牌', 0);
        expect(cfg.getAccessTokenText()).assertEqual('访问令牌');
        expect(cfg.getRefreshTokenText()).assertEqual('刷新令牌');
      });

      it('should keep empty token as empty string', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('', '', 0);
        expect(cfg.accessToken).assertEqual('');
        expect(cfg.getAccessTokenText()).assertEqual('');
        expect(cfg.getRefreshTokenText()).assertEqual('');
      });
    });

    describe('Setters', () => {
      it('setAccessToken should re-encrypt and decrypt back', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', 0);
        cfg.setAccessToken('new-access');
        expect(cfg.getAccessTokenText()).assertEqual('new-access');
      });

      it('setRefreshToken should re-encrypt and decrypt back', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', 0);
        cfg.setRefreshToken('new-refresh');
        expect(cfg.getRefreshTokenText()).assertEqual('new-refresh');
      });

      it('setExpiresAt should update the timestamp', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', 0);
        cfg.setExpiresAt(9999999);
        expect(cfg.expiresAt).assertEqual(9999999);
      });

      it('setAccessToken should produce a different ciphertext than before', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', 0);
        const before: string = cfg.accessToken;
        cfg.setAccessToken('b');
        expect(cfg.accessToken !== before).assertTrue();
      });
    });

    describe('isTokenExpired', () => {
      it('should NOT be expired when expiresAt is 0 (per source: !expiresAt => false)', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', 0);
        expect(cfg.isTokenExpired()).assertFalse();
      });

      it('should be expired when expiresAt is in the past', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', Date.now() - 1000);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should NOT be expired when more than 5 minutes remain', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', Date.now() + 3600000);
        expect(cfg.isTokenExpired()).assertFalse();
      });

      it('should be expired within the 5-minute safety window', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', Date.now() + 60 * 1000);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should be expired just past the 5-minute boundary (strict > in source)', 0, () => {
        const now: number = Date.now();
        // Source: Date.now() > expiresAt - 5min (strict >). Boundary 前移 1ms 保证确定性。
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', now + 5 * 60 * 1000 - 1);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should be expired for negative expiresAt', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', -1);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should reflect setExpiresAt changes', 0, () => {
        const cfg: BaiduNetdiskStorageConfig = new BaiduNetdiskStorageConfig('a', 'r', 0);
        cfg.setExpiresAt(Date.now() + 3600000);
        expect(cfg.isTokenExpired()).assertFalse();
        cfg.setExpiresAt(Date.now() - 1);
        expect(cfg.isTokenExpired()).assertTrue();
      });
    });

    describe('BaiduNetdiskPageConfig', () => {
      it('should expose a string title', 0, () => {
        expect(BaiduNetdiskPageConfig.title).assertEqual('百度网盘');
      });

      it('should expose pageUrl', 0, () => {
        expect(BaiduNetdiskPageConfig.pageUrl).assertEqual('storage/baidu/BaiduNetdiskPage');
      });

      it('should map to BAIDU_NETDISK storage type', 0, () => {
        expect(BaiduNetdiskPageConfig.storageType).assertEqual(StorageType.BAIDU_NETDISK);
      });

      it('should expose icon resource', 0, () => {
        expect(BaiduNetdiskPageConfig.icon).not().assertUndefined();
      });

      it('should expose selectDesc resource', 0, () => {
        expect(BaiduNetdiskPageConfig.selectDesc).not().assertUndefined();
      });

      it('should expose saveDesc resource', 0, () => {
        expect(BaiduNetdiskPageConfig.saveDesc).not().assertUndefined();
      });

      it('should expose childDb port (baidu scheme)', 0, () => {
        expect(BaiduNetdiskPageConfig.childDb).not().assertUndefined();
      });
    });
  });
}
