import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { DashlaneCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/DashlaneCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * DashlaneCsvImportHandler 单元测试
 * Dashlane 6+ CSV 导出格式：title,url,username,password,note,category,otpSecret,lastModified
 */
export default function DashlaneCsvImportHandlerTest() {
  describe('DashlaneCsvImportHandler', () => {
    let handler: DashlaneCsvImportHandler = new DashlaneCsvImportHandler();

    beforeEach(() => {
      handler = new DashlaneCsvImportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptCsvExtension', 0, () => {
        expect(handler.canHandle('.csv')).assertTrue();
        expect(handler.canHandle('.CSV')).assertTrue();
      });

      it('shouldRejectNonCsvExtensions', 0, () => {
        expect(handler.canHandle('.json')).assertFalse();
        expect(handler.canHandle('.xml')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('DASHLANE_CSV');
        expect(handler.formatName).assertEqual('Dashlane CSV');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('sniff', () => {
      it('shouldDetectDashlaneHeader', 0, () => {
        const header = ['title', 'url', 'username', 'password', 'note', 'category', 'otpSecret', 'lastModified'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldDetectMinimalHeaderWithDistinguisher', 0, () => {
        const header = ['title', 'url', 'username', 'password', 'lastModified'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectKeePassStyleExportWithLastModified', 0, () => {
        // 本应用/KeePass 风格导出含 Last Modified + Group/Notes，不得被 Dashlane 认领（否则丢列）
        const header = ['Group', 'Title', 'UserName', 'Password', 'URL', 'Notes', 'TOTP', 'Icon', 'Last Modified'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectOnePasswordHeader', 0, () => {
        const header = ['Title', 'Url', 'Username', 'Password', 'OTPAuth', 'Notes'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectChromeHeader', 0, () => {
        const header = ['name', 'url', 'username', 'password', 'note'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectRandomHeader', 0, () => {
        expect(handler.sniff(['foo', 'bar'], [])).assertEqual(0);
      });
    });

    describe('import', () => {
      it('shouldImportDashlaneExportWithAllFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dashlane CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'title,url,username,password,note,category,otpSecret,lastModified\n' +
          'GitHub,https://github.com,user1,pass1,My account,Dev,JBSWY3DPEHPK3PXP,1660000000';
        const fileContent = TestUtils.createFileContent(csvContent, 'dashlane.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(0);
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Dev');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(entry.fields.get('UserName')).assertEqual('user1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass1');
        expect(entry.fields.get('Notes')).assertEqual('My account');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'otp')).assertEqual('key=JBSWY3DPEHPK3PXP');
      });

      it('shouldParseLastModifiedAsSecondsTimestamp', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dashlane CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'title,url,username,password,note,category,otpSecret,lastModified\n' +
          'GitHub,https://github.com,user1,pass1,,Dev,,1660000000';
        const fileContent = TestUtils.createFileContent(csvContent, 'dashlane.csv');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.times.lastModTime).not().assertUndefined();
        const modified = entry.times.lastModTime;
        if (modified) {
          expect(modified.getTime()).assertEqual(1660000000000);
        }
        expect(entry.times.lastAccessTime).not().assertUndefined();
      });

      it('shouldImportEntryWithoutCategoryAtRoot', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dashlane CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'title,url,username,password,note,category,otpSecret,lastModified\n' +
          'Site,https://s.com,user,pass,,,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'dashlane.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Title')).assertEqual('Site');
      });

      it('shouldProtectPassword', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dashlane CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'title,url,username,password,note,category,otpSecret,lastModified\n' +
          'Site,https://s.com,user,secret,,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'dashlane.csv');

        const result = await handler.import(fileContent);

        const passwordField = result.entries[0].fields.get('Password');
        expect(typeof passwordField !== 'string').assertTrue();
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dashlane CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'dashlane.csv');
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
        const testDb = await TestUtils.createTestDatabase('Dashlane CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'title,username,password,note,category\nSite,user,pass,note,cat';
        const fileContent = TestUtils.createFileContent(csvContent, 'dashlane.csv');
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
