import { describe, expect, it } from '@ohos/hypium';
import { OneDrivePageConfig, OneDriveStorageConfig } from '../../../../../main/ets/storage/onedrive/OneDriveConfig';
import { StorageType } from '../../../../../main/ets/storage/StorageType';

export default function OneDriveConfigTest() {
  describe('OneDriveConfigTest', () => {

    describe('OneDriveStorageConfig', () => {
      it('should encrypt tokens and decrypt back to original', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig(
          'access-123', 'refresh-456', Date.now() + 3600000
        );
        expect(cfg.getAccessTokenText()).assertEqual('access-123');
        expect(cfg.getRefreshTokenText()).assertEqual('refresh-456');
      });

      it('should not store plaintext tokens', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig(
          'plain-access', 'plain-refresh', 0
        );
        expect(cfg.accessToken !== 'plain-access').assertTrue();
        expect(cfg.refreshToken !== 'plain-refresh').assertTrue();
      });

      it('should store expiresAt as provided', 0, () => {
        const ts: number = 1800000000000;
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', ts);
        expect(cfg.expiresAt).assertEqual(ts);
      });

      it('should default optional fields to undefined', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', 0);
        expect(cfg.timeout).assertUndefined();
        expect(cfg.tokenType).assertUndefined();
        expect(cfg.scope).assertUndefined();
      });

      it('should accept optional timeout/tokenType/scope', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', 0,
          { timeout: 60000, tokenType: 'Bearer', scope: 'Files.ReadWrite' });
        expect(cfg.timeout).assertEqual(60000);
        expect(cfg.tokenType).assertEqual('Bearer');
        expect(cfg.scope).assertEqual('Files.ReadWrite');
      });

      it('should support unicode token round-trip', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('访问令牌', '刷新令牌', 0);
        expect(cfg.getAccessTokenText()).assertEqual('访问令牌');
        expect(cfg.getRefreshTokenText()).assertEqual('刷新令牌');
      });
    });

    describe('Setters', () => {
      it('setAccessToken should re-encrypt and decrypt back', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', 0);
        cfg.setAccessToken('new-access');
        expect(cfg.getAccessTokenText()).assertEqual('new-access');
      });

      it('setRefreshToken should re-encrypt and decrypt back', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', 0);
        cfg.setRefreshToken('new-refresh');
        expect(cfg.getRefreshTokenText()).assertEqual('new-refresh');
      });

      it('setExpiresAt should update the timestamp', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', 0);
        cfg.setExpiresAt(9999999);
        expect(cfg.expiresAt).assertEqual(9999999);
      });

      it('setAccessToken should produce a different ciphertext than before', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', 0);
        const before: string = cfg.accessToken;
        cfg.setAccessToken('b');
        expect(cfg.accessToken !== before).assertTrue();
      });
    });

    describe('isTokenExpired', () => {
      it('should NOT be expired when expiresAt is 0 (per source: !expiresAt => false)', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', 0);
        expect(cfg.isTokenExpired()).assertFalse();
      });

      it('should be expired when expiresAt is in the past', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', Date.now() - 1000);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should NOT be expired when more than 5 minutes remain', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', Date.now() + 3600000);
        expect(cfg.isTokenExpired()).assertFalse();
      });

      it('should be expired within the 5-minute safety window', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', Date.now() + 60 * 1000);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should be expired just past the 5-minute boundary (strict > in source)', 0, () => {
        const now: number = Date.now();
        // Source: Date.now() > expiresAt - 5min (strict >). At the exact
        // boundary instant the token is still valid; 1ms past it is expired.
        // Fixture shifts the boundary 1ms into the past so the assertion is
        // deterministic regardless of clock progression during the test.
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', now + 5 * 60 * 1000 - 1);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should reflect setExpiresAt changes', 0, () => {
        const cfg: OneDriveStorageConfig = new OneDriveStorageConfig('a', 'r', 0);
        cfg.setExpiresAt(Date.now() + 3600000);
        expect(cfg.isTokenExpired()).assertFalse();
        cfg.setExpiresAt(Date.now() - 1);
        expect(cfg.isTokenExpired()).assertTrue();
      });
    });

    describe('OneDrivePageConfig', () => {
      it('should expose a string title', 0, () => {
        expect(OneDrivePageConfig.title).assertEqual('OneDrive');
      });

      it('should expose pageUrl', 0, () => {
        expect(OneDrivePageConfig.pageUrl).assertEqual('storage/onedrive/OneDrivePage');
      });

      it('should map to ONEDRIVE storage type', 0, () => {
        expect(OneDrivePageConfig.storageType).assertEqual(StorageType.ONEDRIVE);
      });

      it('should expose icon resource', 0, () => {
        expect(OneDrivePageConfig.icon).not().assertUndefined();
      });

      it('should expose selectDesc resource', 0, () => {
        expect(OneDrivePageConfig.selectDesc).not().assertUndefined();
      });

      it('should expose saveDesc resource', 0, () => {
        expect(OneDrivePageConfig.saveDesc).not().assertUndefined();
      });
    });
  });
}
