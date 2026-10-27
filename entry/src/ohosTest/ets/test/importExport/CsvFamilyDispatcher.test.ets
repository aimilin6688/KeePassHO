import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { CsvFamilyDispatcherImportHandler } from '../../../../main/ets/services/importExport/handlers/import/CsvFamilyDispatcherImportHandler';
import { registerDefaultHandlers, FormatHandlerRegistry } from '../../../../main/ets/services/importExport/index';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { ImportWizardBridge } from '../../../../main/ets/services/importExport/wizard/ImportWizardBridge';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * 纯 ASCII 字符串转字节数组（与 GBK 双字节拼接构造非 UTF-8 内容）
 */
function asciiBytes(text: string): number[] {
  const result: number[] = [];
  for (let i = 0; i < text.length; i++) {
    result.push(text.charCodeAt(i));
  }
  return result;
}

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

      it('shouldDetectKeeperFormat', 0, () => {
        const header = ['record_type', 'folder', 'title', 'login_url',
          'login_username', 'login_password', 'login_totp', 'note'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('KEEPER_CSV');
      });

      it('shouldDetectEnpassFormat', 0, () => {
        const header = ['Title', 'Category', 'Note', 'Login', 'Password', 'OTP Secret', 'URL', 'Email'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('ENPASS_CSV');
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

      it('shouldClaimKnownFormatWithUnrecognizableExtraColumn', 0, () => {
        // 完全不可识别的未知列 → 参考 KeePass 2.x 语义：格式认领，未知列忽略
        const header = ['name', 'url', 'username', 'password', 'note', 'extra'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('CHROME_CSV');
      });

      it('shouldFallBackToGenericWhenKnownFormatHasRecognizableExtraColumn', 0, () => {
        // 可识别的未知列（可映射标准字段，数据不能丢）→ 不认领 → 列映射向导
        const header = ['name', 'url', 'username', 'password', 'note', 'GROUP中文'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('GENERIC_CSV');
      });

      it('shouldFallBackToGenericWhenKnownFormatMissesRequiredColumn', 0, () => {
        // Chrome 必需列 name 缺失，其余格式必需列/特征列也均不齐 → 不认领 → 列映射向导/通用 CSV
        const header = ['url', 'username', 'password', 'note'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('GENERIC_CSV');
      });

      it('shouldFallBackToGenericForChineseAnnotatedHeader', 0, () => {
        // 「GROUP中文,TITLE中文,…」等带注释表头：无解析器精准命中 → 列映射向导（此处无 UI 回落通用）
        const header = ['GROUP中文', 'TITLE中文', 'USERNAME用户名', 'PASSWORD密码', 'URL网址', 'NOTES备注'];
        expect(dispatcher.detectFormatId(header, [])).assertEqual('GENERIC_CSV');
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

    describe('gbkImportDispatch', () => {
      it('shouldImportGbkEncodedChromeCsv', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        // Chrome 表头（ASCII）+ GBK 中文数据：'用户'（D3C3 BBA7）'密码'（C3DC C2EB）'备注'（B1B8 D7A2）
        const bytes = new Uint8Array(
          asciiBytes('name,url,username,password,note\nGitHub,https://github.com,')
            .concat([0xD3, 0xC3, 0xBB, 0xA7, 0x2C])
            .concat([0xC3, 0xDC, 0xC2, 0xEB, 0x2C])
            .concat([0xB1, 0xB8, 0xD7, 0xA2])
        );
        const fileContent = TestUtils.createFileContentFromBytes(bytes, 'gbk-chrome.csv');

        const result = await dispatcher.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('UserName')).assertEqual('用户');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('密码');
        expect(entry.fields.get('Notes')).assertEqual('备注');
      });

      it('shouldImportGbkEncodedGenericCsvWithChineseGroupTitle', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        // KeePass 风格表头（ASCII）+ GBK 中文数据：'工作'（B9A4 D7F7）'中文条目'（D6D0 CEC4 CCF5 C4BF）'用户' '密码'
        const bytes = new Uint8Array(
          asciiBytes('Group,Title,UserName,Password\n')
            .concat([0xB9, 0xA4, 0xD7, 0xF7, 0x2C]) // 工作
            .concat([0xD6, 0xD0, 0xCE, 0xC4, 0xCC, 0xF5, 0xC4, 0xBF, 0x2C]) // 中文条目
            .concat([0xD3, 0xC3, 0xBB, 0xA7, 0x2C]) // 用户
            .concat([0xC3, 0xDC, 0xC2, 0xEB]) // 密码
        );
        const fileContent = TestUtils.createFileContentFromBytes(bytes, 'gbk-generic.csv');

        const result = await dispatcher.import(fileContent);

        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('工作');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('中文条目');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('密码');
      });

      it('shouldReportDetectedEncodingInPreviewSource', 0, () => {
        // 调度器构建的预览须携带原始字节与检测编码，供向导切换编码重解码
        const preview = ImportWizardBridge.buildPreview(
          [['name', 'url'], ['GitHub', 'https://github.com']],
          'Chrome',
          TestUtils.createFileContent('name,url\nGitHub,https://github.com', 'sample.csv').content,
          'gbk'
        );
        expect(preview.detectedEncoding).assertEqual('gbk');
        expect(preview.sourceContent.byteLength > 0).assertTrue();
      });
    });

    describe('annotatedHeaderImport', () => {
      it('shouldImportChineseAnnotatedHeadersViaSuggestedMapping', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        // 用户场景：带中文注释表头，无解析器认领 → 无 UI 上下文回落通用建议映射直导；
        // 建议映射由引擎阶段②前缀匹配生成（GROUP分组/TITLE中文/USERNAME用户名/…）
        const csvContent = 'GROUP分组,TITLE中文,USERNAME用户名,PASSWORD密码,URL网址,NOTES备注\n' +
          '工作,中文条目,注释用户,注释密码,https://example.com,中文备注';
        const fileContent = TestUtils.createFileContent(csvContent, 'annotated.csv');

        const result = await dispatcher.import(fileContent);

        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('工作');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('中文条目');
        expect(entry.fields.get('UserName')).assertEqual('注释用户');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('注释密码');
        expect(entry.fields.get('URL')).assertEqual('https://example.com');
        expect(entry.fields.get('Notes')).assertEqual('中文备注');
      });

      it('shouldKeepEnglishNameAndAnnotatedUsernameDisambiguated', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        // 阶段②消歧：'USERNAME用户名'（命中 8 字符）优先于 'NAME名称'（命中 4 字符）作 UserName
        const csvContent = 'NAME名称,USERNAME用户名,PASSWORD密码\n' +
          '名称列值,用户名列值,密码值';
        const fileContent = TestUtils.createFileContent(csvContent, 'disambiguation.csv');

        const result = await dispatcher.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.fields.get('UserName')).assertEqual('用户名列值');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('密码值');
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
