import { describe, expect, it, beforeAll } from '@ohos/hypium';
import { ImportFormatCatalog } from '../../../../main/ets/services/importExport/catalog/ImportFormatCatalog';
import { ImportFormatGroupInfo } from '../../../../main/ets/services/importExport/catalog/ImportFormatCatalog';
import { FormatSignatureLibrary } from '../../../../main/ets/services/importExport/sniffing/FormatSignatureLibrary';
import { CsvFamilyDispatcherImportHandler } from '../../../../main/ets/services/importExport/handlers/import/CsvFamilyDispatcherImportHandler';
import { JsonFamilyDispatcherImportHandler } from '../../../../main/ets/services/importExport/handlers/import/JsonFamilyDispatcherImportHandler';
import { XmlImportHandler } from '../../../../main/ets/services/importExport/handlers/import/XmlImportHandler';
import { ImportSessionInfo } from '../../../../main/ets/services/importExport/common/ImportSessionInfo';
import { ResourceManager } from '../../../../main/ets/common/utils';
import { TestContextHelper } from '../TestContextHelper';

/**
 * 按分组标识查 catalog 分组（缺失时抛错使测试失败）
 */
function requireGroup(groups: ImportFormatGroupInfo[], groupId: string): ImportFormatGroupInfo {
  for (const group of groups) {
    if (group.groupId === groupId) {
      return group;
    }
  }
  throw new Error(`catalog group not found: ${groupId}`);
}

/**
 * 分组内是否包含指定格式标识
 */
function hasFormat(group: ImportFormatGroupInfo, formatId: string): boolean {
  for (const format of group.formats) {
    if (format.formatId === formatId) {
      return true;
    }
  }
  return false;
}

/**
 * catalog 分组缓存（Hypium 1.0.28 的 beforeEach 不作用于嵌套 describe 的用例，
 * 故用文件级 memo 在用例内自取；catalog 为确定性数据，构建一次即可）
 */
let cachedGroups: ImportFormatGroupInfo[] = [];

function catalogGroups(): ImportFormatGroupInfo[] {
  if (cachedGroups.length === 0) {
    cachedGroups = ImportFormatCatalog.getCatalog();
  }
  return cachedGroups;
}

/**
 * ImportFormatCatalog 防漂移护栏测试（见 docs/import-format-hints-design.md §七）
 * catalog 是帮助面板 / 副标题 / JSON 失败引导的单一数据源：
 * 断言清单与签名库、dispatcher 家族、注册表逐一对齐——新增格式后清单自动跟随，
 * 若清单聚合漏带新格式（漂移）本套件立即失败。
 */
export default function ImportFormatCatalogTest() {
  describe('ImportFormatCatalog', () => {
    // GENERIC_CSV 的 note 经 ResourceManager 解析本地化文本，
    // 测试环境需先注入 context（否则 getString 返回空串，note 断言必失败）
    beforeAll(async () => {
      ResourceManager.getInstance().init(await TestContextHelper.getUIAbilityContext());
    });

    describe('csvGroup', () => {
      it('shouldContainAllSignatureFormatIds', 0, () => {
        const groups = catalogGroups();
        const csvGroup = requireGroup(groups, 'CSV');
        for (const signature of FormatSignatureLibrary.getAllSignatures()) {
          if (!hasFormat(csvGroup, signature.formatId)) {
            expect().assertFail();
            return;
          }
        }
      });

      it('shouldContainSpecialHandlersAndGenericFallback', 0, () => {
        const groups = catalogGroups();
        const csvGroup = requireGroup(groups, 'CSV');
        expect(hasFormat(csvGroup, 'BITWARDEN_CSV')).assertTrue();
        expect(hasFormat(csvGroup, 'PROTONPASS_CSV')).assertTrue();
        expect(hasFormat(csvGroup, 'KEEPER_CSV')).assertTrue();
        expect(hasFormat(csvGroup, 'ENPASS_CSV')).assertTrue();
        expect(hasFormat(csvGroup, 'GENERIC_CSV')).assertTrue();
      });

      it('shouldMatchDispatcherSubFormatCount', 0, () => {
        const groups = catalogGroups();
        const csvGroup = requireGroup(groups, 'CSV');
        const dispatcher = new CsvFamilyDispatcherImportHandler();
        expect(csvGroup.formats.length).assertEqual(dispatcher.getSubFormats().length);
        // 12 已知来源（8 签名 + 4 特殊行 handler）+ 通用兜底 = 13
        expect(csvGroup.formats.length).assertEqual(
          FormatSignatureLibrary.getAllSignatures().length + 5
        );
      });

      it('shouldAnnotateGenericFallbackNoteOnly', 0, () => {
        const groups = catalogGroups();
        const csvGroup = requireGroup(groups, 'CSV');
        let noteCount = 0;
        for (const format of csvGroup.formats) {
          if (format.note !== '') {
            expect(format.formatId).assertEqual('GENERIC_CSV');
            noteCount++;
          }
        }
        expect(noteCount).assertEqual(1);
      });
    });

    describe('jsonGroup', () => {
      it('shouldMatchJsonDispatcherSubFormats', 0, () => {
        const groups = catalogGroups();
        const jsonGroup = requireGroup(groups, 'JSON');
        const dispatcher = new JsonFamilyDispatcherImportHandler();
        const subFormats = dispatcher.getSubFormats();
        expect(jsonGroup.formats.length).assertEqual(subFormats.length);
        for (const format of subFormats) {
          if (!hasFormat(jsonGroup, format.formatId)) {
            expect().assertFail();
            return;
          }
        }
      });

      it('shouldContainBitwardenAndProtonPass', 0, () => {
        const groups = catalogGroups();
        const jsonGroup = requireGroup(groups, 'JSON');
        expect(hasFormat(jsonGroup, 'BITWARDEN_JSON')).assertTrue();
        expect(hasFormat(jsonGroup, 'PROTONPASS_JSON')).assertTrue();
      });
    });

    describe('xmlGroup', () => {
      it('shouldWrapXmlImportHandler', 0, () => {
        const groups = catalogGroups();
        const xmlGroup = requireGroup(groups, 'XML');
        const xmlHandler = new XmlImportHandler();
        expect(hasFormat(xmlGroup, xmlHandler.formatId)).assertTrue();
        expect(xmlGroup.formats.length).assertEqual(1);
      });
    });

    describe('catalogCoverage', () => {
      it('shouldCoverAllTopLevelImportFormats', 0, () => {
        // 组 groupId 覆盖注册表全部顶层导入 handler（CSV / JSON / XML），不多不少
        const groups = catalogGroups();
        expect(groups.length).assertEqual(3);
        expect(requireGroup(groups, 'CSV').groupId).assertEqual('CSV');
        expect(requireGroup(groups, 'JSON').groupId).assertEqual('JSON');
        expect(requireGroup(groups, 'XML').groupId).assertEqual('XML');
      });

      it('shouldProvideCountAndNamesHelpers', 0, () => {
        const groups = catalogGroups();
        const csvCount = ImportFormatCatalog.countFormats(groups, 'CSV');
        expect(csvCount).assertEqual(FormatSignatureLibrary.getAllSignatures().length + 5);
        expect(ImportFormatCatalog.countFormats(groups, 'MISSING')).assertEqual(0);
        const jsonNames = ImportFormatCatalog.getFormatNames(groups, 'JSON');
        expect(jsonNames.length).assertEqual(2);
        expect(ImportFormatCatalog.getFormatNames(groups, 'MISSING').length).assertEqual(0);
      });
    });

    describe('importSessionInfo', () => {
      it('shouldStartEmptyAfterReset', 0, () => {
        ImportSessionInfo.getInstance().reset();
        expect(ImportSessionInfo.getInstance().detectedFormatId).assertEqual('');
        expect(ImportSessionInfo.getInstance().detectedFormatName).assertEqual('');
      });

      it('shouldReportAndOverwriteDetectedFormat', 0, () => {
        ImportSessionInfo.getInstance().reset();
        ImportSessionInfo.getInstance().reportDetectedFormat('LASTPASS_CSV', 'LastPass CSV');
        expect(ImportSessionInfo.getInstance().detectedFormatId).assertEqual('LASTPASS_CSV');
        expect(ImportSessionInfo.getInstance().detectedFormatName).assertEqual('LastPass CSV');
        ImportSessionInfo.getInstance().reportDetectedFormat('GENERIC_CSV', 'Generic CSV');
        expect(ImportSessionInfo.getInstance().detectedFormatId).assertEqual('GENERIC_CSV');
        expect(ImportSessionInfo.getInstance().detectedFormatName).assertEqual('Generic CSV');
        ImportSessionInfo.getInstance().reset();
      });
    });
  });
}
