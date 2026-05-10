import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { RecentFilesService } from '../../../../main/ets/services/RecentFilesService';
import { RecentFile } from '../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../main/ets/storage/StorageType';
import { LocalFileStorageConfig } from '../../../../main/ets/storage/local/LocalFileConfig';

const testConfig = new LocalFileStorageConfig();

export default function RecentFilesServiceTest() {
  describe('RecentFilesService', () => {
    // 测试 mergeRecentFileLists 纯函数
    describe('mergeRecentFileLists', () => {
      it('should return empty list when both lists are empty', 0, () => {
        const result = RecentFilesService.mergeRecentFileLists([], []);
        expect(result.length).assertEqual(0);
      });

      it('should return local files when remote is empty', 0, () => {
        const localFiles: RecentFile[] = [
          { filePath: '/path/a.kdbx', fileName: 'a.kdbx', storageType: StorageType.LOCAL, storageConfig: testConfig }
        ];
        const result = RecentFilesService.mergeRecentFileLists(localFiles, []);
        expect(result.length).assertEqual(1);
        expect(result[0].filePath).assertEqual('/path/a.kdbx');
      });

      it('should return remote files when local is empty', 0, () => {
        const remoteFiles: RecentFile[] = [
          { filePath: '/path/b.kdbx', fileName: 'b.kdbx', storageType: StorageType.LOCAL, storageConfig: testConfig }
        ];
        const result = RecentFilesService.mergeRecentFileLists([], remoteFiles);
        expect(result.length).assertEqual(1);
        expect(result[0].filePath).assertEqual('/path/b.kdbx');
      });

      it('should give local files priority when same filePath exists', 0, () => {
        const localFiles: RecentFile[] = [
          { filePath: '/path/a.kdbx', fileName: 'a_local.kdbx', storageType: StorageType.LOCAL, storageConfig: testConfig }
        ];
        const remoteFiles: RecentFile[] = [
          { filePath: '/path/a.kdbx', fileName: 'a_remote.kdbx', storageType: StorageType.LOCAL, storageConfig: testConfig }
        ];
        const result = RecentFilesService.mergeRecentFileLists(localFiles, remoteFiles);
        expect(result.length).assertEqual(1);
        expect(result[0].fileName).assertEqual('a_local.kdbx');
      });

      it('should merge files from both lists preserving order', 0, () => {
        const localFiles: RecentFile[] = [
          { filePath: '/path/a.kdbx', fileName: 'a.kdbx', storageType: StorageType.LOCAL, storageConfig: testConfig },
          { filePath: '/path/c.kdbx', fileName: 'c.kdbx', storageType: StorageType.LOCAL, storageConfig: testConfig }
        ];
        const remoteFiles: RecentFile[] = [
          { filePath: '/path/b.kdbx', fileName: 'b.kdbx', storageType: StorageType.LOCAL, storageConfig: testConfig },
          { filePath: '/path/a.kdbx', fileName: 'a_remote.kdbx', storageType: StorageType.LOCAL, storageConfig: testConfig }
        ];
        const result = RecentFilesService.mergeRecentFileLists(localFiles, remoteFiles);
        expect(result.length).assertEqual(3);
        expect(result[0].filePath).assertEqual('/path/a.kdbx');
        expect(result[1].filePath).assertEqual('/path/c.kdbx');
        expect(result[2].filePath).assertEqual('/path/b.kdbx');
      });

      it('should respect MAX_RECENT_FILES limit', 0, () => {
        const localFiles: RecentFile[] = [];
        const remoteFiles: RecentFile[] = [];
        for (let i = 0; i < 35; i++) {
          localFiles.push({
            filePath: `/path/local_${i}.kdbx`, fileName: `local_${i}.kdbx`,
            storageType: StorageType.LOCAL, storageConfig: testConfig
          });
          remoteFiles.push({
            filePath: `/path/remote_${i}.kdbx`, fileName: `remote_${i}.kdbx`,
            storageType: StorageType.LOCAL, storageConfig: testConfig
          });
        }
        const result = RecentFilesService.mergeRecentFileLists(localFiles, remoteFiles);
        expect(result.length).assertEqual(30);
      });
    });
  });
}
