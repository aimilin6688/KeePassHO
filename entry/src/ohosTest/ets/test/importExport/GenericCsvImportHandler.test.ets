import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { GenericCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/GenericCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * GenericCsvImportHandler 单元测试
 * 通用 CSV 导入（嗅探兜底）：
 * 1. 标准 KeePass 表头 + 扩展目标列（TOTP/Tags/Icon/Last Modified/Created）
 * 2. 同义词表头自动建议映射
 * 3. 标题兜底链：Title → URL 域名 → UserName → 本地化“条目 N”
 */
export default function GenericCsvImportHandlerTest() {
  describe('GenericCsvImportHandler', () => {
    let handler: GenericCsvImportHandler = new GenericCsvImportHandler();

    beforeEach(() => {
      handler = new GenericCsvImportHandler();
    });

    describe('canHandleAndProperties', () => {
      it('shouldAcceptCsvExtension', 0, () => {
        expect(handler.canHandle('.csv')).assertTrue();
        expect(handler.canHandle('.xml')).assertFalse();
      });

      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('GENERIC_CSV');
        expect(handler.formatName).assertEqual('Generic CSV');
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });

      it('shouldSniffZeroAlways', 0, () => {
        expect(handler.sniff(['Title', 'UserName'], [])).assertEqual(0);
        expect(handler.sniff(['foo'], [])).assertEqual(0);
      });
    });

    describe('import', () => {
      it('shouldImportStandardKeePassHeaders', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Generic Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Group,Title,UserName,Password,URL,Notes,TOTP,Tags,Icon,Last Modified,Created\n' +
          'Work/Sites,Site Entry,user,pass,https://example.com,a note,otpauth://totp/x?secret=ABC,"tag1,tag2",12,1700000000,2023-11-14T22:13:20Z';
        const fileContent = TestUtils.createFileContent(csvContent, 'generic.csv');

        const result = await handler.import(fileContent);

        // 分组 Work/Sites
        expect(result.groups.length).assertEqual(1);
        const workGroup = result.groups[0];
        expect(workGroup.name).assertEqual('Work');
        const sitesGroup = workGroup.groups[0];
        expect(sitesGroup.name).assertEqual('Sites');
        expect(sitesGroup.entries.length).assertEqual(1);

        const entry = sitesGroup.entries[0];
        expect(entry.fields.get('Title')).assertEqual('Site Entry');
        expect(entry.fields.get('UserName')).assertEqual('user');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass');
        expect(entry.fields.get('URL')).assertEqual('https://example.com');
        expect(entry.fields.get('Notes')).assertEqual('a note');
      });

      it('shouldImportTotpIntoOtpField', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Generic Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const otpUri = 'otpauth://totp/x?secret=ABC';
        const csvContent = `Title,TOTP\nTotp Entry,${otpUri}`;
        const fileContent = TestUtils.createFileContent(csvContent, 'generic.csv');

        const result = await handler.import(fileContent);
        expect(KdbxUtils.getFieldValueString(result.entries[0].fields, 'otp')).assertEqual(otpUri);
      });

      it('shouldParseTagsIconAndTimes', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Generic Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,Tags,Icon,Last Modified,Created\n' +
          'Full Entry,"tag1,tag2;tag3",12,1700000000,2023-11-14T22:13:20Z';
        const fileContent = TestUtils.createFileContent(csvContent, 'generic.csv');

        const result = await handler.import(fileContent);
        const entry = result.entries[0];

        // Tags：逗号/分号/Tab 分隔，去重排序
        expect(entry.tags.length).assertEqual(3);
        expect(entry.tags[0]).assertEqual('tag1');
        expect(entry.tags[1]).assertEqual('tag2');
        expect(entry.tags[2]).assertEqual('tag3');

        // Icon
        expect(entry.icon).assertEqual(12);

        // Last Modified：秒级 epoch ×1000；Created：ISO 日期
        expect(entry.times.lastModTime).not().assertUndefined();
        const modified = entry.times.lastModTime;
        if (modified !== undefined) {
          expect(modified.getTime()).assertEqual(1700000000000);
        }
        expect(entry.times.creationTime).not().assertUndefined();
        const created = entry.times.creationTime;
        if (created !== undefined) {
          expect(created.getTime()).assertEqual(1700000000000);
        }
      });

      it('shouldMapSynonymHeaders', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Generic Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Account,login,pwd,website,comment\n' +
          'My Account,myuser,mypass,https://my.com,my comment';
        const fileContent = TestUtils.createFileContent(csvContent, 'generic.csv');

        const result = await handler.import(fileContent);
        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('My Account');
        expect(entry.fields.get('UserName')).assertEqual('myuser');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('mypass');
        expect(entry.fields.get('URL')).assertEqual('https://my.com');
        expect(entry.fields.get('Notes')).assertEqual('my comment');
      });

      it('shouldFallbackTitleToUsernameWhenNoTitleAndUrl', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Generic Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'UserName,Password\nfallbackuser,pass';
        const fileContent = TestUtils.createFileContent(csvContent, 'generic.csv');

        const result = await handler.import(fileContent);
        expect(result.entries[0].fields.get('Title')).assertEqual('fallbackuser');
      });

      it('shouldFallbackTitleToLocalizedEntryNameWhenNothingAvailable', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Generic Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Notes\nonly a note';
        const fileContent = TestUtils.createFileContent(csvContent, 'generic.csv');

        const result = await handler.import(fileContent);
        const title = result.entries[0].fields.get('Title');
        expect(title).assertContain('1');
        expect(title !== '').assertTrue();
      });

      it('shouldThrowInvalidHeaderWhenNoColumnRecognized', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Generic Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'foo,bar\nx,y';
        const fileContent = TestUtils.createFileContent(csvContent, 'generic.csv');
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

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Generic Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'generic.csv');
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
    });
  });
}
