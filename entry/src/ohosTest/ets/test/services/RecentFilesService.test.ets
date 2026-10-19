import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { RecentFilesService } from '../../../../main/ets/services/RecentFilesService';
import { RecentFile } from '../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../main/ets/storage/StorageType';
import { LocalFileStorageConfig } from '../../../../main/ets/storage/local/LocalFileConfig';

const testConfig = new LocalFileStorageConfig();

function makeRecord(filePath: string, fileName: string, storageType: StorageType,
  storageConfig: LocalFileStorageConfig = testConfig): RecentFile {
  return { filePath, fileName, storageType, storageConfig };
}

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

    // 测试 mergeChildConfigRecord 纯函数（M6.9 子库连接配置回写）
    describe('mergeChildConfigRecord', () => {
      it('appends new record at tail without reordering existing list', 0, () => {
        const recentFiles: RecentFile[] = [
          makeRecord('/path/a.kdbx', 'a.kdbx', StorageType.WEBDAV),
          makeRecord('/path/b.kdbx', 'b.kdbx', StorageType.WEBDAV)
        ];
        const record = makeRecord('/path/child.kdbx', 'child.kdbx', StorageType.WEBDAV);
        const result = RecentFilesService.mergeChildConfigRecord(recentFiles, record);
        expect(result.length).assertEqual(3);
        expect(result[0].filePath).assertEqual('/path/a.kdbx');
        expect(result[1].filePath).assertEqual('/path/b.kdbx');
        expect(result[2].filePath).assertEqual('/path/child.kdbx');
        expect(result[2] === record).assertTrue();
      });

      it('updates in place preserving password and search history', 0, () => {
        const recentFiles: RecentFile[] = [{
          filePath: '/path/child.kdbx', fileName: 'child.kdbx',
          storageType: StorageType.WEBDAV, storageConfig: new LocalFileStorageConfig(100),
          password: 'encrypted-secret', passwordSaveTime: 1000,
          searchHistory: ['k1', 'k2'], fileSize: 12345, yubikeySlot: 2
        }];
        const newConfig = new LocalFileStorageConfig(200);
        const record: RecentFile = {
          filePath: '/path/child.kdbx', fileName: 'child-renamed.kdbx',
          storageType: StorageType.WEBDAV, storageConfig: newConfig
        };
        const result = RecentFilesService.mergeChildConfigRecord(recentFiles, record);
        expect(result.length).assertEqual(1);
        expect(result[0].storageConfig === newConfig).assertTrue();
        expect(result[0].fileName).assertEqual('child-renamed.kdbx');
        expect(result[0].password).assertEqual('encrypted-secret');
        expect(result[0].passwordSaveTime).assertEqual(1000);
        expect(result[0].searchHistory?.length).assertEqual(2);
        expect(result[0].searchHistory?.[0]).assertEqual('k1');
        expect(result[0].fileSize).assertEqual(12345);
        expect(result[0].yubikeySlot).assertEqual(2);
      });

      it('returns the same reference when config is unchanged', 0, () => {
        const recentFiles: RecentFile[] = [
          makeRecord('/path/child.kdbx', 'child.kdbx', StorageType.WEBDAV,
            new LocalFileStorageConfig(0))
        ];
        const record = makeRecord('/path/child.kdbx', 'child.kdbx', StorageType.WEBDAV,
          new LocalFileStorageConfig(0));
        const result = RecentFilesService.mergeChildConfigRecord(recentFiles, record);
        expect(result === recentFiles).assertTrue();
      });

      it('matches records by storageType and filePath jointly', 0, () => {
        const recentFiles: RecentFile[] = [
          makeRecord('/path/same.kdbx', 'local.kdbx', StorageType.LOCAL)
        ];
        const record = makeRecord('/path/same.kdbx', 'webdav.kdbx', StorageType.WEBDAV);
        const result = RecentFilesService.mergeChildConfigRecord(recentFiles, record);
        expect(result.length).assertEqual(2);
        expect(result[0].storageType).assertEqual(StorageType.LOCAL);
        expect(result[1].storageType).assertEqual(StorageType.WEBDAV);
      });

      it('evicts oldest beyond MAX_RECENT_FILES then appends', 0, () => {
        const recentFiles: RecentFile[] = [];
        for (let i = 0; i < 30; i++) {
          recentFiles.push(makeRecord(`/path/old_${i}.kdbx`, `old_${i}.kdbx`, StorageType.WEBDAV));
        }
        const record = makeRecord('/path/child.kdbx', 'child.kdbx', StorageType.WEBDAV);
        const result = RecentFilesService.mergeChildConfigRecord(recentFiles, record);
        expect(result.length).assertEqual(30);
        expect(result[0].filePath).assertEqual('/path/old_0.kdbx');
        expect(result[28].filePath).assertEqual('/path/old_28.kdbx');
        expect(result[29].filePath).assertEqual('/path/child.kdbx');
      });
    });
  });
}
