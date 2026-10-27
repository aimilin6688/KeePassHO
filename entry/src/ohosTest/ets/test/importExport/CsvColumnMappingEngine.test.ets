import { describe, expect, it } from '@ohos/hypium';
import { CsvTargetField } from '../../../../main/ets/services/importExport/csvimport/CsvImportModels';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../../../main/ets/services/importExport/csvimport/CsvColumnMappingEngine';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';

/**
 * CsvColumnMappingEngine 单元测试
 * 1. 按格式 Profile（Chrome 等）精确匹配表头构建列映射，缺失必需列抛 INVALID_CSV_HEADER
 * 2. 通用 CSV 通过 ColumnNameMapper 建议映射，同目标字段不重复
 */
export default function CsvColumnMappingEngineTest() {
  describe('CsvColumnMappingEngine', () => {
    const chromeProfile = new CsvFormatProfile(
      'CHROME_CSV', 'Chrome CSV',
      ['name', 'url', 'username', 'password'],
      {
        'name': CsvTargetField.TITLE,
        'url': CsvTargetField.URL,
        'username': CsvTargetField.USERNAME,
        'password': CsvTargetField.PASSWORD,
        'note': CsvTargetField.NOTES
      }
    );

    describe('buildMappingFromProfile', () => {
      it('shouldBuildMappingForFullChromeHeaders', 0, () => {
        const headers = ['name', 'url', 'username', 'password', 'note'];
        const mapping = CsvColumnMappingEngine.buildMappingFromProfile(chromeProfile, headers);
        expect(mapping.length).assertEqual(5);
        expect(mapping[0].target).assertEqual(CsvTargetField.TITLE);
        expect(mapping[0].columnIndex).assertEqual(0);
        expect(mapping[1].target).assertEqual(CsvTargetField.URL);
        expect(mapping[1].columnIndex).assertEqual(1);
        expect(mapping[2].target).assertEqual(CsvTargetField.USERNAME);
        expect(mapping[2].columnIndex).assertEqual(2);
        expect(mapping[3].target).assertEqual(CsvTargetField.PASSWORD);
        expect(mapping[3].columnIndex).assertEqual(3);
        expect(mapping[4].target).assertEqual(CsvTargetField.NOTES);
        expect(mapping[4].columnIndex).assertEqual(4);
      });

      it('shouldIgnoreUnknownColumns', 0, () => {
        const headers = ['name', 'url', 'username', 'password', 'unknown_extra'];
        const mapping = CsvColumnMappingEngine.buildMappingFromProfile(chromeProfile, headers);
        expect(mapping.length).assertEqual(4);
      });

      it('shouldMatchHeadersCaseInsensitively', 0, () => {
        const headers = ['NAME', 'Url', 'UserName', 'PASSWORD'];
        const mapping = CsvColumnMappingEngine.buildMappingFromProfile(chromeProfile, headers);
        expect(mapping.length).assertEqual(4);
        expect(mapping[0].target).assertEqual(CsvTargetField.TITLE);
        expect(mapping[3].target).assertEqual(CsvTargetField.PASSWORD);
      });

      it('shouldTrimHeaderWhitespace', 0, () => {
        const headers = ['  name ', 'url', 'username', 'password'];
        const mapping = CsvColumnMappingEngine.buildMappingFromProfile(chromeProfile, headers);
        expect(mapping.length).assertEqual(4);
        expect(mapping[0].columnIndex).assertEqual(0);
      });

      it('shouldThrowWhenRequiredColumnMissing', 0, () => {
        const headers = ['name', 'url', 'username'];
        try {
          CsvColumnMappingEngine.buildMappingFromProfile(chromeProfile, headers);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.INVALID_CSV_HEADER);
          }
        }
      });
    });

    describe('buildSuggestedMapping', () => {
      it('shouldBuildSuggestedMappingFromSynonyms', 0, () => {
        const headers = ['Account', 'login', 'pwd', 'website', 'comment'];
        const mapping = CsvColumnMappingEngine.buildSuggestedMapping(headers);
        expect(mapping.length).assertEqual(5);
        expect(mapping[0].target).assertEqual(CsvTargetField.TITLE);
        expect(mapping[1].target).assertEqual(CsvTargetField.USERNAME);
        expect(mapping[2].target).assertEqual(CsvTargetField.PASSWORD);
        expect(mapping[3].target).assertEqual(CsvTargetField.URL);
        expect(mapping[4].target).assertEqual(CsvTargetField.NOTES);
      });

      it('shouldSkipDuplicateTargetsKeepingFirstColumn', 0, () => {
        const headers = ['user', 'username', 'email'];
        const mapping = CsvColumnMappingEngine.buildSuggestedMapping(headers);
        expect(mapping.length).assertEqual(1);
        expect(mapping[0].target).assertEqual(CsvTargetField.USERNAME);
        expect(mapping[0].columnIndex).assertEqual(0);
      });

      it('shouldReturnEmptyMappingForUnrecognizedHeaders', 0, () => {
        const mapping = CsvColumnMappingEngine.buildSuggestedMapping(['foo', 'bar']);
        expect(mapping.length).assertEqual(0);
      });

      it('shouldPreserveColumnIndexes', 0, () => {
        const headers = ['foo', 'Title', 'bar', 'Notes'];
        const mapping = CsvColumnMappingEngine.buildSuggestedMapping(headers);
        expect(mapping.length).assertEqual(2);
        expect(mapping[0].columnIndex).assertEqual(1);
        expect(mapping[1].columnIndex).assertEqual(3);
      });

      it('shouldMapStandardKeePassHeaders', 0, () => {
        const headers = ['Group', 'Title', 'UserName', 'Password', 'URL', 'Notes', 'TOTP', 'Tags', 'Icon', 'Last Modified', 'Created'];
        const mapping = CsvColumnMappingEngine.buildSuggestedMapping(headers);
        expect(mapping.length).assertEqual(11);
        expect(mapping[10].target).assertEqual(CsvTargetField.CREATED);
        expect(mapping[10].columnIndex).assertEqual(10);
      });

      it('shouldMapChineseAnnotatedHeaders', 0, () => {
        // 阶段②前缀匹配：带中文注释的表头全部识别
        const headers = ['GROUP分组', 'TITLE标题', 'USERNAME用户名', 'PASSWORD密码', 'URL网址', 'NOTES备注'];
        const mapping = CsvColumnMappingEngine.buildSuggestedMapping(headers);
        expect(mapping.length).assertEqual(6);
        expect(mapping[0].target).assertEqual(CsvTargetField.GROUP);
        expect(mapping[0].columnIndex).assertEqual(0);
        expect(mapping[1].target).assertEqual(CsvTargetField.TITLE);
        expect(mapping[2].target).assertEqual(CsvTargetField.USERNAME);
        expect(mapping[3].target).assertEqual(CsvTargetField.PASSWORD);
        expect(mapping[4].target).assertEqual(CsvTargetField.URL);
        expect(mapping[5].target).assertEqual(CsvTargetField.NOTES);
        expect(mapping[5].columnIndex).assertEqual(5);
      });

      it('shouldPreferMoreSpecificFuzzyMatchForSameTarget', 0, () => {
        // 阶段②同目标冲突：'USERNAME用户名'（命中 8 字符）比 'NAME名称'（命中 4 字符）更具体
        const headers = ['NAME名称', 'USERNAME用户名'];
        const mapping = CsvColumnMappingEngine.buildSuggestedMapping(headers);
        expect(mapping.length).assertEqual(1);
        expect(mapping[0].target).assertEqual(CsvTargetField.USERNAME);
        expect(mapping[0].columnIndex).assertEqual(1);
      });

      it('shouldKeepExactWinnerWhenFuzzyColumnExists', 0, () => {
        // 阶段①精确命中优先；阶段②同目标不再竞争
        const headers = ['title', 'TITLE标题'];
        const mapping = CsvColumnMappingEngine.buildSuggestedMapping(headers);
        expect(mapping.length).assertEqual(1);
        expect(mapping[0].target).assertEqual(CsvTargetField.TITLE);
        expect(mapping[0].columnIndex).assertEqual(0);
      });
    });
  });
}
