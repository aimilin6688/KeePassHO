import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { ChromeCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/ChromeCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * ChromeCsvImportHandler 单元测试
 * Chrome/Edge/Brave/Opera/Vivaldi 导出格式：name,url,username,password[,note]
 */
export default function ChromeCsvImportHandlerTest() {
  describe('ChromeCsvImportHandler', () => {
    let handler: ChromeCsvImportHandler = new ChromeCsvImportHandler();

    beforeEach(() => {
      handler = new ChromeCsvImportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptCsvExtension', 0, () => {
        expect(handler.canHandle('.csv')).assertTrue();
      });

      it('shouldBeCaseInsensitive', 0, () => {
        expect(handler.canHandle('.CSV')).assertTrue();
      });

      it('shouldRejectNonCsvExtensions', 0, () => {
        expect(handler.canHandle('.xml')).assertFalse();
        expect(handler.canHandle('.json')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('CHROME_CSV');
        expect(handler.formatName).assertEqual('Chrome CSV');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('sniff', () => {
      it('shouldDetectChromeHeader', 0, () => {
        const header = ['name', 'url', 'username', 'password', 'note'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldDetectChromeHeaderWithoutNote', 0, () => {
        const header = ['name', 'url', 'username', 'password'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectFirefoxHeader', 0, () => {
        const header = ['url', 'username', 'password', 'httpRealm', 'formActionOrigin', 'guid', 'timeCreated', 'timeLastUsed', 'timePasswordChanged'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectRandomHeader', 0, () => {
        expect(handler.sniff(['foo', 'bar'], [])).assertEqual(0);
      });
    });

    describe('import', () => {
      it('shouldImportChromeExport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username,password,note\n' +
          'GitHub,https://github.com,user1,pass1,Saved by Chrome';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(entry.fields.get('UserName')).assertEqual('user1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass1');
        expect(entry.fields.get('Notes')).assertEqual('Saved by Chrome');
      });

      it('shouldImportMultipleEntries', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username,password\n' +
          'Site A,https://a.com,usera,passa\n' +
          'Site B,https://b.com,userb,passb';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');

        const result = await handler.import(fileContent);
        expect(result.entries.length).assertEqual(2);
        expect(result.entries[0].fields.get('Title')).assertEqual('Site A');
        expect(result.entries[1].fields.get('Title')).assertEqual('Site B');
      });

      it('shouldHandleMultilineQuotedNote', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username,password,note\n' +
          'Site,https://s.com,user,pass,"line1\nline2"';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');

        const result = await handler.import(fileContent);
        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Notes')).assertEqual('line1\nline2');
      });

      it('shouldProtectPassword', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username,password\nSite,https://s.com,user,secret';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');

        const result = await handler.import(fileContent);
        const passwordField = result.entries[0].fields.get('Password');
        expect(typeof passwordField !== 'string').assertTrue();
        expect(KdbxUtils.getFieldValueString(result.entries[0].fields, 'Password')).assertEqual('secret');
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'chrome.csv');
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

      it('shouldThrowInvalidHeaderWhenRequiredColumnMissing', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,username,password\nSite,user,pass';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');
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
    });
  });
}
