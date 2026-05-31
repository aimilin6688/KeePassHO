import { describe, expect, it } from '@ohos/hypium';
import { PCloudStorage } from '../../../../../main/ets/storage/pcloud/PCloudStorage';
import { PCloudStorageConfig } from '../../../../../main/ets/storage/pcloud/PCloudConfig';
import { StorageType } from '../../../../../main/ets/storage/StorageType';
import { runFileStorageTests } from '../FileStorageTestSuite';
import { PCloudTestConfig } from './PCloudTestConfig';

export default function PCloudStorageCommon() {
    runFileStorageTests({
    storageType: StorageType.PCLOUD,
    pageUrl: 'storage/pcloud/PCloudPage',
    createStorage: () => new PCloudStorage(),
    createConfig: () => PCloudTestConfig.createStorageConfig(),
    listDirPath: PCloudTestConfig.ROOT_FOLDER_ID,
    writeDir: PCloudTestConfig.ROOT_FOLDER_ID + '/',
    nonExistentPath: 'f999999999',
    specificTests: () => {
      it('should reject write path without slash', 0, async () => {
        const s = new PCloudStorage();
        s.init(new PCloudStorageConfig());
        let caught = false;
        try { await s.write('invalidpath', new ArrayBuffer(0)); }
        catch (e) { caught = true; }
        expect(caught).assertTrue();
      });
    }
  });
}
