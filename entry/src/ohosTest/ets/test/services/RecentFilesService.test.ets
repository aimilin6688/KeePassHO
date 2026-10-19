import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { fileIo as fs } from '@kit.CoreFileKit';
import { RecentFilesService } from '../../../../main/ets/services/RecentFilesService';
import { RecentFile } from '../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../main/ets/storage/StorageType';
import { LocalFileStorageConfig } from '../../../../main/ets/storage/local/LocalFileConfig';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { TestContextHelper } from '../TestContextHelper';

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

  // 实例级契约测试：驱动真实单例（preferences 持久化），
  // beforeAll 快照真实最近文件列表并在 afterAll 完整还原，不污染应用数据
  describe('RecentFilesServiceInstance', () => {
    let savedFiles: RecentFile[] = [];

    beforeAll(async () => {
      const context = await TestContextHelper.getUIAbilityContext();
      await RecentFilesService.getInstance().init(context);
      savedFiles = await RecentFilesService.getInstance().getRecentFiles();
      await RecentFilesService.getInstance().clearRecentFiles();
    });

    afterAll(async () => {
      await RecentFilesService.getInstance().clearRecentFiles();
      await RecentFilesService.getInstance().doAddMerged(savedFiles);
    });

    it('getInstance returns singleton', 0, () => {
      const a = RecentFilesService.getInstance();
      const b = RecentFilesService.getInstance();
      expect(a === b).assertTrue();
    });

    it('getRecentFiles returns empty list after clear', 0, async () => {
      const files = await RecentFilesService.getInstance().getRecentFiles();
      expect(files.length).assertEqual(0);
    });

    it('loadMostRecentFile returns null when list is empty', 0, async () => {
      const recent = await RecentFilesService.getInstance().loadMostRecentFile();
      expect(recent).assertNull();
    });

    it('addRecentFile stores records and moves duplicate to top', 0, async () => {
      await RecentFilesService.addRecentFile(makeRecord('/path/a.kdbx', 'a.kdbx', StorageType.LOCAL));
      let files = await RecentFilesService.getInstance().getRecentFiles();
      expect(files.length).assertEqual(1);
      expect(files[0].filePath).assertEqual('/path/a.kdbx');
      await RecentFilesService.addRecentFile(makeRecord('/path/b.kdbx', 'b.kdbx', StorageType.LOCAL));
      files = await RecentFilesService.getInstance().getRecentFiles();
      expect(files.length).assertEqual(2);
      expect(files[0].filePath).assertEqual('/path/b.kdbx');
      // 重复添加：置顶且不产生重复记录
      await RecentFilesService.addRecentFile(makeRecord('/path/a.kdbx', 'a2.kdbx', StorageType.LOCAL));
      files = await RecentFilesService.getInstance().getRecentFiles();
      expect(files.length).assertEqual(2);
      expect(files[0].filePath).assertEqual('/path/a.kdbx');
      expect(files[0].fileName).assertEqual('a2.kdbx');
      expect(files[1].filePath).assertEqual('/path/b.kdbx');
    });

    it('addRecentFile rejects empty path', 0, async () => {
      let threw = false;
      try {
        await RecentFilesService.addRecentFile(makeRecord('', 'empty.kdbx', StorageType.LOCAL));
      } catch (error) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('getRecentFile finds by path and returns null for miss', 0, async () => {
      const found = await RecentFilesService.getRecentFile('/path/a.kdbx');
      expect(found).not().assertNull();
      expect(found!.filePath).assertEqual('/path/a.kdbx');
      const missing = await RecentFilesService.getRecentFile('/path/none.kdbx');
      expect(missing).assertNull();
    });

    it('setPassword encrypts, clearPassword wipes, empty args reject', 0, async () => {
      const setOk = await RecentFilesService.setPassword('/path/a.kdbx', 'secret');
      expect(setOk).assertTrue();
      const withPassword = await RecentFilesService.getRecentFile('/path/a.kdbx');
      expect(withPassword).not().assertNull();
      expect(withPassword!.password).not().assertUndefined();
      expect(withPassword!.password !== 'secret').assertTrue();
      const clearOk = await RecentFilesService.clearPassword('/path/a.kdbx');
      expect(clearOk).assertTrue();
      const cleared = await RecentFilesService.getRecentFile('/path/a.kdbx');
      expect(cleared!.password).assertUndefined();
      const emptyReject = await RecentFilesService.setPassword('/path/a.kdbx', '');
      expect(emptyReject).assertFalse();
    });

    it('searchHistory dedupes, keeps latest first and clears', 0, async () => {
      // 空关键词在门控之前拦截，恒为 false
      expect(await RecentFilesService.addSearchHistory('/path/a.kdbx', '')).assertFalse();
      const enableSearchHistory: boolean = SettingsService.isSearchHistoryEnable();
      const added1 = await RecentFilesService.addSearchHistory('/path/a.kdbx', 'k1');
      expect(added1).assertEqual(enableSearchHistory);
      const added2 = await RecentFilesService.addSearchHistory('/path/a.kdbx', 'k2');
      expect(added2).assertEqual(enableSearchHistory);
      if (!enableSearchHistory) {
        // 真机关闭了搜索历史：门控生效，恒为空
        const disabled = await RecentFilesService.getSearchHistory('/path/a.kdbx');
        expect(disabled.length).assertEqual(0);
        return;
      }
      // 重复关键词去重并前移
      const added3 = await RecentFilesService.addSearchHistory('/path/a.kdbx', 'k1');
      expect(added3).assertTrue();
      const history = await RecentFilesService.getSearchHistory('/path/a.kdbx');
      expect(history.length).assertEqual(2);
      expect(history[0]).assertEqual('k1');
      expect(history[1]).assertEqual('k2');
      expect(await RecentFilesService.clearSearchHistory('/path/a.kdbx')).assertTrue();
      const cleared = await RecentFilesService.getSearchHistory('/path/a.kdbx');
      expect(cleared.length).assertEqual(0);
    });

    it('removeRecentFile removes only the matching path', 0, async () => {
      await RecentFilesService.addRecentFile(makeRecord('/path/c.kdbx', 'c.kdbx', StorageType.LOCAL));
      await RecentFilesService.getInstance().removeRecentFile(makeRecord('/path/a.kdbx', 'a.kdbx', StorageType.LOCAL));
      const files = await RecentFilesService.getInstance().getRecentFiles();
      const stillHasA = files.some(file => file.filePath === '/path/a.kdbx');
      expect(stillHasA).assertFalse();
      const stillHasC = files.some(file => file.filePath === '/path/c.kdbx');
      expect(stillHasC).assertTrue();
    });

    it('checkFileExists probes real local file and reports missing as false', 0, async () => {
      const context = await TestContextHelper.getUIAbilityContext();
      const tmpPath = context.filesDir + '/recent-probe.kdbx';
      const file = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, 'kdbx-probe');
      await fs.close(file);
      try {
        const existing = makeRecord(tmpPath, 'recent-probe.kdbx', StorageType.LOCAL);
        const exists = await RecentFilesService.getInstance().checkFileExists(existing);
        expect(exists).assertTrue();
        const missing = makeRecord(context.filesDir + '/definitely-missing.kdbx', 'x.kdbx', StorageType.LOCAL);
        const missingExists = await RecentFilesService.getInstance().checkFileExists(missing);
        expect(missingExists).assertFalse();
      } finally {
        try {
          await fs.unlink(tmpPath);
        } catch (error) {
          // best effort
        }
      }
    });

    it('loadMostRecentFile returns top existing local file', 0, async () => {
      const context = await TestContextHelper.getUIAbilityContext();
      const tmpPath = context.filesDir + '/recent-most.kdbx';
      const file = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, 'kdbx-most-recent');
      await fs.close(file);
      try {
        await RecentFilesService.getInstance().clearRecentFiles();
        await RecentFilesService.addRecentFile(makeRecord(tmpPath, 'recent-most.kdbx', StorageType.LOCAL));
        const recent = await RecentFilesService.getInstance().loadMostRecentFile();
        expect(recent).not().assertNull();
        expect(recent!.filePath).assertEqual(tmpPath);
      } finally {
        try {
          await fs.unlink(tmpPath);
        } catch (error) {
          // best effort
        }
      }
    });
  });
}
