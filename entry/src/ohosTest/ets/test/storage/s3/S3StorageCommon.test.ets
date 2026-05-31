import { describe, expect, it } from '@ohos/hypium';
import { S3Storage } from '../../../../../main/ets/storage/s3/S3Storage';
import { StorageType } from '../../../../../main/ets/storage/StorageType';
import { runFileStorageTests } from '../FileStorageTestSuite';
import { S3TestConfig } from './S3TestConfig';

export default function S3StorageCommonTest() {
  runFileStorageTests({
    storageType: StorageType.S3,
    pageUrl: 'storage/s3/S3Page',
    createStorage: () => new S3Storage(),
    createConfig: () => S3TestConfig.getStorageConfig(),
    listDirPath: S3TestConfig.BUCKET,
    writeDir: '',
    nonExistentPath: 'non-existent-s3-test-file-12345.kdbx',
    specificTests: () => {
      it('should create config with correct endpoint', 0, () => {
        const config = S3TestConfig.getStorageConfig();
        expect(config.endpoint).assertEqual(S3TestConfig.ENDPOINT);
      });
      it('should have default bucket', 0, () => {
        expect(S3TestConfig.BUCKET).assertEqual('default-1253435893');
      });
      it('should have default timeout', 0, () => {
        expect(S3TestConfig.TIMEOUT).assertEqual(30000);
      });
    }
  });
}
