import { describe, expect, it } from '@ohos/hypium';
import { S3MultipartConfig, S3PageConfig, S3StorageConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { StorageType } from '../../../../../main/ets/storage/StorageType';

export default function S3ConfigTest() {
  describe('S3ConfigTest', () => {

    describe('S3StorageConfig', () => {
      it('should encrypt credentials and decrypt back to original', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig(
          'https://s3.amazonaws.com', 'AKIAIOSFODNN7', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCY'
        );
        expect(cfg.endpoint).assertEqual('https://s3.amazonaws.com');
        expect(cfg.getAccessKeyIdText()).assertEqual('AKIAIOSFODNN7');
        expect(cfg.getSecretAccessKeyText()).assertEqual('wJalrXUtnFEMI/K7MDENG/bPxRfiCY');
      });

      it('should not store plaintext credentials', 0, () => {
        const plain: string = 'AKIAIOSFODNN7';
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', plain, 'secret');
        expect(cfg.accessKeyId !== plain).assertTrue();
        expect(cfg.secretAccessKey !== 'secret').assertTrue();
      });

      it('should default region to us-east-1', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', 'k', 's');
        expect(cfg.region).assertEqual('us-east-1');
      });

      it('should default bucket to undefined', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', 'k', 's');
        expect(cfg.bucket).assertUndefined();
      });

      it('should default pathStyle to false', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', 'k', 's');
        expect(cfg.pathStyle).assertFalse();
      });

      it('should default timeout to 30000ms', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', 'k', 's');
        expect(cfg.timeout).assertEqual(30000);
      });

      it('should accept custom region via options', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', 'k', 's',
          { region: 'eu-west-1' });
        expect(cfg.region).assertEqual('eu-west-1');
      });

      it('should accept custom bucket via options', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', 'k', 's',
          { bucket: 'my-bucket' });
        expect(cfg.bucket).assertEqual('my-bucket');
      });

      it('should accept pathStyle=true via options', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', 'k', 's',
          { pathStyle: true });
        expect(cfg.pathStyle).assertTrue();
      });

      it('should accept custom timeout via options', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', 'k', 's',
          { timeout: 60000 });
        expect(cfg.timeout).assertEqual(60000);
      });

      it('should accept all options together', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://minio.local:9000', 'minioadmin', 'minioadmin',
          { region: 'default', bucket: 'keepass', pathStyle: true, timeout: 10000 });
        expect(cfg.region).assertEqual('default');
        expect(cfg.bucket).assertEqual('keepass');
        expect(cfg.pathStyle).assertTrue();
        expect(cfg.timeout).assertEqual(10000);
        expect(cfg.getAccessKeyIdText()).assertEqual('minioadmin');
      });

      it('should support unicode credentials round-trip', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', '中文密钥', '密码');
        expect(cfg.getAccessKeyIdText()).assertEqual('中文密钥');
        expect(cfg.getSecretAccessKeyText()).assertEqual('密码');
      });

      it('should support empty-string credentials round-trip', 0, () => {
        const cfg: S3StorageConfig = new S3StorageConfig('https://s3.example.com', '', '');
        expect(cfg.getAccessKeyIdText()).assertEqual('');
        expect(cfg.getSecretAccessKeyText()).assertEqual('');
      });
    });

    describe('S3MultipartConfig', () => {
      it('MIN_PART_SIZE should be 5MB', 0, () => {
        expect(S3MultipartConfig.MIN_PART_SIZE).assertEqual(5 * 1024 * 1024);
      });

      it('RECOMMENDED_PART_SIZE should be 8MB', 0, () => {
        expect(S3MultipartConfig.RECOMMENDED_PART_SIZE).assertEqual(8 * 1024 * 1024);
      });

      it('MAX_PART_SIZE should be 32MB', 0, () => {
        expect(S3MultipartConfig.MAX_PART_SIZE).assertEqual(32 * 1024 * 1024);
      });

      it('MULTIPART_THRESHOLD should be 5MB', 0, () => {
        expect(S3MultipartConfig.MULTIPART_THRESHOLD).assertEqual(5 * 1024 * 1024);
      });

      it('TARGET_PART_COUNT should be 500', 0, () => {
        expect(S3MultipartConfig.TARGET_PART_COUNT).assertEqual(500);
      });

      it('CONCURRENT_UPLOADS should be 3', 0, () => {
        expect(S3MultipartConfig.CONCURRENT_UPLOADS).assertEqual(3);
      });

      it('MAX_RETRY_COUNT should be 3', 0, () => {
        expect(S3MultipartConfig.MAX_RETRY_COUNT).assertEqual(3);
      });

      it('PROGRESS_CALLBACK_INTERVAL should be 100ms', 0, () => {
        expect(S3MultipartConfig.PROGRESS_CALLBACK_INTERVAL).assertEqual(100);
      });

      it('MIN_PART_SIZE should be <= MAX_PART_SIZE', 0, () => {
        expect(S3MultipartConfig.MIN_PART_SIZE <= S3MultipartConfig.MAX_PART_SIZE).assertTrue();
      });

      it('RECOMMENDED_PART_SIZE should be within min/max range', 0, () => {
        expect(S3MultipartConfig.RECOMMENDED_PART_SIZE >= S3MultipartConfig.MIN_PART_SIZE).assertTrue();
        expect(S3MultipartConfig.RECOMMENDED_PART_SIZE <= S3MultipartConfig.MAX_PART_SIZE).assertTrue();
      });
    });

    describe('S3PageConfig', () => {
      it('should expose pageUrl', 0, () => {
        expect(S3PageConfig.pageUrl).assertEqual('storage/s3/S3Page');
      });

      it('should map to S3 storage type', 0, () => {
        expect(S3PageConfig.storageType).assertEqual(StorageType.S3);
      });

      it('should expose icon resource', 0, () => {
        expect(S3PageConfig.icon).not().assertUndefined();
      });

      it('should expose title resource', 0, () => {
        expect(S3PageConfig.title).not().assertUndefined();
      });

      it('should expose selectDesc resource', 0, () => {
        expect(S3PageConfig.selectDesc).not().assertUndefined();
      });

      it('should expose saveDesc resource', 0, () => {
        expect(S3PageConfig.saveDesc).not().assertUndefined();
      });
    });
  });
}
