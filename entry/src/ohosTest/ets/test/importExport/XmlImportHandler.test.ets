import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { XmlImportHandler } from '../../../../main/ets/services/importExport/handlers/import/XmlImportHandler';
import { XmlExportHandler } from '../../../../main/ets/services/importExport/handlers/export/XmlExportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';
import { Kdbx } from 'kdbxweb';

/**
 * XmlImportHandler 单元测试
 * 测试目标：
 * 1. 解析 KeePass XML 导出格式（db.saveXml 产物）还原条目/分组结构
 * 2. 边界场景：空内容、纯空白、畸形 XML、非 KeePass 结构 XML、空数据库
 * 3. 字段保真（标准字段 + Unicode）
 * 4. 与 XmlExportHandler 往返一致性
 */
export default function XmlImportHandlerTest() {
  describe('XmlImportHandler', () => {
    let handler: XmlImportHandler = new XmlImportHandler();

    beforeEach(() => {
      handler = new XmlImportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptXmlExtension', 0, () => {
        expect(handler.canHandle('.xml')).assertTrue();
      });

      it('shouldAcceptXmlExtensionCaseInsensitive', 0, () => {
        expect(handler.canHandle('.XML')).assertTrue();
        expect(handler.canHandle('.Xml')).assertTrue();
        expect(handler.canHandle('.xMl')).assertTrue();
      });

      it('shouldRejectNonXmlExtensions', 0, () => {
        expect(handler.canHandle('.csv')).assertFalse();
        expect(handler.canHandle('.json')).assertFalse();
        expect(handler.canHandle('.kdbx')).assertFalse();
        expect(handler.canHandle('.txt')).assertFalse();
        expect(handler.canHandle('')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldExposeCorrectFormatMetadata', 0, () => {
        expect(handler.formatId).assertEqual('XML');
        expect(handler.formatName).assertEqual('XML');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.xml');
      });
    });

    describe('importValidKeePassXml', () => {
      it('shouldImportSingleEntryFromXml', 0, async () => {
        const db = await TestUtils.createTestDatabase('Xml Import Db');
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

      it('shouldImportMultipleEntries', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Entry1', 'u1', 'p1');
        TestUtils.createTestEntry(db, rootGroup, 'Entry2', 'u2', 'p2');
        TestUtils.createTestEntry(db, rootGroup, 'Entry3', 'u3', 'p3');

        const xmlContent = await db.saveXml(true, true);
        const result = await handler.import(TestUtils.createFileContent(xmlContent, 't.xml'));

        expect(result.entries.length).assertEqual(3);

        const titles: string[] = [];
        for (const e of result.entries) {
          titles.push(e.fields.get('Title') as string);
        }
        expect(titles.includes('Entry1')).assertTrue();
        expect(titles.includes('Entry2')).assertTrue();
        expect(titles.includes('Entry3')).assertTrue();
      });

      it('shouldImportAllStandardFields', 0, async () => {
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
        const result = await handler.import(TestUtils.createFileContent(xmlContent, 't.xml'));

        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('Full Entry');
        expect(entry.fields.get('UserName')).assertEqual('user@example.com');
        expect(entry.fields.get('URL')).assertEqual('https://example.com');
        expect(entry.fields.get('Notes')).assertEqual('Important notes');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('secret123');
      });

      it('shouldImportGroupsAndNestedGroups', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        const workGroup = TestUtils.createTestGroup(db, rootGroup, 'Work');
        const projectsGroup = TestUtils.createTestGroup(db, workGroup, 'Projects');
        TestUtils.createTestEntry(db, projectsGroup, 'Project Entry', 'pu');

        const xmlContent = await db.saveXml(true, true);
        const result = await handler.import(TestUtils.createFileContent(xmlContent, 't.xml'));

        expect(result.groups.length).assertLarger(0);

        let workFound = false;
        for (const g of result.groups) {
          if (g.name === 'Work') {
            workFound = true;
            expect(g.groups.length).assertLarger(0);
            let projectsFound = false;
            for (const sg of g.groups) {
              if (sg.name === 'Projects') {
                projectsFound = true;
                break;
              }
            }
            expect(projectsFound).assertTrue();
            break;
          }
        }
        expect(workFound).assertTrue();
      });

      it('shouldImportEmptyDatabaseAsZeroEntries', 0, async () => {
        const db = await TestUtils.createTestDatabase('Empty Db');
        FileService.resetDbFileParam(db, Date.now());

        const xmlContent = await db.saveXml(true, true);
        const result = await handler.import(TestUtils.createFileContent(xmlContent, 't.xml'));

        expect(result).not().assertNull();
        expect(result.entries.length).assertEqual(0);
      });

      it('shouldPreserveUnicodeCharacters', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(
          db, rootGroup,
          '中文标题',
          '用户名',
          '密码',
          'https://example.com/路径',
          '备注信息'
        );

        const xmlContent = await db.saveXml(true, true);
        const result = await handler.import(TestUtils.createFileContent(xmlContent, 't.xml'));

        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('中文标题');
        expect(entry.fields.get('UserName')).assertEqual('用户名');
        expect(entry.fields.get('URL')).assertEqual('https://example.com/路径');
        expect(entry.fields.get('Notes')).assertEqual('备注信息');
      });
    });

    describe('importErrorHandling', () => {
      it('shouldThrowFileEmptyForEmptyContent', 0, async () => {
        const fileContent = TestUtils.createFileContent('', 'test.xml');

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          expect(error instanceof ImportError).assertTrue();
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.FILE_EMPTY);
          }
        }
      });

      it('shouldThrowFileEmptyForWhitespaceOnlyContent', 0, async () => {
        const fileContent = TestUtils.createFileContent('   \n\t  \r\n  ', 'test.xml');

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          expect(error instanceof ImportError).assertTrue();
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.FILE_EMPTY);
          }
        }
      });

      it('shouldThrowInvalidFileFormatForMalformedXml', 0, async () => {
        const fileContent = TestUtils.createFileContent('not valid xml <<<?', 'test.xml');

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          expect(error instanceof ImportError).assertTrue();
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.INVALID_FILE_FORMAT);
          }
        }
      });

      it('shouldThrowInvalidFileFormatForUnclosedTag', 0, async () => {
        const fileContent = TestUtils.createFileContent('<root><child>text</root>', 'test.xml');

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          expect(error instanceof ImportError).assertTrue();
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.INVALID_FILE_FORMAT);
          }
        }
      });

      it('shouldThrowInvalidFileFormatForNonKeePassXml', 0, async () => {
        // 合法 XML 但非 KeePass 结构
        const fileContent = TestUtils.createFileContent(
          '<?xml version="1.0" encoding="utf-8"?>\n<Root><Item>hello</Item></Root>',
          'test.xml'
        );

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          expect(error instanceof ImportError).assertTrue();
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.INVALID_FILE_FORMAT);
          }
        }
      });
    });

    describe('roundTripWithXmlExportHandler', () => {
      it('shouldPreserveEntryDataThroughExportImport', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'RoundTrip Entry', 'rt@example.com', 'rtpass');

        const exportHandler = new XmlExportHandler();
        const exported = await exportHandler.export(db);
        const xmlContent = TestUtils.decodeBuffer(exported);

        const imported = await handler.import(TestUtils.createFileContent(xmlContent, 'rt.xml'));

        expect(imported.entries.length).assertEqual(1);
        const entry = imported.entries[0];
        expect(entry.fields.get('Title')).assertEqual('RoundTrip Entry');
        expect(entry.fields.get('UserName')).assertEqual('rt@example.com');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('rtpass');
      });

      it('shouldPreserveGroupStructureThroughExportImport', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        const workGroup = TestUtils.createTestGroup(db, rootGroup, 'Work');
        const personalGroup = TestUtils.createTestGroup(db, rootGroup, 'Personal');
        TestUtils.createTestEntry(db, workGroup, 'Work Entry', 'wu', 'wp');
        TestUtils.createTestEntry(db, personalGroup, 'Personal Entry', 'pu', 'pp');

        const exportHandler = new XmlExportHandler();
        const exported = await exportHandler.export(db);
        const xmlContent = TestUtils.decodeBuffer(exported);

        const imported = await handler.import(TestUtils.createFileContent(xmlContent, 'rt.xml'));

        expect(imported.groups.length).assertLarger(0);
        const groupNames: string[] = [];
        for (const g of imported.groups) {
          if (g.name !== undefined) {
            groupNames.push(g.name);
          }
        }
        expect(groupNames.includes('Work')).assertTrue();
        expect(groupNames.includes('Personal')).assertTrue();
      });
    });
  });
}
