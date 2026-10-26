import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { OnePasswordCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/OnePasswordCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * OnePasswordCsvImportHandler 单元测试
 * 1Password 8 CSV 导出格式：Title,Url,Username,Password,OTPAuth,Notes
 */
export default function OnePasswordCsvImportHandlerTest() {
  describe('OnePasswordCsvImportHandler', () => {
    let handler: OnePasswordCsvImportHandler = new OnePasswordCsvImportHandler();

    beforeEach(() => {
      handler = new OnePasswordCsvImportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptCsvExtension', 0, () => {
        expect(handler.canHandle('.csv')).assertTrue();
        expect(handler.canHandle('.CSV')).assertTrue();
      });

      it('shouldRejectNonCsvExtensions', 0, () => {
        expect(handler.canHandle('.json')).assertFalse();
        expect(handler.canHandle('.1pux')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('ONEPASSWORD_CSV');
        expect(handler.formatName).assertEqual('1Password CSV');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('sniff', () => {
      it('shouldDetectOnePasswordHeader', 0, () => {
        const header = ['Title', 'Url', 'Username', 'Password', 'OTPAuth', 'Notes'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectHeaderWithoutOtpAuthDistinguisher', 0, () => {
        // OTPAuth 为 1Password 8 特征列；无该列时不认领，避免误判含 Notes 的 KeePass 风格导出
        const header = ['Title', 'Url', 'Username', 'Password', 'Notes'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectDashlaneHeader', 0, () => {
        const header = ['title', 'url', 'username', 'password', 'note', 'category', 'otpSecret', 'lastModified'];
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
      it('shouldImportOnePasswordExport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('1Password CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,Url,Username,Password,OTPAuth,Notes\n' +
          'GitHub,https://github.com,user1,pass1,JBSWY3DPEHPK3PXP,My GitHub account';
        const fileContent = TestUtils.createFileContent(csvContent, '1password.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(entry.fields.get('UserName')).assertEqual('user1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'otp')).assertEqual('key=JBSWY3DPEHPK3PXP');
        expect(entry.fields.get('Notes')).assertEqual('My GitHub account');
      });

      it('shouldImportOtpauthUriTotpRaw', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('1Password CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const otpauth = 'otpauth://totp/GitHub?secret=JBSWY3DPEHPK3PXP&issuer=GitHub';
        const csvContent = 'Title,Url,Username,Password,OTPAuth,Notes\n' +
          'GitHub,https://github.com,user1,pass1,' + otpauth + ',';
        const fileContent = TestUtils.createFileContent(csvContent, '1password.csv');

        const result = await handler.import(fileContent);

        expect(KdbxUtils.getFieldValueString(result.entries[0].fields, 'otp')).assertEqual(otpauth);
      });

      it('shouldHandleMultilineQuotedNotes', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('1Password CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,Url,Username,Password,OTPAuth,Notes\n' +
          'Site,https://s.com,user,pass,,"line1\nline2"';
        const fileContent = TestUtils.createFileContent(csvContent, '1password.csv');

        const result = await handler.import(fileContent);

        expect(result.entries[0].fields.get('Notes')).assertEqual('line1\nline2');
      });

      it('shouldProtectPassword', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('1Password CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,Url,Username,Password,OTPAuth,Notes\nSite,https://s.com,user,secret,,';
        const fileContent = TestUtils.createFileContent(csvContent, '1password.csv');

        const result = await handler.import(fileContent);

        const passwordField = result.entries[0].fields.get('Password');
        expect(typeof passwordField !== 'string').assertTrue();
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('1Password CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', '1password.csv');
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
        const testDb = await TestUtils.createTestDatabase('1Password CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,Url,Username\nSite,https://s.com,user';
        const fileContent = TestUtils.createFileContent(csvContent, '1password.csv');
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
