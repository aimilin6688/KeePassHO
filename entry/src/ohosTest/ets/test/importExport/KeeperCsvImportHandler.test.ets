import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { KeeperCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/KeeperCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * KeeperCsvImportHandler 单元测试
 * Keeper CSV 导出格式（报告 §三/§六 规格）：
 * 首列 record_type（login/card/address/bankAccount/...），login 行含
 * login_url,login_username,login_password,login_totp；folder→Group；note→Notes。
 * record_type 之后列按行类型偏移：非 login 行的 login_* 列值转入自定义字段
 * （原表头名作字段名）并清空标准字段，附 Record Type 自定义字段。
 */
export default function KeeperCsvImportHandlerTest() {
  describe('KeeperCsvImportHandler', () => {
    let handler: KeeperCsvImportHandler = new KeeperCsvImportHandler();

    beforeEach(() => {
      handler = new KeeperCsvImportHandler();
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
        expect(handler.formatId).assertEqual('KEEPER_CSV');
        expect(handler.formatName).assertEqual('Keeper CSV');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('sniff', () => {
      it('shouldDetectFullKeeperHeader', 0, () => {
        const header = ['record_type', 'folder', 'title', 'login_url',
          'login_username', 'login_password', 'login_totp', 'note'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldDetectMinimalKeeperHeader', 0, () => {
        const header = ['record_type', 'folder', 'title'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectWhenRecordTypeNotFirstColumn', 0, () => {
        // 首列为文档化特征；record_type 不在首列时不认领
        const header = ['folder', 'record_type', 'title', 'login_url',
          'login_username', 'login_password', 'login_totp', 'note'];
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
      it('shouldImportLoginRowWithAllFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Keeper CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'record_type,folder,title,login_url,login_username,login_password,login_totp,note\n' +
          'login,Social,GitHub,https://github.com,user1,pass1,JBSWY3DPEHPK3PXP,Code hosting';
        const fileContent = TestUtils.createFileContent(csvContent, 'keeper.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(0);
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Social');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(entry.fields.get('UserName')).assertEqual('user1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'otp')).assertEqual('key=JBSWY3DPEHPK3PXP');
        expect(entry.fields.get('Notes')).assertEqual('Code hosting');
      });

      it('shouldImportLoginRowWithoutFolderAtRoot', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Keeper CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'record_type,folder,title,login_url,login_username,login_password,login_totp,note\n' +
          'login,,GitHub,https://github.com,user1,pass1,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'keeper.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Title')).assertEqual('GitHub');
      });

      it('shouldImportOtpauthUriTotpRaw', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Keeper CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const otpauth = 'otpauth://totp/GitHub?secret=JBSWY3DPEHPK3PXP&issuer=GitHub';
        const csvContent = 'record_type,folder,title,login_url,login_username,login_password,login_totp,note\n' +
          'login,,GitHub,https://github.com,user1,pass1,' + otpauth + ',';
        const fileContent = TestUtils.createFileContent(csvContent, 'keeper.csv');

        const result = await handler.import(fileContent);

        expect(KdbxUtils.getFieldValueString(result.entries[0].fields, 'otp')).assertEqual(otpauth);
      });

      it('shouldImportCardRowWithShiftedColumnsAsCustomFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Keeper CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        // 非登录行：record_type 之后列按类型偏移（login_url 列位置此时为卡号等）
        const csvContent = 'record_type,folder,title,login_url,login_username,login_password,login_totp,note\n' +
          'card,Finance,My Card,4111111111111111,12/28,123,John Doe,Card note';
        const fileContent = TestUtils.createFileContent(csvContent, 'keeper.csv');

        const result = await handler.import(fileContent);

        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Finance');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('My Card');
        expect(entry.fields.get('Notes')).assertEqual('Card note');
        // 标准字段已清空（列偏移后的值不属于 URL/UserName/Password/otp）
        expect(entry.fields.get('URL')).assertEqual('');
        expect(entry.fields.get('UserName')).assertEqual('');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'otp')).assertEqual('');
        // 偏移列值按原表头名转入自定义字段（无损保留）
        expect(entry.fields.get('login_url')).assertEqual('4111111111111111');
        expect(entry.fields.get('login_username')).assertEqual('12/28');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'login_password')).assertEqual('123');
        expect(entry.fields.get('login_totp')).assertEqual('John Doe');
        // 记录类型标记
        expect(entry.fields.get('Record Type')).assertEqual('card');
      });

      it('shouldProtectShiftedPasswordColumnAsCustomField', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Keeper CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'record_type,folder,title,login_url,login_username,login_password,login_totp,note\n' +
          'bankAccount,Finance,Bank,,,,,Bank note';
        const fileContent = TestUtils.createFileContent(csvContent, 'keeper.csv');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Record Type')).assertEqual('bankAccount');
      });

      it('shouldTreatEmptyRecordTypeAsLogin', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Keeper CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'record_type,folder,title,login_url,login_username,login_password,login_totp,note\n' +
          ',Finance,GitHub,https://github.com,user1,pass1,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'keeper.csv');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(entry.fields.get('UserName')).assertEqual('user1');
        expect(entry.fields.get('Record Type')).assertUndefined();
      });

      it('shouldProtectPassword', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Keeper CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'record_type,folder,title,login_url,login_username,login_password,login_totp,note\n' +
          'login,,Site,https://s.com,user,secret,,';
        const fileContent = TestUtils.createFileContent(csvContent, 'keeper.csv');

        const result = await handler.import(fileContent);

        const passwordField = result.entries[0].fields.get('Password');
        expect(typeof passwordField !== 'string').assertTrue();
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Keeper CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'keeper.csv');
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
        const testDb = await TestUtils.createTestDatabase('Keeper CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'record_type,title,note\nlogin,GitHub,note';
        const fileContent = TestUtils.createFileContent(csvContent, 'keeper.csv');
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
