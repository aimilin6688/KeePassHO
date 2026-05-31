import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { XmlImportHandler } from '../../../../main/ets/services/importExport/handlers/import/XmlImportHandler';
import { XmlExportHandler } from '../../../../main/ets/services/importExport/handlers/export/XmlExportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { Kdbx, KdbxCredentials } from 'kdbxweb';

/**
 * XML 导入导出完整功能测试
 * 测试目标：
 * 1. XML 导入能够正确解析 KeePass XML 格式文件
 * 2. XML 导出能够将数据库导出为 KeePass XML 格式
 * 3. 导入导出能够互相验证（导出后重新导入验证数据一致性）
 */
export default function XmlExportHandlerTest() {
  describe('XmlImportHandler', () => {
    let handler: XmlImportHandler = new XmlImportHandler();

    beforeEach(() => {
      handler = new XmlImportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptXmlFormatId', 0, () => {
        expect(handler.canHandle('.xml')).assertTrue();
      });

      it('shouldBeCaseInsensitive', 0, () => {
        expect(handler.canHandle('.XML')).assertTrue();
        expect(handler.canHandle('.Xml')).assertTrue();
      });

      it('shouldRejectOtherFormatIds', 0, () => {
        expect(handler.canHandle('.csv')).assertFalse();
        expect(handler.canHandle('.json')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('XML');
        expect(handler.formatName).assertEqual('XML');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.xml');
      });
    });

    describe('importBasicFunctionality', () => {
      it('shouldImportValidKeePassXml', 0, async () => {
        // 先创建一个数据库并导出为 XML
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Test Entry', 'user', 'pass');

        const xmlContent = await db.saveXml(true, true);
        const fileContent = TestUtils.createFileContent(xmlContent, 'test.xml');

        const result = await handler.import(fileContent);

        expect(result).not().assertNull();
        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Title')).assertEqual('Test Entry');
      });

      it('shouldImportDatabaseWithMultipleEntries', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Entry1', 'user1', 'pass1');
        TestUtils.createTestEntry(db, rootGroup, 'Entry2', 'user2', 'pass2');
        TestUtils.createTestEntry(db, rootGroup, 'Entry3', 'user3', 'pass3');

        const xmlContent = await db.saveXml(true, true);
        const fileContent = TestUtils.createFileContent(xmlContent, 'test.xml');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(3);
      });

      it('shouldImportGroupsCorrectly', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        const workGroup = TestUtils.createTestGroup(db, rootGroup, 'Work');
        TestUtils.createTestEntry(db, workGroup, 'Work Entry', 'workuser');

        const xmlContent = await db.saveXml(true, true);
        const fileContent = TestUtils.createFileContent(xmlContent, 'test.xml');

        const result = await handler.import(fileContent);

        // 验证分组被导入
        expect(result.groups.length).assertLarger(0);
      });

      it('shouldPreserveEntryFields', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(
          db, rootGroup,
          'Full Entry',
          'user@example.com',
          'secret123',
          'https://example.com',
          'Important notes'
        );

        const xmlContent = await db.saveXml(true, true);
        const fileContent = TestUtils.createFileContent(xmlContent, 'test.xml');

        const result = await handler.import(fileContent);

        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('Full Entry');
        expect(entry.fields.get('UserName')).assertEqual('user@example.com');
        expect(entry.fields.get('URL')).assertEqual('https://example.com');
      });
    });

    describe('importErrorHandling', () => {
      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const fileContent = TestUtils.createFileContent('', 'test.xml');

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

      it('shouldThrowInvalidFileFormatForInvalidXml', 0, async () => {
        const fileContent = TestUtils.createFileContent('not valid xml', 'test.xml');

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.INVALID_FILE_FORMAT);
          }
        }
      });
    });
  });

  describe('XmlExportHandler', () => {
    let handler: XmlExportHandler = new XmlExportHandler();

    beforeEach(() => {
      handler = new XmlExportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptXmlFormatId', 0, () => {
        expect(handler.canHandle('XML')).assertTrue();
      });

      it('shouldRejectOtherFormatIds', 0, () => {
        expect(handler.canHandle('CSV')).assertFalse();
        expect(handler.canHandle('KDBX')).assertFalse();
        expect(handler.canHandle('xml')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('XML');
        expect(handler.formatName).assertEqual('XML');
        expect(handler.defaultFileName).assertEqual('export.xml');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.xml');
      });
    });

    describe('exportBasicFunctionality', () => {
      it('shouldExportDatabaseAsXml', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('XML Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Test Entry', 'user', 'pass');

        const result = await handler.export(testDb);
        const xmlContent = TestUtils.decodeBuffer(result);

        expect(xmlContent).assertContain('<?xml');
        expect(xmlContent).assertContain('Test Entry');
        expect(xmlContent).assertContain('user');
      });

      it('shouldExportWithCorrectXmlDeclaration', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('XML Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Test', 'user');

        const result = await handler.export(testDb);
        const xmlContent = TestUtils.decodeBuffer(result);

        expect(xmlContent.startsWith('<?xml')).assertTrue();
      });

      it('shouldIncludeDatabaseName', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('XML Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Test', 'user');

        const result = await handler.export(testDb);
        const xmlContent = TestUtils.decodeBuffer(result);

        expect(xmlContent).assertContain('XML Export Test');
      });

      it('shouldReturnArrayBuffer', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('XML Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        TestUtils.createTestEntry(testDb, rootGroup, 'Test', 'user');

        const result = await handler.export(testDb);

        expect(result instanceof ArrayBuffer).assertTrue();
        expect(result.byteLength).assertLarger(0);
      });

      it('shouldExportGroupsAndSubgroups', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('XML Export Test');
        FileService.resetDbFileParam(testDb, Date.now());
        const rootGroup = testDb.getDefaultGroup();
        const subgroup = TestUtils.createTestGroup(testDb, rootGroup, 'SubGroup');
        TestUtils.createTestEntry(testDb, subgroup, 'Entry1', 'user1');

        const result = await handler.export(testDb);
        const xmlContent = TestUtils.decodeBuffer(result);

        expect(xmlContent).assertContain('SubGroup');
        expect(xmlContent).assertContain('Entry1');
      });
    });
  });

  describe('XmlImportExportRoundTrip', () => {
    let importHandler: XmlImportHandler = new XmlImportHandler();
    let exportHandler: XmlExportHandler = new XmlExportHandler();

    beforeEach(() => {
      importHandler = new XmlImportHandler();
      exportHandler = new XmlExportHandler();
    });

    it('shouldPreserveEntryDataThroughRoundTrip', 0, async () => {
      // 创建测试数据库
      const db = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(db, Date.now());
      const rootGroup = db.getDefaultGroup();

      // 添加测试条目
      TestUtils.createTestEntry(db, rootGroup, 'Original Entry', 'original@example.com', 'password123');

      // 导出为 XML
      const exportedData = await exportHandler.export(db);
      const xmlContent = TestUtils.decodeBuffer(exportedData);

      // 导入 XML
      const fileContent = TestUtils.createFileContent(xmlContent, 'reimport.xml');
      const importedGroup = await importHandler.import(fileContent);

      // 验证数据一致性
      expect(importedGroup.entries.length).assertEqual(1);

      const importedEntry = importedGroup.entries[0];
      expect(importedEntry.fields.get('Title')).assertEqual('Original Entry');
      expect(importedEntry.fields.get('UserName')).assertEqual('original@example.com');
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
      const xmlContent = TestUtils.decodeBuffer(exportedData);

      // 重新导入
      const fileContent = TestUtils.createFileContent(xmlContent, 'reimport.xml');
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
      const xmlContent = TestUtils.decodeBuffer(exportedData);

      // 重新导入
      const fileContent = TestUtils.createFileContent(xmlContent, 'reimport.xml');
      const importedGroup = await importHandler.import(fileContent);

      // 验证分组被正确导入
      expect(importedGroup.groups.length).assertLarger(0);
    });

    it('shouldPreserveURLAndNotesFields', 0, async () => {
      const db = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(db, Date.now());
      const rootGroup = db.getDefaultGroup();

      // 创建带完整字段的条目
      TestUtils.createTestEntry(
        db, rootGroup,
        'Full Entry',
        'user@example.com',
        'secret',
        'https://example.com',
        'Important notes for this entry'
      );

      // 导出
      const exportedData = await exportHandler.export(db);
      const xmlContent = TestUtils.decodeBuffer(exportedData);

      // 重新导入
      const fileContent = TestUtils.createFileContent(xmlContent, 'reimport.xml');
      const importedGroup = await importHandler.import(fileContent);

      // 验证字段
      const entry = importedGroup.entries[0];
      expect(entry.fields.get('URL')).assertEqual('https://example.com');
      expect(entry.fields.get('Notes')).assertEqual('Important notes for this entry');
    });

    it('shouldPreserveNestedGroups', 0, async () => {
      const db = await TestUtils.createTestDatabase();
      FileService.resetDbFileParam(db, Date.now());
      const rootGroup = db.getDefaultGroup();

      // 创建嵌套分组
      const workGroup = TestUtils.createTestGroup(db, rootGroup, 'Work');
      const projectsGroup = TestUtils.createTestGroup(db, workGroup, 'Projects');
      TestUtils.createTestEntry(db, projectsGroup, 'Project Entry', 'projectuser');

      // 导出
      const exportedData = await exportHandler.export(db);
      const xmlContent = TestUtils.decodeBuffer(exportedData);

      // 重新导入
      const fileContent = TestUtils.createFileContent(xmlContent, 'reimport.xml');
      const importedGroup = await importHandler.import(fileContent);

      // 验证嵌套分组
      expect(importedGroup.groups.length).assertLarger(0);

      // 找到 Work 分组
      let workGroupFound = false;
      for (const g of importedGroup.groups) {
        if (g.name === 'Work') {
          workGroupFound = true;
          expect(g.groups.length).assertLarger(0);
          break;
        }
      }
      expect(workGroupFound).assertTrue();
    });
  });
}
