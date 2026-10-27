import { describe, expect, it, beforeEach } from '@ohos/hypium';
import {
  ColumnMappingItem,
  ColumnMappingProfile,
  WizardTargetField,
  WizardTargetFieldConverter
} from '../../../../main/ets/services/importExport/csvimport/CsvMappingModels';
import { CsvTargetField } from '../../../../main/ets/services/importExport/csvimport/CsvImportModels';
import { GenericCsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/GenericCsvImportHandler';
import { CsvFamilyDispatcherImportHandler } from '../../../../main/ets/services/importExport/handlers/import/CsvFamilyDispatcherImportHandler';
import { ImportWizardBridge, WizardPagePresenter } from '../../../../main/ets/services/importExport/wizard/ImportWizardBridge';
import { CsvMappingPreview } from '../../../../main/ets/services/importExport/csvimport/CsvMappingModels';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * 记录呈现并拒绝：headless 环境验证向导是否被请求
 */
class RecordingRefusingPresenter implements WizardPagePresenter {
  presented: boolean = false;

  present(preview: CsvMappingPreview): boolean {
    this.presented = true;
    return false;
  }
}

/**
 * 记录呈现并接受：验证向导未被请求（presented 应保持 false）
 */
class RecordingAcceptingPresenter implements WizardPagePresenter {
  presented: boolean = false;

  present(preview: CsvMappingPreview): boolean {
    this.presented = true;
    return true;
  }
}

/**
 * CSV 列映射向导模型 + importWithProfile 导入路径 + 调度器向导路由 单元测试（M2-4）
 * 1. ColumnMappingProfile.validate：至少一映射列 + 标准目标冲突检测 + CUSTOM 冲突（按自定义字段名/源列名）
 * 2. WizardTargetFieldConverter 双向转换
 * 3. GenericCsvImportHandler.importWithProfile：向导档案 → 标准/自定义字段 + 目标分组包装 + 全 SKIP 报错
 * 4. 调度器未知来源 headless 路由：无 UI 上下文回落建议映射直导；Norton 签名直接分发
 */
export default function CsvMappingWizardTest() {
  describe('CsvMappingWizard', () => {
    describe('ColumnMappingProfile_validate', () => {
      it('shouldFailWhenAllColumnsSkipped', 0, () => {
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'a', WizardTargetField.SKIP),
          new ColumnMappingItem(1, 'b', WizardTargetField.SKIP)
        ], '');
        const result = profile.validate();
        expect(result.hasMappedColumn).assertFalse();
        expect(result.isValid).assertFalse();
        expect(result.conflicts.length).assertEqual(0);
      });

      it('shouldPassWithSingleMappedColumn', 0, () => {
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'a', WizardTargetField.SKIP),
          new ColumnMappingItem(1, 'b', WizardTargetField.TITLE)
        ], '');
        const result = profile.validate();
        expect(result.hasMappedColumn).assertTrue();
        expect(result.conflicts.length).assertEqual(0);
      });

      it('shouldDetectStandardTargetConflict', 0, () => {
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'name', WizardTargetField.TITLE),
          new ColumnMappingItem(1, 'title', WizardTargetField.TITLE)
        ], '');
        const result = profile.validate();
        expect(result.hasMappedColumn).assertTrue();
        expect(result.conflicts.length).assertEqual(1);
        expect(result.conflicts[0].targetLabel).assertEqual('TITLE');
        expect(result.conflicts[0].columnNames.length).assertEqual(2);
        expect(result.conflicts[0].columnNames[0]).assertEqual('name');
        expect(result.conflicts[0].columnNames[1]).assertEqual('title');
      });

      it('shouldDetectCustomFieldConflictByCustomName', 0, () => {
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'colA', WizardTargetField.CUSTOM, 'License'),
          new ColumnMappingItem(1, 'colB', WizardTargetField.CUSTOM, 'License')
        ], '');
        const result = profile.validate();
        expect(result.conflicts.length).assertEqual(1);
        expect(result.conflicts[0].targetLabel).assertEqual('License');
      });

      it('shouldNotConflictCustomFieldsWithDifferentNames', 0, () => {
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'colA', WizardTargetField.CUSTOM, 'License'),
          new ColumnMappingItem(1, 'colB', WizardTargetField.CUSTOM, 'Serial')
        ], '');
        const result = profile.validate();
        expect(result.conflicts.length).assertEqual(0);
      });

      it('shouldFallbackCustomNameToSourceColumnNameForConflict', 0, () => {
        // CUSTOM 未填字段名时按源列名参与冲突检测
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'colA', WizardTargetField.CUSTOM, ''),
          new ColumnMappingItem(1, 'colA', WizardTargetField.CUSTOM, '')
        ], '');
        const result = profile.validate();
        expect(result.conflicts.length).assertEqual(1);
        expect(result.conflicts[0].targetLabel).assertEqual('colA');
      });
    });

    describe('WizardTargetFieldConverter', () => {
      it('shouldConvertEachStandardField', 0, () => {
        expect(WizardTargetFieldConverter.fromCsvTargetField(CsvTargetField.TITLE))
          .assertEqual(WizardTargetField.TITLE);
        expect(WizardTargetFieldConverter.fromCsvTargetField(CsvTargetField.USERNAME))
          .assertEqual(WizardTargetField.USERNAME);
        expect(WizardTargetFieldConverter.fromCsvTargetField(CsvTargetField.PASSWORD))
          .assertEqual(WizardTargetField.PASSWORD);
        expect(WizardTargetFieldConverter.fromCsvTargetField(CsvTargetField.URL))
          .assertEqual(WizardTargetField.URL);
        expect(WizardTargetFieldConverter.fromCsvTargetField(CsvTargetField.NOTES))
          .assertEqual(WizardTargetField.NOTES);
        expect(WizardTargetFieldConverter.fromCsvTargetField(CsvTargetField.EXPIRY_TIME))
          .assertEqual(WizardTargetField.EXPIRY_TIME);
      });

      it('shouldConvertBackEachStandardField', 0, () => {
        expect(WizardTargetFieldConverter.toCsvTargetField(WizardTargetField.TITLE))
          .assertEqual(CsvTargetField.TITLE);
        expect(WizardTargetFieldConverter.toCsvTargetField(WizardTargetField.EXPIRY_TIME))
          .assertEqual(CsvTargetField.EXPIRY_TIME);
      });

      it('shouldReturnUndefinedForSkipAndCustom', 0, () => {
        expect(WizardTargetFieldConverter.toCsvTargetField(WizardTargetField.SKIP)).assertUndefined();
        expect(WizardTargetFieldConverter.toCsvTargetField(WizardTargetField.CUSTOM)).assertUndefined();
      });
    });

    describe('GenericCsvImportHandler_importWithProfile', () => {
      let handler: GenericCsvImportHandler = new GenericCsvImportHandler();

      beforeEach(() => {
        handler = new GenericCsvImportHandler();
      });

      it('shouldImportStandardAndCustomFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Wizard Import Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const rows: string[][] = [
          ['site', 'login', 'secret', 'license'],
          ['Example', 'wuser', 'wpass', 'KEY-123'],
          ['Another', 'wuser2', 'wpass2', '']
        ];
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'site', WizardTargetField.TITLE),
          new ColumnMappingItem(1, 'login', WizardTargetField.USERNAME),
          new ColumnMappingItem(2, 'secret', WizardTargetField.PASSWORD),
          new ColumnMappingItem(3, 'license', WizardTargetField.CUSTOM, 'License')
        ], '');

        const result = handler.importWithProfile(rows, profile);

        expect(result.entries.length).assertEqual(2);
        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('Example');
        expect(entry.fields.get('UserName')).assertEqual('wuser');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('wpass');
        // CUSTOM 列 → 指定自定义字段名
        expect(entry.fields.get('License')).assertEqual('KEY-123');
        // 空自定义值跳过
        expect(result.entries[1].fields.get('License')).assertUndefined();
      });

      it('shouldFallbackCustomNameToSourceColumnName', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Wizard Import Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const rows: string[][] = [
          ['site', 'memo'],
          ['Example', 'some memo']
        ];
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'site', WizardTargetField.TITLE),
          new ColumnMappingItem(1, 'memo', WizardTargetField.CUSTOM, '')
        ], '');

        const result = handler.importWithProfile(rows, profile);

        expect(result.entries.length).assertEqual(1);
        // CUSTOM 未填字段名 → 源列名作为字段名
        expect(result.entries[0].fields.get('memo')).assertEqual('some memo');
      });

      it('shouldWrapEntriesInTargetGroup', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Wizard Import Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const rows: string[][] = [
          ['site'],
          ['Example']
        ];
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'site', WizardTargetField.TITLE)
        ], 'Imported');

        const result = handler.importWithProfile(rows, profile);

        expect(result.entries.length).assertEqual(0);
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Imported');
        expect(result.groups[0].entries.length).assertEqual(1);
        expect(result.groups[0].entries[0].fields.get('Title')).assertEqual('Example');
      });

      it('shouldThrowWhenAllColumnsSkipped', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Wizard Import Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const rows: string[][] = [
          ['site', 'login'],
          ['Example', 'u']
        ];
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'site', WizardTargetField.SKIP),
          new ColumnMappingItem(1, 'login', WizardTargetField.SKIP)
        ], '');

        try {
          handler.importWithProfile(rows, profile);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.INVALID_CSV_HEADER);
          }
        }
      });

      it('shouldImportExpiryTimeFromWizardProfile', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Wizard Import Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const rows: string[][] = [
          ['site', 'expires'],
          ['Example', '1735689600']
        ];
        const profile = new ColumnMappingProfile([
          new ColumnMappingItem(0, 'site', WizardTargetField.TITLE),
          new ColumnMappingItem(1, 'expires', WizardTargetField.EXPIRY_TIME)
        ], '');

        const result = handler.importWithProfile(rows, profile);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.times.expires).assertTrue();
        expect(entry.times.expiryTime?.getTime()).assertEqual(1735689600000);
      });
    });

    describe('DispatcherWizardRouting', () => {
      let dispatcher: CsvFamilyDispatcherImportHandler = new CsvFamilyDispatcherImportHandler();

      beforeEach(() => {
        dispatcher = new CsvFamilyDispatcherImportHandler();
      });

      it('shouldFallBackToSuggestedMappingWhenHeadlessForUnknownSource', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Wizard Database');
        FileService.resetDbFileParam(testDb, Date.now());

        // 未知来源表头（无任何族处理器认领）；headless 测试环境无导航栈 → 桥 resolve null → 通用建议映射直导
        const csvContent = 'title,username,password,url\n' +
          'Example,wuser,wpass,https://example.com';
        const fileContent = TestUtils.createFileContent(csvContent, 'unknown.csv');

        const result = await dispatcher.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('Example');
        expect(entry.fields.get('UserName')).assertEqual('wuser');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('wpass');
        expect(entry.fields.get('URL')).assertEqual('https://example.com');
      });

      it('shouldDispatchNortonSignatureDirectly', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Wizard Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const csvContent = 'url,username,password,title,group\n' +
          'https://github.com,nuser,npass,GitHub,Social';
        const fileContent = TestUtils.createFileContent(csvContent, 'norton.csv');

        const result = await dispatcher.import(fileContent);

        // Norton 语义：group 列 → 分组
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Social');
        expect(result.groups[0].entries[0].fields.get('Title')).assertEqual('GitHub');
      });

      it('shouldDetectSignatureFormatsInDetectFormatId', 0, () => {
        expect(dispatcher.detectFormatId(['url', 'username', 'password', 'title', 'group'], []))
          .assertEqual('NORTON_IDSAFE_CSV');
        expect(dispatcher.detectFormatId(['tk_export_version', 'name', 'login', 'password'], []))
          .assertEqual('TRUEKEY_CSV');
      });

      it('shouldAutoImportKeePassStyleCsvWithoutWizard', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Wizard Database');
        FileService.resetDbFileParam(testDb, Date.now());

        // 标准 KeePass 风格表头：无族处理器认领，但建议映射可识别全部列
        // → 不弹向导（present 不被调用），按建议映射直接导入
        const spy = new RecordingAcceptingPresenter();
        ImportWizardBridge.getInstance().setPresenter(spy);
        try {
          const csvContent = 'Group,Title,UserName,Password,URL,Notes\n' +
            'Internet Bank,MyBank,bankuser,bankpass,https://bank.example.com,main account';
          const fileContent = TestUtils.createFileContent(csvContent, 'keepass-style.csv');

          const result = await dispatcher.import(fileContent);

          expect(spy.presented).assertFalse();
          expect(result.groups.length).assertEqual(1);
          expect(result.groups[0].name).assertEqual('Internet Bank');
          expect(result.groups[0].entries[0].fields.get('Title')).assertEqual('MyBank');
          expect(result.groups[0].entries[0].fields.get('UserName')).assertEqual('bankuser');
          expect(KdbxUtils.getFieldValueString(result.groups[0].entries[0].fields, 'Password')).assertEqual('bankpass');
          expect(result.groups[0].entries[0].fields.get('URL')).assertEqual('https://bank.example.com');
          expect(result.groups[0].entries[0].fields.get('Notes')).assertEqual('main account');
        } finally {
          ImportWizardBridge.getInstance().resetPresenter();
        }
      });

      it('shouldRequestWizardWhenNoRecognizableColumns', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Dispatcher Wizard Database');
        FileService.resetDbFileParam(testDb, Date.now());

        // 无任何可识别列 → 请求向导（present 被调用）；
        // headless 呈现失败回落直导，通用建议映射为空 → INVALID_CSV_HEADER
        const spy = new RecordingRefusingPresenter();
        ImportWizardBridge.getInstance().setPresenter(spy);
        try {
          const csvContent = 'colA,colB,colC\nvalue1,value2,value3';
          const fileContent = TestUtils.createFileContent(csvContent, 'unrecognizable.csv');

          try {
            await dispatcher.import(fileContent);
            expect().assertFail();
          } catch (err) {
            const error = err as Error;
            if (error instanceof ImportError) {
              expect(error.code).assertEqual(ImportExportErrorCode.INVALID_CSV_HEADER);
            } else {
              expect().assertFail();
            }
          }
          expect(spy.presented).assertTrue();
        } finally {
          ImportWizardBridge.getInstance().resetPresenter();
        }
      });
    });
  });
}
