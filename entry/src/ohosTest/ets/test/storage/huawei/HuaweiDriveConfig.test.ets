import { describe, expect, it } from '@ohos/hypium';
import {
  HuaweiDrivePageConfig,
  HuaweiDriveScope,
  HuaweiDriveStorageConfig
} from '../../../../../main/ets/storage/huawei/HuaweiDriveConfig';
import { StorageType } from '../../../../../main/ets/storage/StorageType';

export default function HuaweiDriveConfigTest() {
  describe('HuaweiDriveConfigTest', () => {

    describe('HuaweiDriveStorageConfig', () => {
      it('should encrypt tokens and decrypt back to original', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig(
          'access-abc', 'refresh-def', Date.now() + 3600000
        );
        expect(cfg.getAccessTokenText()).assertEqual('access-abc');
        expect(cfg.getRefreshTokenText()).assertEqual('refresh-def');
      });

      it('should not store plaintext tokens', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('p-access', 'p-refresh', 0);
        expect(cfg.accessToken !== 'p-access').assertTrue();
        expect(cfg.refreshToken !== 'p-refresh').assertTrue();
      });

      it('should store expiresAt as provided', 0, () => {
        const ts: number = 1800000000000;
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', ts);
        expect(cfg.expiresAt).assertEqual(ts);
      });

      it('should default optional fields to undefined', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', 0);
        expect(cfg.timeout).assertUndefined();
        expect(cfg.tokenType).assertUndefined();
        expect(cfg.scope).assertUndefined();
      });

      it('should accept optional timeout/tokenType/scope', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', 0,
          { timeout: 45000, tokenType: 'Bearer', scope: 'drive.file' });
        expect(cfg.timeout).assertEqual(45000);
        expect(cfg.tokenType).assertEqual('Bearer');
        expect(cfg.scope).assertEqual('drive.file');
      });

      it('should support unicode token round-trip', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('令牌', '刷新', 0);
        expect(cfg.getAccessTokenText()).assertEqual('令牌');
        expect(cfg.getRefreshTokenText()).assertEqual('刷新');
      });
    });

    describe('Setters', () => {
      it('setAccessToken should re-encrypt and decrypt back', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', 0);
        cfg.setAccessToken('new-access');
        expect(cfg.getAccessTokenText()).assertEqual('new-access');
      });

      it('setRefreshToken should re-encrypt and decrypt back', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', 0);
        cfg.setRefreshToken('new-refresh');
        expect(cfg.getRefreshTokenText()).assertEqual('new-refresh');
      });

      it('setExpiresAt should update the timestamp', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', 0);
        cfg.setExpiresAt(123456);
        expect(cfg.expiresAt).assertEqual(123456);
      });

      it('setRefreshToken should produce a different ciphertext', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', 0);
        const before: string = cfg.refreshToken;
        cfg.setRefreshToken('changed');
        expect(cfg.refreshToken !== before).assertTrue();
      });
    });

    describe('isTokenExpired', () => {
      // 与 OneDrive 不同：HuaweiDrive expiresAt=0 视为已过期（保守策略触发刷新）
      it('should be expired when expiresAt is 0 (conservative)', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', 0);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should be expired when expiresAt is in the past', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', Date.now() - 1000);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should NOT be expired when more than 5 minutes remain', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', Date.now() + 3600000);
        expect(cfg.isTokenExpired()).assertFalse();
      });

      it('should be expired within the 5-minute safety window', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', Date.now() + 60 * 1000);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should be expired just past the 5-minute boundary (strict > in source)', 0, () => {
        const now: number = Date.now();
        // Source: Date.now() > expiresAt - 5min (strict >). At the exact
        // boundary instant the token is still valid; 1ms past it is expired.
        // Fixture shifts the boundary 1ms into the past so the assertion is
        // deterministic regardless of clock progression during the test.
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', now + 5 * 60 * 1000 - 1);
        expect(cfg.isTokenExpired()).assertTrue();
      });

      it('should reflect setExpiresAt changes', 0, () => {
        const cfg: HuaweiDriveStorageConfig = new HuaweiDriveStorageConfig('a', 'r', 0);
        expect(cfg.isTokenExpired()).assertTrue();
        cfg.setExpiresAt(Date.now() + 3600000);
        expect(cfg.isTokenExpired()).assertFalse();
        cfg.setExpiresAt(Date.now() - 1);
        expect(cfg.isTokenExpired()).assertTrue();
      });
    });

    describe('HuaweiDriveScope', () => {
      it('FULL should grant full drive access', 0, () => {
        expect(HuaweiDriveScope.FULL).assertEqual('openid https://www.huawei.com/auth/drive');
      });

      it('APP_FILE should grant app-file access', 0, () => {
        expect(HuaweiDriveScope.APP_FILE).assertEqual('openid https://www.huawei.com/auth/drive.file');
      });

      it('should expose 2 scope values', 0, () => {
        const keys: string[] = Object.keys(HuaweiDriveScope);
        expect(keys.length).assertEqual(2);
      });

      it('FULL and APP_FILE should differ', 0, () => {
        const fullScope: string = HuaweiDriveScope.FULL;
        const appFileScope: string = HuaweiDriveScope.APP_FILE;
        expect(fullScope !== appFileScope).assertTrue();
      });
    });

    describe('HuaweiDrivePageConfig', () => {
      it('should expose pageUrl', 0, () => {
        expect(HuaweiDrivePageConfig.pageUrl).assertEqual('storage/huawei/HuaweiDrivePage');
      });

      it('should map to HUAWEI_DRIVE storage type', 0, () => {
        expect(HuaweiDrivePageConfig.storageType).assertEqual(StorageType.HUAWEI_DRIVE);
      });

      it('should expose icon resource', 0, () => {
        expect(HuaweiDrivePageConfig.icon).not().assertUndefined();
      });

      it('should expose title resource', 0, () => {
        expect(HuaweiDrivePageConfig.title).not().assertUndefined();
      });

      it('should expose selectDesc resource', 0, () => {
        expect(HuaweiDrivePageConfig.selectDesc).not().assertUndefined();
      });

      it('should expose saveDesc resource', 0, () => {
        expect(HuaweiDrivePageConfig.saveDesc).not().assertUndefined();
      });
    });
  });
}
