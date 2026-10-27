import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { FormatSignatureLibrary } from '../../../../main/ets/services/importExport/sniffing/FormatSignatureLibrary';
import { PresetCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/PresetCsvImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * 按格式标识构造签名驱动 handler（签名缺失时抛错使测试失败）
 */
function buildPresetHandler(formatId: string): PresetCsvImportHandler {
  const signature = FormatSignatureLibrary.getSignature(formatId);
  if (signature === null) {
    throw new Error(`signature not found: ${formatId}`);
  }
  return new PresetCsvImportHandler(signature);
}

/**
 * 纯数据格式签名折叠统一测试（原 Chrome/Firefox/LastPass/Dashlane/1Password 5 个独立 handler 测试整合）
 * 统一由 FormatSignatureLibrary 签名 + PresetCsvImportHandler 驱动：
 * - 评分：必需列缺失 → 0；特征列（distinguishers）全缺 → 0；未知列可识别 → 0（走向导预填）；满足 → 90
 * - 导入：签名 headerMap 预设映射；附加列（不在已知全集且不可识别）→ 自定义字段（字段名 = 原始表头）
 * - LastPass：grouping 支持 '\' 与 '/' 嵌套分隔（slashGroupPath）
 * - Firefox：时间列微秒/秒级时间戳（CREATED/LAST_MODIFIED）；无标题列时域名兜底
 */
export default function PresetCsvImportFormatsTest() {
  describe('PresetCsvImportHandler_chrome', () => {
    // Chrome/Edge/Brave/Opera/Vivaldi 导出格式：name,url,username,password[,note]
    let handler: PresetCsvImportHandler = buildPresetHandler('CHROME_CSV');

    beforeEach(() => {
      handler = buildPresetHandler('CHROME_CSV');
    });

    describe('canHandle', () => {
      it('shouldAcceptCsvExtension', 0, () => {
        expect(handler.canHandle('.csv')).assertTrue();
      });

      it('shouldBeCaseInsensitive', 0, () => {
        expect(handler.canHandle('.CSV')).assertTrue();
      });

      it('shouldRejectNonCsvExtensions', 0, () => {
        expect(handler.canHandle('.xml')).assertFalse();
        expect(handler.canHandle('.json')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('CHROME_CSV');
        expect(handler.formatName).assertEqual('Chrome CSV');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.csv');
      });
    });

    describe('sniff', () => {
      it('shouldDetectChromeHeader', 0, () => {
        const header = ['name', 'url', 'username', 'password', 'note'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldDetectChromeHeaderWithoutNote', 0, () => {
        const header = ['name', 'url', 'username', 'password'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectFirefoxHeader', 0, () => {
        const header = ['url', 'username', 'password', 'httpRealm', 'formActionOrigin', 'guid', 'timeCreated', 'timeLastUsed', 'timePasswordChanged'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });

      it('shouldRejectRandomHeader', 0, () => {
        expect(handler.sniff(['foo', 'bar'], [])).assertEqual(0);
      });

      it('shouldClaimHeaderWithUnrecognizableExtraColumn', 0, () => {
        // 完全不可识别的未知列 → 参考 KeePass 2.x 语义忽略照导
        const header = ['name', 'url', 'username', 'password', 'note', 'extra'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectHeaderWithRecognizableExtraColumn', 0, () => {
        // 可识别的未知列（可映射标准字段）→ 拒绝认领，交由列映射向导预填（不丢列数据）
        const header = ['name', 'url', 'username', 'password', 'note', 'GROUP分组'];
        expect(handler.sniff(header, [])).assertEqual(0);
      });
    });

    describe('import', () => {
      it('shouldImportChromeExport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username,password,note\n' +
          'GitHub,https://github.com,user1,pass1,Saved by Chrome';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(entry.fields.get('UserName')).assertEqual('user1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass1');
        expect(entry.fields.get('Notes')).assertEqual('Saved by Chrome');
      });

      it('shouldImportMultipleEntries', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username,password\n' +
          'Site A,https://a.com,usera,passa\n' +
          'Site B,https://b.com,userb,passb';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');

        const result = await handler.import(fileContent);
        expect(result.entries.length).assertEqual(2);
        expect(result.entries[0].fields.get('Title')).assertEqual('Site A');
        expect(result.entries[1].fields.get('Title')).assertEqual('Site B');
      });

      it('shouldHandleMultilineQuotedNote', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username,password,note\n' +
          'Site,https://s.com,user,pass,"line1\nline2"';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');

        const result = await handler.import(fileContent);
        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Notes')).assertEqual('line1\nline2');
      });

      it('shouldProtectPassword', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username,password\nSite,https://s.com,user,secret';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');

        const result = await handler.import(fileContent);
        const passwordField = result.entries[0].fields.get('Password');
        expect(typeof passwordField !== 'string').assertTrue();
        expect(KdbxUtils.getFieldValueString(result.entries[0].fields, 'Password')).assertEqual('secret');
      });

      it('shouldImportUnrecognizableExtraColumnAsCustomField', 0, async () => {
        // 附加列（不在签名已知全集且不可识别）→ 自定义字段，字段名 = 原始表头
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,url,username,password,note,extra\n' +
          'GitHub,https://github.com,user1,pass1,Saved by Chrome,MyExtraValue';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('extra')).assertEqual('MyExtraValue');
        expect(result.entries[0].fields.get('Title')).assertEqual('GitHub');
      });

      it('shouldThrowFileEmptyForEmptyFile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('', 'chrome.csv');
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
        const testDb = await TestUtils.createTestDatabase('Chrome Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'name,username,password\nSite,user,pass';
        const fileContent = TestUtils.createFileContent(csvContent, 'chrome.csv');
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

  describe('PresetCsvImportHandler_firefox', () => {
    // Firefox about:logins 导出格式：
    // url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged
    // 时间列为微秒级 epoch（兼容秒/毫秒级输入）
    let handler: PresetCsvImportHandler = buildPresetHandler('FIREFOX_CSV');

    beforeEach(() => {
      handler = buildPresetHandler('FIREFOX_CSV');
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
        // 参考 KeePass 2.x 按名映射语义：非必需列缺失照常认领（该字段留空）
        const header = ['url', 'username', 'password', 'formActionOrigin', 'guid', 'timeCreated', 'timeLastUsed', 'timePasswordChanged'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldClaimFirefoxHeaderWithUnrecognizableExtraColumn', 0, () => {
        // 完全不可识别的未知列 → 参考 KeePass 2.x 语义忽略照导
        const header = ['url', 'username', 'password', 'httpRealm', 'formActionOrigin', 'guid', 'timeCreated', 'timeLastUsed', 'timePasswordChanged', 'extra'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectFirefoxHeaderWithRecognizableExtraColumn', 0, () => {
        // 可识别的未知列（可映射标准字段）→ 拒绝认领，交由列映射向导预填（不丢列数据）
        const header = ['url', 'username', 'password', 'httpRealm', 'formActionOrigin', 'guid', 'timeCreated', 'timeLastUsed', 'timePasswordChanged', 'GROUP分组'];
        expect(handler.sniff(header, [])).assertEqual(0);
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

  describe('PresetCsvImportHandler_lastpass', () => {
    // LastPass 导出格式：url,username,password,extra,name,grouping,fav[,totp]
    // - grouping 支持 '\'（KeePass LastPassCsv2 语义）与 '/' 两种嵌套分隔符（slashGroupPath）
    // - extra 多行内容导入 Notes；totp 列导入 'otp' 字段（裸密钥转 key= 格式，otpauth 原样保留）
    // - fav 列忽略
    let handler: PresetCsvImportHandler = buildPresetHandler('LASTPASS_CSV');

    beforeEach(() => {
      handler = buildPresetHandler('LASTPASS_CSV');
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

      it('shouldClaimHeaderWithUnrecognizableExtraColumn', 0, () => {
        // 完全不可识别的未知列 → 参考 KeePass 2.x 语义忽略照导
        const header = ['url', 'username', 'password', 'extra', 'name', 'grouping', 'fav', 'totp', 'unknown'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectHeaderWithRecognizableExtraColumn', 0, () => {
        // 可识别的未知列（可映射标准字段）→ 拒绝认领，交由列映射向导预填（不丢列数据）
        const header = ['url', 'username', 'password', 'extra', 'name', 'grouping', 'fav', 'totp', 'TITLE标题'];
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

        // 分组：Work\Email → Work/Email 嵌套（slashGroupPath 归一化）
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

      it('shouldTagFavoriteWhenFavIsOne', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('LastPass Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,extra,name,grouping,fav\n' +
          'https://example.com,user,pass,note,Entry,,1';
        const fileContent = TestUtils.createFileContent(csvContent, 'lastpass.csv');

        const result = await handler.import(fileContent);
        expect(result.entries[0].tags.length).assertEqual(1);
        expect(result.entries[0].tags[0]).assertEqual(KdbxUtils.FAVORITE_TAG);
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

  describe('PresetCsvImportHandler_dashlane', () => {
    // Dashlane 6+ CSV 导出格式：title,url,username,password,note,category,otpSecret,lastModified
    let handler: PresetCsvImportHandler = buildPresetHandler('DASHLANE_CSV');

    beforeEach(() => {
      handler = buildPresetHandler('DASHLANE_CSV');
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

      it('shouldClaimHeaderWithUnrecognizableExtraColumn', 0, () => {
        // 完全不可识别的未知列 → 参考 KeePass 2.x 语义忽略照导
        const header = ['title', 'url', 'username', 'password', 'note', 'category', 'otpSecret', 'lastModified', 'unknown'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectHeaderWithRecognizableExtraColumn', 0, () => {
        // 可识别的未知列（如 Group，KeePass 风格导出特征）→ 拒绝认领，交由列映射向导（不丢列数据）
        const header = ['title', 'url', 'username', 'password', 'note', 'category', 'otpSecret', 'lastModified', 'GROUP分组'];
        expect(handler.sniff(header, [])).assertEqual(0);
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

  describe('PresetCsvImportHandler_onepassword', () => {
    // 1Password 8 CSV 导出格式：Title,Url,Username,Password,OTPAuth,Notes
    let handler: PresetCsvImportHandler = buildPresetHandler('ONEPASSWORD_CSV');

    beforeEach(() => {
      handler = buildPresetHandler('ONEPASSWORD_CSV');
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

      it('shouldClaimHeaderWithUnrecognizableExtraColumn', 0, () => {
        // 完全不可识别的未知列 → 参考 KeePass 2.x 语义忽略照导
        const header = ['Title', 'Url', 'Username', 'Password', 'OTPAuth', 'Notes', 'Unknown'];
        expect(handler.sniff(header, [])).assertEqual(90);
      });

      it('shouldRejectHeaderWithRecognizableExtraColumn', 0, () => {
        // 可识别的未知列（可映射标准字段）→ 拒绝认领，交由列映射向导预填（不丢列数据）
        const header = ['Title', 'Url', 'Username', 'Password', 'OTPAuth', 'Notes', 'GROUP分组'];
        expect(handler.sniff(header, [])).assertEqual(0);
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
