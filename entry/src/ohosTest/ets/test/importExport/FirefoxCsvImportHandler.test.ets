import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { FirefoxCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/FirefoxCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * FirefoxCsvImportHandler 单元测试
 * Firefox about:logins 导出格式：
 * url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged
 * 时间列为微秒级 epoch（兼容秒/毫秒级输入）
 */
export default function FirefoxCsvImportHandlerTest() {
  describe('FirefoxCsvImportHandler', () => {
    let handler: FirefoxCsvImportHandler = new FirefoxCsvImportHandler();

    beforeEach(() => {
      handler = new FirefoxCsvImportHandler();
    });

    describe('canHandleAndProperties', () => {
      it('shouldAcceptCsvExtension', 0, () => {
        expect(handler.canHandle('.csv')).assertTrue();
        expect(handler.canHandle('.xml')).assertFalse();
      });

      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('FIREFOX_CSV');
        expect(handler.formatName).assertEqual('Firefox CSV');
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('sniff', () => {
      it('shouldDetectFirefoxHeader', 0, () => {
        const header = ['url', 'username', 'password', 'httpRealm', 'formActionOrigin', 'guid', 'timeCreated', 'timeLastUsed', 'timePasswordChanged'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldDetectFirefoxHeaderWithoutRealm', 0, () => {
        const header = ['url', 'username', 'password', 'formActionOrigin', 'guid', 'timeCreated', 'timeLastUsed', 'timePasswordChanged'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectChromeHeader', 0, () => {
        expect(handler.sniff(['name', 'url', 'username', 'password'], [])).assertEqual(0);
      });

      it('shouldRejectPlainUrlUsernamePasswordHeader', 0, () => {
        // 无 Firefox 特征列（httpRealm/guid/timePasswordChanged 等）时不认领，交由通用 CSV
        expect(handler.sniff(['url', 'username', 'password'], [])).assertEqual(0);
      });
    });

    describe('import', () => {
      it('shouldImportFirefoxExport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Firefox Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged\n' +
          'https://example.com,user2,pass2,ExampleRealm,https://example.com,{guid1},1539152037000000,1539152040000000,1539152050000000';
        const fileContent = TestUtils.createFileContent(csvContent, 'firefox.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.fields.get('URL')).assertEqual('https://example.com');
        expect(entry.fields.get('UserName')).assertEqual('user2');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass2');
        expect(entry.fields.get('Notes')).assertEqual('ExampleRealm');
      });

      it('shouldUseHostnameAsFallbackTitle', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Firefox Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged\n' +
          'https://example.com/user2,ffuser,ffpass,,https://example.com,{guid2},1539152037000000,1539152037000000,1539152037000000';
        const fileContent = TestUtils.createFileContent(csvContent, 'firefox.csv');

        const result = await handler.import(fileContent);
        expect(result.entries[0].fields.get('Title')).assertEqual('example.com');
      });

      it('shouldParseMicrosecondTimestamps', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Firefox Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged\n' +
          'https://example.com,user,pass,,https://example.com,{guid3},1539152037000000,1539152040000000,1539152050000000';
        const fileContent = TestUtils.createFileContent(csvContent, 'firefox.csv');

        const result = await handler.import(fileContent);
        const entry = result.entries[0];
        expect(entry.times.creationTime).not().assertUndefined();
        const created = entry.times.creationTime;
        if (created !== undefined) {
          expect(created.getTime()).assertEqual(1539152037000);
        }
        expect(entry.times.lastModTime).not().assertUndefined();
        const modified = entry.times.lastModTime;
        if (modified !== undefined) {
          expect(modified.getTime()).assertEqual(1539152050000);
        }
      });

      it('shouldParseSecondTimestamps', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Firefox Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged\n' +
          'https://example.com,user,pass,,https://example.com,{guid4},1700000000,1700000000,1700000000';
        const fileContent = TestUtils.createFileContent(csvContent, 'firefox.csv');

        const result = await handler.import(fileContent);
        const created = result.entries[0].times.creationTime;
        if (created !== undefined) {
          expect(created.getTime()).assertEqual(1700000000000);
        }
      });

      it('shouldKeepNotesEmptyWhenHttpRealmEmpty', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Firefox Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged\n' +
          'https://example.com,user,pass,,https://example.com,{guid5},0,0,0';
        const fileContent = TestUtils.createFileContent(csvContent, 'firefox.csv');

        const result = await handler.import(fileContent);
        expect(result.entries[0].fields.get('Notes')).assertEqual('');
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Firefox Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'firefox.csv');
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
        const testDb = await TestUtils.createTestDatabase('Firefox Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username\nhttps://example.com,user';
        const fileContent = TestUtils.createFileContent(csvContent, 'firefox.csv');
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
