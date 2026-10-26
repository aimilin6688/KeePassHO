import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { LastPassCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/LastPassCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * LastPassCsvImportHandler 单元测试
 * LastPass 导出格式：url,username,password,extra,name,grouping,fav[,totp]
 * - grouping 支持 '\'（KeePass LastPassCsv2 语义）与 '/' 两种嵌套分隔符
 * - extra 多行内容导入 Notes；totp 列导入 'otp' 字段（裸密钥转 key= 格式，otpauth 原样保留）
 * - fav 列 M1 忽略
 */
export default function LastPassCsvImportHandlerTest() {
  describe('LastPassCsvImportHandler', () => {
    let handler: LastPassCsvImportHandler = new LastPassCsvImportHandler();

    beforeEach(() => {
      handler = new LastPassCsvImportHandler();
    });

    describe('canHandleAndProperties', () => {
      it('shouldAcceptCsvExtension', 0, () => {
        expect(handler.canHandle('.csv')).assertTrue();
        expect(handler.canHandle('.xml')).assertFalse();
      });

      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('LASTPASS_CSV');
        expect(handler.formatName).assertEqual('LastPass CSV');
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('sniff', () => {
      it('shouldDetectLastPassHeader', 0, () => {
        const header = ['url', 'username', 'password', 'extra', 'name', 'grouping', 'fav'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldDetectLastPassHeaderWithTotp', 0, () => {
        const header = ['url', 'username', 'password', 'extra', 'name', 'grouping', 'fav', 'totp'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectChromeHeader', 0, () => {
        expect(handler.sniff(['name', 'url', 'username', 'password'], [])).assertEqual(0);
      });

      it('shouldRejectFirefoxHeader', 0, () => {
        const header = ['url', 'username', 'password', 'httpRealm', 'formActionOrigin', 'guid', 'timeCreated', 'timeLastUsed', 'timePasswordChanged'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });
    });

    describe('import', () => {
      it('shouldImportLastPassExport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('LastPass Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,extra,name,grouping,fav,totp\n' +
          'https://example.com,user3,pass3,"line1\nline2",ExampleEntry,Work\\Email,1,JBSWY3DPEHPK3PXP';
        const fileContent = TestUtils.createFileContent(csvContent, 'lastpass.csv');

        const result = await handler.import(fileContent);

        // 分组：Work\Email → Work/Email 嵌套
        expect(result.groups.length).assertEqual(1);
        const workGroup = result.groups[0];
        expect(workGroup.name).assertEqual('Work');
        expect(workGroup.groups.length).assertEqual(1);
        const emailGroup = workGroup.groups[0];
        expect(emailGroup.name).assertEqual('Email');
        expect(emailGroup.entries.length).assertEqual(1);

        const entry = emailGroup.entries[0];
        expect(entry.fields.get('Title')).assertEqual('ExampleEntry');
        expect(entry.fields.get('URL')).assertEqual('https://example.com');
        expect(entry.fields.get('UserName')).assertEqual('user3');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass3');
        expect(entry.fields.get('Notes')).assertEqual('line1\nline2');
      });

      it('shouldImportTotpSecretAsKeyFormat', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('LastPass Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,extra,name,grouping,fav,totp\n' +
          'https://example.com,user,pass,note,Entry,,,JBSWY3DPEHPK3PXP';
        const fileContent = TestUtils.createFileContent(csvContent, 'lastpass.csv');

        const result = await handler.import(fileContent);
        expect(KdbxUtils.getFieldValueString(result.entries[0].fields, 'otp')).assertEqual('key=JBSWY3DPEHPK3PXP');
      });

      it('shouldKeepOtpauthUriAsIs', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('LastPass Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const otpUri = 'otpauth://totp/Example?secret=ABCDEF&issuer=Example';
        const csvContent = 'url,username,password,extra,name,grouping,fav,totp\n' +
          `https://example.com,user,pass,note,Entry,,,${otpUri}`;
        const fileContent = TestUtils.createFileContent(csvContent, 'lastpass.csv');

        const result = await handler.import(fileContent);
        expect(KdbxUtils.getFieldValueString(result.entries[0].fields, 'otp')).assertEqual(otpUri);
      });

      it('shouldSupportSlashSeparatedGrouping', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('LastPass Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,extra,name,grouping,fav\n' +
          'https://example.com,user,pass,note,Entry,Work/Email,0';
        const fileContent = TestUtils.createFileContent(csvContent, 'lastpass.csv');

        const result = await handler.import(fileContent);
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Work');
        expect(result.groups[0].groups[0].name).assertEqual('Email');
      });

      it('shouldPlaceEntryInRootWhenGroupingEmpty', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('LastPass Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,extra,name,grouping,fav\n' +
          'https://example.com,user,pass,note,Entry,,0';
        const fileContent = TestUtils.createFileContent(csvContent, 'lastpass.csv');

        const result = await handler.import(fileContent);
        expect(result.groups.length).assertEqual(0);
        expect(result.entries.length).assertEqual(1);
      });

      it('shouldIgnoreFavColumn', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('LastPass Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,extra,name,grouping,fav\n' +
          'https://example.com,user,pass,note,Entry,,1';
        const fileContent = TestUtils.createFileContent(csvContent, 'lastpass.csv');

        const result = await handler.import(fileContent);
        expect(result.entries[0].tags.length).assertEqual(0);
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('LastPass Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'lastpass.csv');
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
        const testDb = await TestUtils.createTestDatabase('LastPass Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,extra,name\nhttps://example.com,user,pass,note,Entry';
        const fileContent = TestUtils.createFileContent(csvContent, 'lastpass.csv');
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
