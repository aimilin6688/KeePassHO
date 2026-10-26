import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { BitwardenCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/BitwardenCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * BitwardenCsvImportHandler 单元测试
 * Bitwarden CSV 导出格式：folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
 */
export default function BitwardenCsvImportHandlerTest() {
  describe('BitwardenCsvImportHandler', () => {
    let handler: BitwardenCsvImportHandler = new BitwardenCsvImportHandler();

    beforeEach(() => {
      handler = new BitwardenCsvImportHandler();
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
        expect(handler.formatId).assertEqual('BITWARDEN_CSV');
        expect(handler.formatName).assertEqual('Bitwarden CSV');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('sniff', () => {
      it('shouldDetectFullBitwardenHeader', 0, () => {
        const header = ['folder', 'favorite', 'type', 'name', 'notes', 'fields', 'reprompt',
          'login_uri', 'login_username', 'login_password', 'login_totp'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldDetectMinimalBitwardenHeader', 0, () => {
        const header = ['type', 'name', 'login_uri', 'login_username', 'login_password'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectChromeHeader', 0, () => {
        const header = ['name', 'url', 'username', 'password', 'note'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectLastPassHeader', 0, () => {
        const header = ['url', 'username', 'password', 'extra', 'name', 'grouping', 'fav'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectRandomHeader', 0, () => {
        expect(handler.sniff(['foo', 'bar'], [])).assertEqual(0);
      });
    });

    describe('import', () => {
      it('shouldImportLoginEntryWithAllFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Bitwarden CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n' +
          'Social,1,1,GitHub,Code hosting,reprompt note,0,https://github.com,user1,pass1,JBSWY3DPEHPK3PXP';
        const fileContent = TestUtils.createFileContent(csvContent, 'bitwarden.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(0);
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Social');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(entry.fields.get('UserName')).assertEqual('user1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass1');
        expect(entry.fields.get('Notes')).assertEqual('Code hosting');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'otp')).assertEqual('key=JBSWY3DPEHPK3PXP');
      });

      it('shouldImportEntryWithoutFolderAtRoot', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Bitwarden CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n' +
          ',0,1,GitHub,, ,0,https://github.com,user1,pass1,';
        const fileContent = TestUtils.createFileContent(csvContent, 'bitwarden.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Title')).assertEqual('GitHub');
        expect(result.entries[0].tags.length).assertEqual(0);
      });

      it('shouldMarkFavoriteAsFavoriteTag', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Bitwarden CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n' +
          ',1,1,Site,, ,0,https://s.com,user,pass,';
        const fileContent = TestUtils.createFileContent(csvContent, 'bitwarden.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].tags.includes(KdbxUtils.FAVORITE_TAG)).assertTrue();
      });

      it('shouldSplitFieldsColumnIntoCustomFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Bitwarden CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n' +
          ',0,1,GitHub,,"Security Question: answer1; Recovery email: a@b.c",0,https://github.com,user1,pass1,';
        const fileContent = TestUtils.createFileContent(csvContent, 'bitwarden.csv');

        const result = await handler.import(fileContent);

        const entry = result.entries[0];
        expect(entry.fields.get('Security Question')).assertEqual('answer1');
        expect(entry.fields.get('Recovery email')).assertEqual('a@b.c');
      });

      it('shouldImportOtpauthUriTotpRaw', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Bitwarden CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const otpauth = 'otpauth://totp/GitHub:user1?secret=JBSWY3DPEHPK3PXP&issuer=GitHub';
        const csvContent = 'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n' +
          ',0,1,GitHub,, ,0,https://github.com,user1,pass1,' + otpauth;
        const fileContent = TestUtils.createFileContent(csvContent, 'bitwarden.csv');

        const result = await handler.import(fileContent);

        expect(KdbxUtils.getFieldValueString(result.entries[0].fields, 'otp')).assertEqual(otpauth);
      });

      it('shouldImportNoteTypeEntry', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Bitwarden CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n' +
          'Notes,0,2,My Note,note content,,0,,,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'bitwarden.csv');

        const result = await handler.import(fileContent);

        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Notes');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('My Note');
        expect(entry.fields.get('Notes')).assertEqual('note content');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('');
      });

      it('shouldProtectPassword', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Bitwarden CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n' +
          ',0,1,Site,, ,0,https://s.com,user,secret,';
        const fileContent = TestUtils.createFileContent(csvContent, 'bitwarden.csv');

        const result = await handler.import(fileContent);

        const passwordField = result.entries[0].fields.get('Password');
        expect(typeof passwordField !== 'string').assertTrue();
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Bitwarden CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'bitwarden.csv');
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
        const testDb = await TestUtils.createTestDatabase('Bitwarden CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'type,name,notes,login_username,login_password\n1,Site,,user,pass';
        const fileContent = TestUtils.createFileContent(csvContent, 'bitwarden.csv');
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
