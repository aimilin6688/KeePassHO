import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { EnpassCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/EnpassCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * EnpassCsvImportHandler 单元测试
 * Enpass 6 CSV 导出格式（报告 §三/§六 规格）：
 * 首列 "Title","Category"（约 40 个固定列），按列名而非位置映射：
 * Title / Category→Group / Login→UserName / Password / OTP Secret→TOTP / URL / Note；
 * 其余非空列（Email/Phone/Card No/...）→ 自定义字段（password/cvv/ssn/pin 类受保护）。
 */
export default function EnpassCsvImportHandlerTest() {
  describe('EnpassCsvImportHandler', () => {
    let handler: EnpassCsvImportHandler = new EnpassCsvImportHandler();

    beforeEach(() => {
      handler = new EnpassCsvImportHandler();
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
        expect(handler.formatId).assertEqual('ENPASS_CSV');
        expect(handler.formatName).assertEqual('Enpass CSV');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('sniff', () => {
      it('shouldDetectEnpassHeader', 0, () => {
        // 约 40 个固定列的代表性前缀（首列 Title、次列 Category 为文档化特征）
        const header = ['Title', 'Category', 'Note', 'Login', 'Password', 'OTP Secret', 'URL',
          'Email', 'Phone', 'Card No', 'CC Cvv', 'Expiry Date', 'Bank Name', 'SSN', 'Group'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectChromeHeader', 0, () => {
        const header = ['name', 'url', 'username', 'password', 'note'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectDashlaneHeader', 0, () => {
        // Dashlane 首列为 title，但次列是 url 而非 category
        const header = ['title', 'url', 'username', 'password', 'note', 'category', 'otpSecret', 'lastModified'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectKeePassStyleHeader', 0, () => {
        const header = ['Group', 'Title', 'UserName', 'Password', 'URL', 'Notes'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectRandomHeader', 0, () => {
        expect(handler.sniff(['foo', 'bar'], [])).assertEqual(0);
      });
    });

    describe('import', () => {
      it('shouldImportLoginRecord', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Enpass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,Category,Note,Login,Password,OTP Secret,URL,Email,Phone,Card No,CC Cvv,Group\n' +
          'GitHub,Logins,My note,user1,pass1,JBSWY3DPEHPK3PXP,https://github.com,me@x.com,,,,WrongGroup';
        const fileContent = TestUtils.createFileContent(csvContent, 'enpass.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(0);
        expect(result.groups.length).assertEqual(1);
        // Category→Group；字面 Group 列不得抢分组映射
        expect(result.groups[0].name).assertEqual('Logins');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('UserName')).assertEqual('user1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass1');
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(entry.fields.get('Notes')).assertEqual('My note');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'otp')).assertEqual('key=JBSWY3DPEHPK3PXP');
        // 非映射列 → 自定义字段
        expect(entry.fields.get('Email')).assertEqual('me@x.com');
        expect(entry.fields.get('Group')).assertEqual('WrongGroup');
        // 空列不产生空自定义字段
        expect(entry.fields.get('Phone')).assertUndefined();
      });

      it('shouldImportCardRecordWithCustomFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Enpass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,Category,Note,Login,Password,OTP Secret,URL,Email,Phone,Card No,CC Cvv,Group\n' +
          'My Card,Cards,Card note,,,,,me@x.com,,4111111111111111,123,';
        const fileContent = TestUtils.createFileContent(csvContent, 'enpass.csv');

        const result = await handler.import(fileContent);

        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Cards');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('My Card');
        expect(entry.fields.get('Notes')).assertEqual('Card note');
        expect(entry.fields.get('Card No')).assertEqual('4111111111111111');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'CC Cvv')).assertEqual('123');
        expect(entry.fields.get('Email')).assertEqual('me@x.com');
        // cvv 类敏感列受保护
        const cvvField = entry.fields.get('CC Cvv');
        expect(typeof cvvField !== 'string').assertTrue();
      });

      it('shouldProtectPassword', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Enpass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,Category,Note,Login,Password,OTP Secret,URL,Email,Phone,Card No,CC Cvv,Group\n' +
          'Site,Logins,,user,secret,,,,,,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'enpass.csv');

        const result = await handler.import(fileContent);

        const passwordField = result.groups[0].entries[0].fields.get('Password');
        expect(typeof passwordField !== 'string').assertTrue();
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Enpass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'enpass.csv');
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

      it('shouldThrowInvalidHeaderWhenCategoryMissing', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Enpass CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Title,Note,Login,Password,URL\nSite,note,user,pass,https://s.com';
        const fileContent = TestUtils.createFileContent(csvContent, 'enpass.csv');
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
