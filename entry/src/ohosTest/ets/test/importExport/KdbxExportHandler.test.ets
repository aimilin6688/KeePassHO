import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { KdbxExportHandler } from '../../../../main/ets/services/importExport/handlers/export/KdbxExportHandler';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { Kdbx, KdbxCredentials } from 'kdbxweb';

/**
 * KDBX 导出完整功能测试
 * 测试目标：
 * 1. 能够将数据库导出为有效的 KDBX 格式
 * 2. 导出的 KDBX 文件可以被重新加载
 * 3. 导出后重新加载数据完整性验证
 */
export default function KdbxExportHandlerTest() {
  describe('KdbxExportHandler', () => {
    let handler: KdbxExportHandler = new KdbxExportHandler();

    beforeEach(() => {
      handler = new KdbxExportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptKdbxFormatId', 0, () => {
        expect(handler.canHandle('KDBX')).assertTrue();
      });

      it('shouldRejectOtherFormatIds', 0, () => {
        expect(handler.canHandle('CSV')).assertFalse();
        expect(handler.canHandle('XML')).assertFalse();
        expect(handler.canHandle('kdbx')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('KDBX');
        expect(handler.formatName).assertEqual('KDBX');
        expect(handler.defaultFileName).assertEqual('export.kdbx');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.kdbx');
      });
    });

    describe('exportBasicFunctionality', () => {
      it('shouldExportDatabaseAsKdbxBinary', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Test Entry', 'user', 'pass');

        const result = await handler.export(testDb);

        expect(result instanceof ArrayBuffer).assertTrue();
        expect(result.byteLength).assertLarger(0);
      });

      it('shouldProduceValidKdbxFormat', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Test', 'user', 'pass');

        const result = await handler.export(testDb);

        // KDBX文件以特定的魔数开始
        const bytes = new Uint8Array(result);
        expect(bytes[0]).assertEqual(0x03); // KDBX版本前缀
        expect(bytes[1]).assertEqual(0xd9);
      });

      it('shouldExportDatabaseWithMultipleEntries', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Entry1', 'user1', 'pass1');
        TestUtils.createTestEntry(testDb, rootGroup, 'Entry2', 'user2', 'pass2');
        TestUtils.createTestEntry(testDb, rootGroup, 'Entry3', 'user3', 'pass3');

        const result = await handler.export(testDb);
        expect(result.byteLength).assertLarger(0);
      });

      it('shouldExportDatabaseWithGroups', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        const subgroup = TestUtils.createTestGroup(testDb, rootGroup, 'SubGroup');
        TestUtils.createTestEntry(testDb, subgroup, 'EntryInGroup', 'user');

        const result = await handler.export(testDb);
        expect(result.byteLength).assertLarger(0);
      });
    });

    describe('exportReimportVerification', () => {
      it('shouldBeReimportableWithSameData', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Test Entry', 'user', 'pass');

        const exportedData = await handler.export(testDb);

        // 尝试重新加载导出的数据
        const credentials = new KdbxCredentials(null);
        const reloadedDb = await Kdbx.load(exportedData, credentials);

        expect(reloadedDb).not().assertNull();
        expect(reloadedDb.getDefaultGroup().entries.length).assertEqual(1);

        const entry = reloadedDb.getDefaultGroup().entries[0];
        expect(entry.fields.get('Title')).assertEqual('Test Entry');
        expect(entry.fields.get('UserName')).assertEqual('user');
      });

      it('shouldPreserveMultipleEntriesAfterReimport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Entry A', 'userA', 'passA');
        TestUtils.createTestEntry(testDb, rootGroup, 'Entry B', 'userB', 'passB');
        TestUtils.createTestEntry(testDb, rootGroup, 'Entry C', 'userC', 'passC');

        const exportedData = await handler.export(testDb);

        const credentials = new KdbxCredentials(null);
        const reloadedDb = await Kdbx.load(exportedData, credentials);

        expect(reloadedDb.getDefaultGroup().entries.length).assertEqual(3);

        // 验证所有条目都存在
        const titles: string[] = [];
        for (const e of reloadedDb.getDefaultGroup().entries) {
          titles.push(e.fields.get('Title') as string);
        }
        expect(titles.includes('Entry A')).assertTrue();
        expect(titles.includes('Entry B')).assertTrue();
        expect(titles.includes('Entry C')).assertTrue();
      });

      it('shouldPreserveGroupStructureAfterReimport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        const workGroup = TestUtils.createTestGroup(testDb, rootGroup, 'Work');
        const personalGroup = TestUtils.createTestGroup(testDb, rootGroup, 'Personal');

        TestUtils.createTestEntry(testDb, workGroup, 'Work Entry', 'workuser');
        TestUtils.createTestEntry(testDb, personalGroup, 'Personal Entry', 'personaluser');

        const exportedData = await handler.export(testDb);

        const credentials = new KdbxCredentials(null);
        const reloadedDb = await Kdbx.load(exportedData, credentials);

        const reloadedRoot = reloadedDb.getDefaultGroup();
        // 注意：数据库可能包含回收站分组，所以分组数量 >= 2
        expect(reloadedRoot.groups.length >= 2).assertTrue();

        // 验证分组名称
        const groupNames: string[] = [];
        for (const g of reloadedRoot.groups) {
          if (g.name !== undefined) {
            groupNames.push(g.name);
          }
        }
        expect(groupNames.includes('Work')).assertTrue();
        expect(groupNames.includes('Personal')).assertTrue();
      });

      it('shouldPreserveNestedGroupsAfterReimport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        const workGroup = TestUtils.createTestGroup(testDb, rootGroup, 'Work');
        const projectsGroup = TestUtils.createTestGroup(testDb, workGroup, 'Projects');
        TestUtils.createTestEntry(testDb, projectsGroup, 'Project Entry', 'projectuser');

        const exportedData = await handler.export(testDb);

        const credentials = new KdbxCredentials(null);
        const reloadedDb = await Kdbx.load(exportedData, credentials);

        const reloadedRoot = reloadedDb.getDefaultGroup();

        // 找到 Work 分组
        let workGroupFound = false;
        for (const g of reloadedRoot.groups) {
          if (g.name === 'Work') {
            workGroupFound = true;
            expect(g.groups.length).assertEqual(1);
            expect(g.groups[0].name).assertEqual('Projects');
            break;
          }
        }
        expect(workGroupFound).assertTrue();
      });

      it('shouldPreserveEntryFieldsAfterReimport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(
          testDb, rootGroup,
          'Full Entry',
          'user@example.com',
          'secret123',
          'https://example.com',
          'Important notes'
        );

        const exportedData = await handler.export(testDb);

        const credentials = new KdbxCredentials(null);
        const reloadedDb = await Kdbx.load(exportedData, credentials);

        const entry = reloadedDb.getDefaultGroup().entries[0];
        expect(entry.fields.get('Title')).assertEqual('Full Entry');
        expect(entry.fields.get('UserName')).assertEqual('user@example.com');
        expect(entry.fields.get('URL')).assertEqual('https://example.com');
        expect(entry.fields.get('Notes')).assertEqual('Important notes');
      });

      it('shouldHandleEmptyDatabaseExport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        // 空数据库也应该可以导出
        const result = await handler.export(testDb);
        expect(result.byteLength).assertLarger(0);

        // 验证可以重新加载
        const credentials = new KdbxCredentials(null);
        const reloadedDb = await Kdbx.load(result, credentials);
        expect(reloadedDb).not().assertNull();
      });
    });

    describe('exportDataIntegrity', () => {
      it('shouldPreservePasswordProtectionStatus', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Protected', 'user', 'secret');

        const exportedData = await handler.export(testDb);

        const credentials = new KdbxCredentials(null);
        const reloadedDb = await Kdbx.load(exportedData, credentials);

        const reloadedEntry = reloadedDb.getDefaultGroup().entries[0];
        // 密码应该是 ProtectedValue 类型
        const password = reloadedEntry.fields.get('Password');
        expect(password).not().assertNull();
      });

      it('shouldPreserveSpecialCharactersInFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        const entry = TestUtils.createTestEntry(testDb, rootGroup, 'Entry with "quotes"', 'user');
        entry.fields.set('Notes', 'Notes with\nnewlines\nand\ttabs');

        const exportedData = await handler.export(testDb);

        const credentials = new KdbxCredentials(null);
        const reloadedDb = await Kdbx.load(exportedData, credentials);

        const reloadedEntry = reloadedDb.getDefaultGroup().entries[0];
        expect(reloadedEntry.fields.get('Title')).assertEqual('Entry with "quotes"');
        const notes = reloadedEntry.fields.get('Notes');
        expect(notes).assertContain('newlines');
        expect(notes).assertContain('tabs');
      });

      it('shouldHandleUnicodeCharacters', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(
          testDb, rootGroup,
          '中文标题',
          '用户名',
          '密码',
          'https://example.com/路径',
          '备注信息'
        );

        const exportedData = await handler.export(testDb);

        const credentials = new KdbxCredentials(null);
        const reloadedDb = await Kdbx.load(exportedData, credentials);

        const entry = reloadedDb.getDefaultGroup().entries[0];
        expect(entry.fields.get('Title')).assertEqual('中文标题');
        expect(entry.fields.get('UserName')).assertEqual('用户名');
      });
    });
  });
}
