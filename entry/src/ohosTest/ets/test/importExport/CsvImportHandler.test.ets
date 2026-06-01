import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { CsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/CsvImportHandler';
import { CsvExportHandler } from '../../../../main/ets/services/importExport/handlers/export/CsvExportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * CSV 导入导出完整功能测试
 * 测试目标：
 * 1. CSV 导入能够正确解析 CSV 文件内容并创建 KdbxGroup
 * 2. CSV 导出能够将数据库内容正确导出为 CSV 格式
 * 3. 导入导出能够互相验证（导出后重新导入验证数据一致性）
 */
export default function CsvImportHandlerTest() {
  describe('CsvImportHandler', () => {
    let handler: CsvImportHandler = new CsvImportHandler();

    beforeEach(() => {
      handler = new CsvImportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptCsvExtension', 0, () => {
        expect(handler.canHandle('.csv')).assertTrue();
      });

      it('shouldBeCaseInsensitive', 0, () => {
        expect(handler.canHandle('.CSV')).assertTrue();
        expect(handler.canHandle('.Csv')).assertTrue();
      });

      it('shouldRejectNonCsvExtensions', 0, () => {
        expect(handler.canHandle('.xml')).assertFalse();
        expect(handler.canHandle('.json')).assertFalse();
        expect(handler.canHandle('.txt')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('CSV');
        expect(handler.formatName).assertEqual('CSV');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('importBasicFunctionality', () => {
      it('shouldImportSingleEntryWithTitleOnly', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title\nTest Entry';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        const result = await handler.import(fileContent);

        expect(result).not().assertNull();
        expect(result.entries.length).assertEqual(1);

        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('Test Entry');
      });

      it('shouldImportMultipleEntries', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title\nEntry1\nEntry2\nEntry3';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(3);
        expect(result.entries[0].fields.get('Title')).assertEqual('Entry1');
        expect(result.entries[1].fields.get('Title')).assertEqual('Entry2');
        expect(result.entries[2].fields.get('Title')).assertEqual('Entry3');
      });

      it('shouldImportEntryWithAllStandardFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,UserName,Password,URL,Notes\n' +
          'My Entry,user@example.com,secret123,https://example.com,This is a note';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];

        expect(entry.fields.get('Title')).assertEqual('My Entry');
        expect(entry.fields.get('UserName')).assertEqual('user@example.com');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('secret123');
        expect(entry.fields.get('URL')).assertEqual('https://example.com');
        expect(entry.fields.get('Notes')).assertEqual('This is a note');
      });

      it('shouldImportEntryWithTOTPField', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,TOTP\n' +
          'TOTP Entry,otpauth://totp/issuer?secret=ABCDEF';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(KdbxUtils.getFieldValueString(entry.fields, 'TOTP')).assertEqual('otpauth://totp/issuer?secret=ABCDEF');
      });
    });

    describe('importGroupHandling', () => {
      it('shouldCreateGroupsFromGroupField', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Group,Title\n' +
          'Work,Work Entry\n' +
          'Personal,Personal Entry';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        const result = await handler.import(fileContent);

        // 应该有2个子分组
        expect(result.groups.length).assertEqual(2);

        // 验证分组名称
        const groupNames: string[] = [];
        for (const g of result.groups) {
          if (g.name !== undefined) {
            groupNames.push(g.name);
          }
        }
        expect(groupNames.includes('Work')).assertTrue();
        expect(groupNames.includes('Personal')).assertTrue();
      });

      it('shouldCreateNestedGroupsFromPath', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Group,Title\n' +
          'Work/Projects/ProjectA,Project A Entry\n' +
          'Work/Projects/ProjectB,Project B Entry';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        const result = await handler.import(fileContent);

        // 根分组下应该有 Work 分组
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Work');

        // Work 分组下应该有 Projects 分组
        const workGroup = result.groups[0];
        expect(workGroup.groups.length).assertEqual(1);
        expect(workGroup.groups[0].name).assertEqual('Projects');

        // Projects 分组下应该有 ProjectA 和 ProjectB
        const projectsGroup = workGroup.groups[0];
        expect(projectsGroup.groups.length).assertEqual(2);
      });

      it('shouldPlaceEntriesInCorrectGroups', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Group,Title\n' +
          'Work,Work Entry 1\n' +
          'Work,Work Entry 2\n' +
          'Personal,Personal Entry';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        const result = await handler.import(fileContent);

        // 找到 Work 分组
        let workGroup = result.groups[0];
        for (const g of result.groups) {
          if (g.name === 'Work') {
            workGroup = g;
            break;
          }
        }
        expect(workGroup.entries.length).assertEqual(2);

        // 找到 Personal 分组
        let personalGroup = result.groups[0];
        for (const g of result.groups) {
          if (g.name === 'Personal') {
            personalGroup = g;
            break;
          }
        }
        expect(personalGroup.entries.length).assertEqual(1);
      });
    });

    describe('importCsvParsing', () => {
      it('shouldHandleQuotedFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,Notes\n' +
          '"Entry with, comma","Note with ""quotes"" and, comma"';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];

        expect(entry.fields.get('Title')).assertEqual('Entry with, comma');
        expect(entry.fields.get('Notes')).assertEqual('Note with "quotes" and, comma');
      });

      it('shouldHandleEmptyLines', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title\nEntry1\n\nEntry2\n\n';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        const result = await handler.import(fileContent);

        // 空行应该被跳过
        expect(result.entries.length).assertEqual(2);
      });
    });

    describe('importErrorHandling', () => {
      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = '';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.FILE_EMPTY);
          }
        }
      });

      it('shouldThrowInvalidCsvHeaderWhenTitleMissing', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'UserName,Password\nuser,pass';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.INVALID_CSV_HEADER);
          }
        }
      });

      it('shouldHandleFileWithHeaderOnly', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,UserName,Password';
        const fileContent = TestUtils.createFileContent(csvContent, 'test.csv');

        const result = await handler.import(fileContent);

        // 只有标题行，没有数据行
        expect(result.entries.length).assertEqual(0);
      });
    });
  });

  describe('CsvExportHandler', () => {
    let handler: CsvExportHandler = new CsvExportHandler();

    beforeEach(() => {
      handler = new CsvExportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptCsvFormatId', 0, () => {
        expect(handler.canHandle('CSV')).assertTrue();
      });

      it('shouldRejectOtherFormatIds', 0, () => {
        expect(handler.canHandle('XML')).assertFalse();
        expect(handler.canHandle('KDBX')).assertFalse();
        expect(handler.canHandle('csv')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('CSV');
        expect(handler.formatName).assertEqual('CSV');
        expect(handler.defaultFileName).assertEqual('export.csv');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('exportBasicFunctionality', () => {
      it('shouldExportDatabaseWithSingleEntry', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Test Entry', 'user', 'pass');

        const result = await handler.export(testDb);
        const csvContent = TestUtils.decodeBuffer(result);

        // 验证包含标题行
        expect(csvContent).assertContain('Title');
        expect(csvContent).assertContain('UserName');
        expect(csvContent).assertContain('Password');

        // 验证包含条目数据
        expect(csvContent).assertContain('Test Entry');
        expect(csvContent).assertContain('user');
        expect(csvContent).assertContain('pass');
      });

      it('shouldExportDatabaseWithMultipleEntries', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Entry1', 'user1', 'pass1');
        TestUtils.createTestEntry(testDb, rootGroup, 'Entry2', 'user2', 'pass2');
        TestUtils.createTestEntry(testDb, rootGroup, 'Entry3', 'user3', 'pass3');

        const result = await handler.export(testDb);
        const csvContent = TestUtils.decodeBuffer(result);

        expect(csvContent).assertContain('Entry1');
        expect(csvContent).assertContain('Entry2');
        expect(csvContent).assertContain('Entry3');
      });

      it('shouldExportEntryWithURLAndNotes', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(
          testDb, rootGroup,
          'Full Entry',
          'user@example.com',
          'secret',
          'https://example.com',
          'Important notes'
        );

        const result = await handler.export(testDb);
        const csvContent = TestUtils.decodeBuffer(result);

        expect(csvContent).assertContain('Full Entry');
        expect(csvContent).assertContain('user@example.com');
        expect(csvContent).assertContain('https://example.com');
        expect(csvContent).assertContain('Important notes');
      });

      it('shouldReturnValidArrayBuffer', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Test', 'user');

        const result = await handler.export(testDb);

        expect(result instanceof ArrayBuffer).assertTrue();
        expect(result.byteLength).assertLarger(0);
      });
    });

    describe('exportGroupHandling', () => {
      it('shouldIncludeGroupPathInExport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        const workGroup = TestUtils.createTestGroup(testDb, rootGroup, 'Work');
        TestUtils.createTestEntry(testDb, workGroup, 'Work Entry', 'workuser');

        const result = await handler.export(testDb);
        const csvContent = TestUtils.decodeBuffer(result);

        expect(csvContent).assertContain('Work');
        expect(csvContent).assertContain('Work Entry');
      });

      it('shouldIncludeNestedGroupPath', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('CSV Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        const workGroup = TestUtils.createTestGroup(testDb, rootGroup, 'Work');
        const projectsGroup = TestUtils.createTestGroup(testDb, workGroup, 'Projects');
        TestUtils.createTestEntry(testDb, projectsGroup, 'Project Entry', 'projectuser');

        const result = await handler.export(testDb);
        const csvContent = TestUtils.decodeBuffer(result);

        // 路径应该包含 Work/Projects
        expect(csvContent).assertContain('Work');
        expect(csvContent).assertContain('Projects');
      });
    });
  });

  describe('CsvImportExportRoundTrip', () => {
    let importHandler: CsvImportHandler = new CsvImportHandler();
    let exportHandler: CsvExportHandler = new CsvExportHandler();

    beforeEach(() => {
      importHandler = new CsvImportHandler();
      exportHandler = new CsvExportHandler();
    });

    it('shouldPreserveBasicEntryDataThroughRoundTrip', 0, async () => {
      // 创建测试数据库
      const db = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(db, Date.now());
      const rootGroup = db.getDefaultGroup();

      // 添加测试条目
      TestUtils.createTestEntry(db, rootGroup, 'Original Entry', 'original@example.com', 'password123');

      // 导出为 CSV
      const exportedData = await exportHandler.export(db);
      const csvContent = TestUtils.decodeBuffer(exportedData);

      // 重新设置数据库用于导入
      const importDb = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(importDb, Date.now());

      // 导入 CSV
      const fileContent = TestUtils.createFileContent(csvContent, 'reimport.csv');
      const importedGroup = await importHandler.import(fileContent);

      // 验证数据一致性
      expect(importedGroup.entries.length).assertEqual(1);

      const importedEntry = importedGroup.entries[0];
      expect(importedEntry.fields.get('Title')).assertEqual('Original Entry');
      expect(importedEntry.fields.get('UserName')).assertEqual('original@example.com');
      expect(KdbxUtils.getFieldValueString(importedEntry.fields,'Password')).assertEqual('password123');
    });

    it('shouldPreserveMultipleEntriesThroughRoundTrip', 0, async () => {
      const db = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(db, Date.now());
      const rootGroup = db.getDefaultGroup();

      // 添加多个条目
      TestUtils.createTestEntry(db, rootGroup, 'Entry A', 'userA', 'passA');
      TestUtils.createTestEntry(db, rootGroup, 'Entry B', 'userB', 'passB');
      TestUtils.createTestEntry(db, rootGroup, 'Entry C', 'userC', 'passC');

      // 导出
      const exportedData = await exportHandler.export(db);
      const csvContent = TestUtils.decodeBuffer(exportedData);

      // 重新导入
      const importDb = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(importDb, Date.now());

      const fileContent = TestUtils.createFileContent(csvContent, 'reimport.csv');
      const importedGroup = await importHandler.import(fileContent);

      // 验证条目数量
      expect(importedGroup.entries.length).assertEqual(3);

      // 验证所有条目都被正确导入
      const titles: string[] = [];
      for (const e of importedGroup.entries) {
        titles.push(e.fields.get('Title') as string);
      }
      expect(titles.includes('Entry A')).assertTrue();
      expect(titles.includes('Entry B')).assertTrue();
      expect(titles.includes('Entry C')).assertTrue();
    });

    it('shouldPreserveGroupStructureThroughRoundTrip', 0, async () => {
      const db = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(db, Date.now());
      const rootGroup = db.getDefaultGroup();

      // 创建分组和条目
      const workGroup = TestUtils.createTestGroup(db, rootGroup, 'Work');
      const personalGroup = TestUtils.createTestGroup(db, rootGroup, 'Personal');

      TestUtils.createTestEntry(db, workGroup, 'Work Entry', 'workuser', 'workpass');
      TestUtils.createTestEntry(db, personalGroup, 'Personal Entry', 'personaluser', 'personalpass');

      // 导出
      const exportedData = await exportHandler.export(db);
      const csvContent = TestUtils.decodeBuffer(exportedData);

      // 重新导入
      const importDb = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(importDb, Date.now());

      const fileContent = TestUtils.createFileContent(csvContent, 'reimport.csv');
      const importedGroup = await importHandler.import(fileContent);

      // 验证分组被创建
      expect(importedGroup.groups.length).assertEqual(2);

      const groupNames: string[] = [];
      for (const g of importedGroup.groups) {
        if (g.name !== undefined) {
          groupNames.push(g.name);
        }
      }
      expect(groupNames.includes('Work')).assertTrue();
      expect(groupNames.includes('Personal')).assertTrue();
    });

    it('shouldPreserveSpecialCharactersThroughRoundTrip', 0, async () => {
      const db = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(db, Date.now());
      const rootGroup = db.getDefaultGroup();

      // 创建包含特殊字符的条目
      const entry = TestUtils.createTestEntry(db, rootGroup, 'Entry with, comma', 'user', 'pass');
      entry.fields.set('Notes', 'Notes with "quotes" and, comma');

      // 导出
      const exportedData = await exportHandler.export(db);
      const csvContent = TestUtils.decodeBuffer(exportedData);

      // 重新导入
      const importDb = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(importDb, Date.now());

      const fileContent = TestUtils.createFileContent(csvContent, 'reimport.csv');
      const importedGroup = await importHandler.import(fileContent);

      // 验证特殊字符被正确处理
      expect(importedGroup.entries.length).assertEqual(1);

      const importedEntry = importedGroup.entries[0];
      expect(importedEntry.fields.get('Title')).assertEqual('Entry with, comma');

      const notes = importedEntry.fields.get('Notes');
      expect(notes).assertContain('quotes');
      expect(notes).assertContain('comma');
    });
  });
}
