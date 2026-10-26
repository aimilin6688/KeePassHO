import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { CsvFamilyDispatcherImportHandler } from '../../../../main/ets/services/importExport/handlers/import/CsvFamilyDispatcherImportHandler';
import { registerDefaultHandlers, FormatHandlerRegistry } from '../../../../main/ets/services/importExport/index';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * CsvFamilyDispatcherImportHandler 单元测试
 * CSV 导入族调度器（组合根以 formatId 'CSV' 占据 .csv 路由键）：
 * 1. 按表头嗅探分发到 Chrome/Firefox/LastPass/通用 CSV
 * 2. 注册后 '.csv' 与 'CSV' 键均解析到调度器
 */
export default function CsvFamilyDispatcherTest() {
  describe('CsvFamilyDispatcherImportHandler', () => {
    let dispatcher: CsvFamilyDispatcherImportHandler = new CsvFamilyDispatcherImportHandler();

    beforeEach(() => {
      dispatcher = new CsvFamilyDispatcherImportHandler();
    });

    describe('canHandleAndProperties', () => {
      it('shouldAcceptCsvExtension', 0, () => {
        expect(dispatcher.canHandle('.csv')).assertTrue();
        expect(dispatcher.canHandle('.CSV')).assertTrue();
        expect(dispatcher.canHandle('.xml')).assertFalse();
      });

      it('shouldOccupyCsvRouteKey', 0, () => {
        expect(dispatcher.formatId).assertEqual('CSV');
        expect(dispatcher.formatName).assertEqual('CSV');
        expect(dispatcher.supportedExtensions.length).assertEqual(1);
        expect(dispatcher.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('detectFormatId', () => {
      it('shouldDetectChromeFormat', 0, () => {
        const header = ['name', 'url', 'username', 'password', 'note'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('CHROME_CSV');
      });

      it('shouldDetectFirefoxFormat', 0, () => {
        const header = ['url', 'username', 'password', 'httpRealm', 'formActionOrigin', 'guid', 'timeCreated', 'timeLastUsed', 'timePasswordChanged'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('FIREFOX_CSV');
      });

      it('shouldDetectLastPassFormat', 0, () => {
        const header = ['url', 'username', 'password', 'extra', 'name', 'grouping', 'fav'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('LASTPASS_CSV');
      });

      it('shouldDetectBitwardenFormat', 0, () => {
        const header = ['folder', 'favorite', 'type', 'name', 'notes', 'fields', 'reprompt',
          'login_uri', 'login_username', 'login_password', 'login_totp'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('BITWARDEN_CSV');
      });

      it('shouldDetectProtonPassFormat', 0, () => {
        const header = ['name', 'url', 'username', 'password', 'note', 'totp', 'email', 'vault'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('PROTONPASS_CSV');
      });

      it('shouldPreferProtonPassOverChromeForChromeSupersetHeader', 0, () => {
        // §4.5：Chrome 表头 + Proton 特征列（totp/vault/email）的超集须判为 Proton Pass，而非 Chrome
        const header = ['name', 'url', 'username', 'password', 'note', 'totp', 'vault'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('PROTONPASS_CSV');
      });

      it('shouldDetectDashlaneFormat', 0, () => {
        const header = ['title', 'url', 'username', 'password', 'note', 'category', 'otpSecret', 'lastModified'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('DASHLANE_CSV');
      });

      it('shouldDetectOnePasswordFormat', 0, () => {
        const header = ['Title', 'Url', 'Username', 'Password', 'OTPAuth', 'Notes'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('ONEPASSWORD_CSV');
      });

      it('shouldPreferDashlaneOverOnePasswordForDashlaneHeader', 0, () => {
        // Dashlane 与 1Password 均满足 title/url/username/password，靠特征列消歧
        const dashlaneHeader = ['title', 'url', 'username', 'password', 'note', 'category', 'otpSecret', 'lastModified'];
        expect(dispatcher.detectFormatId(dashlaneHeader, [])).assertEqual('DASHLANE_CSV');
        const onePasswordHeader = ['Title', 'Url', 'Username', 'Password', 'OTPAuth', 'Notes'];
        expect(dispatcher.detectFormatId(onePasswordHeader, [])).assertEqual('ONEPASSWORD_CSV');
      });

      it('shouldFallBackToGenericForUnknownHeader', 0, () => {
        expect(dispatcher.detectFormatId(['foo', 'bar'], [])).assertEqual('GENERIC_CSV');
      });

      it('shouldFallBackToGenericForKeePassStyleHeader', 0, () => {
        const header = ['Group', 'Title', 'UserName', 'Password', 'URL', 'Notes'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('GENERIC_CSV');
      });

      it('shouldFallBackToGenericForAppExportHeaderWithLastModified', 0, () => {
        // 本应用 CSV 导出表头含 Last Modified，须仍走通用 CSV（Dashlane 不得误认领）
        const header = ['Group', 'Title', 'UserName', 'Password', 'URL', 'Notes', 'TOTP', 'Icon', 'Last Modified'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('GENERIC_CSV');
      });

      it('shouldNotClaimPlainUrlUsernamePasswordHeader', 0, () => {
        // 仅 url/username/password 无 Firefox 特征列时不误判为 Firefox，走通用 CSV
        expect(dispatcher.detectFormatId(['url', 'username', 'password'], [])).assertEqual('GENERIC_CSV');
      });
    });

    describe('importDispatch', () => {
      it('shouldDispatchToChromeHandler', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username,password,note\n' +
          'GitHub,https://github.com,dispuser,disppass,chrome note';
        const fileContent = TestUtils.createFileContent(csvContent, 'dispatch.csv');

        const result = await dispatcher.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        // Chrome 语义：name → Title
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('Notes')).assertEqual('chrome note');
      });

      it('shouldDispatchToFirefoxHandler', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged\n' +
          'https://example.com,ffuser,ffpass,Realm,https://example.com,{g},1539152037000000,1539152037000000,1539152037000000';
        const fileContent = TestUtils.createFileContent(csvContent, 'dispatch.csv');

        const result = await dispatcher.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        // Firefox 语义：无 name 列，Title 兜底为 URL 域名
        expect(entry.fields.get('Title')).assertEqual('example.com');
        expect(entry.fields.get('Notes')).assertEqual('Realm');
      });

      it('shouldDispatchToLastPassHandler', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,extra,name,grouping,fav\n' +
          'https://example.com,lpuser,lppass,lp extra,LP Entry,Social,0';
        const fileContent = TestUtils.createFileContent(csvContent, 'dispatch.csv');

        const result = await dispatcher.import(fileContent);

        // LastPass 语义：grouping → 分组
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Social');
        expect(result.groups[0].entries.length).assertEqual(1);
        expect(result.groups[0].entries[0].fields.get('Title')).assertEqual('LP Entry');
      });

      it('shouldDispatchToGenericHandlerForKeePassStyleCsv', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'Group,Title,UserName,Password\n' +
          'Work,Generic Entry,genuser,genpass';
        const fileContent = TestUtils.createFileContent(csvContent, 'dispatch.csv');

        const result = await dispatcher.import(fileContent);

        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Work');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('Generic Entry');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('genpass');
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'dispatch.csv');
        try {
          await dispatcher.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.FILE_EMPTY);
          }
        }
      });
    });

    describe('registryIntegration', () => {
      it('shouldRegisterDispatcherForCsvRouteKey', 0, () => {
        registerDefaultHandlers();
        const registry = FormatHandlerRegistry.getInstance();

        const byExtension = registry.getImportHandler('.csv');
        expect(byExtension).not().assertUndefined();
        expect(byExtension?.formatId).assertEqual('CSV');
        expect(byExtension instanceof CsvFamilyDispatcherImportHandler).assertTrue();

        const byFormatId = registry.getImportHandler('CSV');
        expect(byFormatId).not().assertUndefined();
        expect(byFormatId?.formatId).assertEqual('CSV');
      });
    });
  });
}
