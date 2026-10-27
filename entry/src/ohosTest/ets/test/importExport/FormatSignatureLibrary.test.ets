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
 * FormatSignatureLibrary + PresetCsvImportHandler 单元测试（M2-4）
 * 评分规则（§4.5）：必需表头全在 → 70；表头 ⊆ 已知全集 → 100；否则 0；
 * 未声明可选列的签名（known == required，Norton）出现未知列 → 0（防超集误认领）。
 * 首批签名：Norton Identity Safe CSV（KeePass NortonIdSafeCsv2013 权威）、
 * True Key CSV（KeePass TrueKeyCsv4 权威，特征列 tk_export_version）。
 */
export default function FormatSignatureLibraryTest() {
  describe('FormatSignatureLibrary', () => {
    describe('scoreSignature_norton', () => {
      it('shouldScore100ForExactNortonHeader', 0, () => {
        const signature = FormatSignatureLibrary.getSignature('NORTON_IDSAFE_CSV');
        if (signature === null) {
          expect().assertFail();
          return;
        }
        const score = FormatSignatureLibrary.scoreSignature(
          signature,
          ['url', 'username', 'password', 'title', 'group']
        );
        expect(score).assertEqual(100);
      });

      it('shouldScore100ForCaseInsensitiveNortonHeader', 0, () => {
        const signature = FormatSignatureLibrary.getSignature('NORTON_IDSAFE_CSV');
        if (signature === null) {
          expect().assertFail();
          return;
        }
        const score = FormatSignatureLibrary.scoreSignature(
          signature,
          ['URL', 'Username', 'Password', 'Title', 'Group']
        );
        expect(score).assertEqual(100);
      });

      it('shouldScore0WhenRequiredHeaderMissing', 0, () => {
        const signature = FormatSignatureLibrary.getSignature('NORTON_IDSAFE_CSV');
        if (signature === null) {
          expect().assertFail();
          return;
        }
        // 缺 group 列（4 列）
        const score = FormatSignatureLibrary.scoreSignature(
          signature,
          ['url', 'username', 'password', 'title']
        );
        expect(score).assertEqual(0);
      });

      it('shouldScore0ForKeePassStyleSupersetHeader', 0, () => {
        // 回归护栏：KeePass 风格导出表头是 Norton 必需列的超集，不得被认领（strict 规则 → 0）
        const signature = FormatSignatureLibrary.getSignature('NORTON_IDSAFE_CSV');
        if (signature === null) {
          expect().assertFail();
          return;
        }
        const score = FormatSignatureLibrary.scoreSignature(
          signature,
          ['Group', 'Title', 'UserName', 'Password', 'URL', 'Notes']
        );
        expect(score).assertEqual(0);
      });

      it('shouldScore0ForRandomHeader', 0, () => {
        const signature = FormatSignatureLibrary.getSignature('NORTON_IDSAFE_CSV');
        if (signature === null) {
          expect().assertFail();
          return;
        }
        expect(FormatSignatureLibrary.scoreSignature(signature, ['foo', 'bar'])).assertEqual(0);
      });
    });

    describe('scoreSignature_truekey', () => {
      it('shouldScore100ForFullKnownHeader', 0, () => {
        const signature = FormatSignatureLibrary.getSignature('TRUEKEY_CSV');
        if (signature === null) {
          expect().assertFail();
          return;
        }
        const score = FormatSignatureLibrary.scoreSignature(
          signature,
          ['tk_export_version', 'name', 'login', 'password', 'url', 'favorite', 'city']
        );
        expect(score).assertEqual(100);
      });

      it('shouldScore70ForHeaderWithUnknownExtraColumn', 0, () => {
        // TrueKey 声明了可选列全集（known > required）：未知列 → 70 候选
        const signature = FormatSignatureLibrary.getSignature('TRUEKEY_CSV');
        if (signature === null) {
          expect().assertFail();
          return;
        }
        const score = FormatSignatureLibrary.scoreSignature(
          signature,
          ['tk_export_version', 'name', 'login', 'password', 'future_column']
        );
        expect(score).assertEqual(70);
      });

      it('shouldScore0WhenTkExportVersionMissing', 0, () => {
        const signature = FormatSignatureLibrary.getSignature('TRUEKEY_CSV');
        if (signature === null) {
          expect().assertFail();
          return;
        }
        const score = FormatSignatureLibrary.scoreSignature(
          signature,
          ['name', 'login', 'password', 'url']
        );
        expect(score).assertEqual(0);
      });
    });

    describe('matchAndGet', () => {
      it('shouldMatchNortonHeader', 0, () => {
        const result = FormatSignatureLibrary.matchCsvHeaders(['url', 'username', 'password', 'title', 'group']);
        expect(result?.formatId).assertEqual('NORTON_IDSAFE_CSV');
        expect(result?.score).assertEqual(100);
      });

      it('shouldMatchTrueKeyHeader', 0, () => {
        const result = FormatSignatureLibrary.matchCsvHeaders(
          ['tk_export_version', 'name', 'login', 'password']
        );
        expect(result?.formatId).assertEqual('TRUEKEY_CSV');
      });

      it('shouldReturnNullForUnknownHeader', 0, () => {
        const result = FormatSignatureLibrary.matchCsvHeaders(['foo', 'bar']);
        expect(result).assertNull();
      });

      it('shouldReturnAllSignatures', 0, () => {
        const signatures = FormatSignatureLibrary.getAllSignatures();
        expect(signatures.length).assertEqual(2);
      });

      it('shouldReturnNullForUnknownFormatId', 0, () => {
        expect(FormatSignatureLibrary.getSignature('NOPE')).assertNull();
      });
    });

    describe('PresetCsvImportHandler_norton', () => {
      let handler: PresetCsvImportHandler = buildPresetHandler('NORTON_IDSAFE_CSV');

      beforeEach(() => {
        handler = buildPresetHandler('NORTON_IDSAFE_CSV');
      });

      it('shouldExposeSignatureMetadata', 0, () => {
        expect(handler.formatId).assertEqual('NORTON_IDSAFE_CSV');
        expect(handler.formatName).assertEqual('Norton Identity Safe');
        expect(handler.canHandle('.csv')).assertTrue();
      });

      it('shouldSniffBySignatureScore', 0, () => {
        expect(handler.sniff(['url', 'username', 'password', 'title', 'group'], [])).assertEqual(100);
        expect(handler.sniff(['foo', 'bar'], [])).assertEqual(0);
      });

      it('shouldImportNortonExportWithGroup', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Norton CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,title,group\n' +
          'https://github.com,nuser,npass,GitHub,Social\n' +
          'https://example.com,nuser2,npass2,Example,';
        const fileContent = TestUtils.createFileContent(csvContent, 'norton.csv');

        const result = await handler.import(fileContent);

        // group 列语义：分组；空 group → 根分组
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Social');
        expect(result.groups[0].entries.length).assertEqual(1);
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(entry.fields.get('UserName')).assertEqual('nuser');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('npass');

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Title')).assertEqual('Example');
      });

      it('shouldThrowInvalidHeaderWhenRequiredColumnMissing', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Norton CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,title\nhttps://a.com,u,p,T';
        const fileContent = TestUtils.createFileContent(csvContent, 'norton.csv');
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

    describe('PresetCsvImportHandler_truekey', () => {
      let handler: PresetCsvImportHandler = buildPresetHandler('TRUEKEY_CSV');

      beforeEach(() => {
        handler = buildPresetHandler('TRUEKEY_CSV');
      });

      it('shouldExposeSignatureMetadata', 0, () => {
        expect(handler.formatId).assertEqual('TRUEKEY_CSV');
        expect(handler.formatName).assertEqual('True Key');
      });

      it('shouldImportTrueKeyExportWithFavoriteAndCustomFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('True Key CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'tk_export_version,name,login,password,url,favorite,city,autologin\n' +
          '2,GitHub,tkuser,tkpass,https://github.com,1,San Francisco,0';
        const fileContent = TestUtils.createFileContent(csvContent, 'truekey.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('UserName')).assertEqual('tkuser');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('tkpass');
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        // favorite=1 → __FAVORITE__ 标签（BitwardenCsv 先例）
        expect(entry.tags.includes(KdbxUtils.FAVORITE_TAG)).assertTrue();
        // customHeaderMap：city → City 自定义字段
        expect(entry.fields.get('City')).assertEqual('San Francisco');
        // ignoredHeaders：autologin 不入字段
        expect(entry.fields.get('autologin')).assertUndefined();
        expect(entry.fields.get('Autologin')).assertUndefined();
      });

      it('shouldNotTagFavoriteWhenFavoriteUnset', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('True Key CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'tk_export_version,name,login,password,favorite\n' +
          '2,Site,tkuser,tkpass,0';
        const fileContent = TestUtils.createFileContent(csvContent, 'truekey.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].tags.includes(KdbxUtils.FAVORITE_TAG)).assertFalse();
      });

      it('shouldImportExpiryTimeFromExpirationDate', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('True Key CSV Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        // 1735689600 秒 = 2025-01-01T00:00:00Z
        const csvContent = 'tk_export_version,name,login,password,expirationdate\n' +
          '2,Site,tkuser,tkpass,1735689600';
        const fileContent = TestUtils.createFileContent(csvContent, 'truekey.csv');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.times.expires).assertTrue();
        expect(entry.times.expiryTime?.getTime()).assertEqual(1735689600000);
      });
    });
  });
}
