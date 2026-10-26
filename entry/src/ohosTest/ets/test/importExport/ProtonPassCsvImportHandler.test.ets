import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { ProtonPassCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/ProtonPassCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * ProtonPassCsvImportHandler 单元测试
 * Proton Pass CSV 导出格式：name,url,email,username,password,totp,note[,vault]
 * email 语义（对齐 KeePassXC ProtonPassReader）：username 为空时作 UserName 兜底，否则入自定义字段
 */
export default function ProtonPassCsvImportHandlerTest() {
  describe('ProtonPassCsvImportHandler', () => {
    let handler: ProtonPassCsvImportHandler = new ProtonPassCsvImportHandler();

    beforeEach(() => {
      handler = new ProtonPassCsvImportHandler();
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
        expect(handler.formatId).assertEqual('PROTONPASS_CSV');
        expect(handler.formatName).assertEqual('Proton Pass CSV');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('sniff', () => {
      it('shouldDetectProtonHeaderWithVault', 0, () => {
        const header = ['name', 'url', 'email', 'username', 'password', 'totp', 'note', 'vault'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldDetectProtonHeaderWithoutVault', 0, () => {
        const header = ['name', 'url', 'email', 'username', 'password', 'totp', 'note'];
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
      it('shouldImportProtonExportWithVault', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,email,username,password,totp,note,vault\n' +
          'GitHub,https://github.com,user1@proton.me,user1,pass1,JBSWY3DPEHPK3PXP,My account,Personal';
        const fileContent = TestUtils.createFileContent(csvContent, 'proton.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(0);
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Personal');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(entry.fields.get('UserName')).assertEqual('user1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'otp')).assertEqual('key=JBSWY3DPEHPK3PXP');
        expect(entry.fields.get('Notes')).assertEqual('My account');
        expect(entry.fields.get('Email')).assertEqual('user1@proton.me');
      });

      it('shouldFallbackEmailToUsernameWhenUsernameEmpty', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,email,username,password,totp,note,vault\n' +
          'GitHub,https://github.com,user1@proton.me,,pass1,,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'proton.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.fields.get('UserName')).assertEqual('user1@proton.me');
        expect(entry.fields.get('Email')).assertUndefined();
      });

      it('shouldKeepEmailAsCustomFieldWhenUsernamePresent', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,email,username,password,totp,note,vault\n' +
          'GitHub,https://github.com,user1@proton.me,user1,pass1,,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'proton.csv');

        const result = await handler.import(fileContent);

        expect(result.entries[0].fields.get('UserName')).assertEqual('user1');
        expect(result.entries[0].fields.get('Email')).assertEqual('user1@proton.me');
      });

      it('shouldImportEntryWithoutVaultAtRoot', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,email,username,password,totp,note\n' +
          'Site,https://s.com,user,pass,,,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'proton.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Title')).assertEqual('Site');
      });

      it('shouldImportOtpauthUriTotpRaw', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const otpauth = 'otpauth://totp/GitHub?secret=JBSWY3DPEHPK3PXP&issuer=GitHub';
        const csvContent = 'name,url,email,username,password,totp,note,vault\n' +
          'GitHub,https://github.com,user1@proton.me,user1,pass1,' + otpauth + ',,';
        const fileContent = TestUtils.createFileContent(csvContent, 'proton.csv');

        const result = await handler.import(fileContent);

        expect(KdbxUtils.getFieldValueString(result.entries[0].fields, 'otp')).assertEqual(otpauth);
      });

      it('shouldProtectPassword', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,email,username,password,totp,note\n' +
          'Site,https://s.com,user,secret,,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'proton.csv');

        const result = await handler.import(fileContent);

        const passwordField = result.entries[0].fields.get('Password');
        expect(typeof passwordField !== 'string').assertTrue();
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'proton.csv');
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
        const testDb = await TestUtils.createTestDatabase('Proton Pass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username\nSite,https://s.com,user';
        const fileContent = TestUtils.createFileContent(csvContent, 'proton.csv');
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
