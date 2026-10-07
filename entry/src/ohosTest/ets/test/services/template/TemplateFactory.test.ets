import { afterAll, afterEach, beforeAll, beforeEachIt, describe, expect, it } from '@ohos/hypium';
import { TemplateFactory } from '../../../../../main/ets/services/template/TemplateFactory';
import { ITemplateStrategy } from '../../../../../main/ets/services/template/strategies/ITemplateStrategy';
import {
  ITemplate,
  IPresetTemplate,
  IUserTemplate,
  ITemplateField,
  StandardFieldsMap,
  TemplateApplyOptions
} from '../../../../../main/ets/services/template/TemplateTypes';
import { TemplateConstants } from '../../../../../main/ets/services/template/TemplateConstants';
import { PresetTemplateStrategy } from '../../../../../main/ets/services/template/strategies/PresetTemplateStrategy';
import { UserTemplateStrategy } from '../../../../../main/ets/services/template/strategies/UserTemplateStrategy';
import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { FileService } from '../../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../../main/ets/common/utils';
import { TestUtils } from '../../importExport/TestUtils';

/**
 * 用于测试 fallback 路径的伪模板（无 id / 无 uuid，两个策略均不支持）
 */
class FakeTemplate {
  name: string = 'Fake';
  iconId: number = 7;
  standardFields: StandardFieldsMap = { title: 'FakeTitle' };
  customFields: ITemplateField[] = [{ key: 'fake_cf', value: 'fcv', isProtected: false }];
  tags: string[] = ['t1', 't2'];
  createdAt: Date = new Date();
  updatedAt: Date = new Date();
}

/**
 * 自定义策略桩：在 entry 上写入标记字段以验证被调用
 */
class MarkerStrategy implements ITemplateStrategy {
  private supported: boolean;
  public callCount: number = 0;

  constructor(supported: boolean) {
    this.supported = supported;
  }

  getTemplates(kdbx?: Kdbx): ITemplate[] {
    return [];
  }

  applyTemplate(entry: KdbxEntry, template: ITemplate, options?: TemplateApplyOptions): void {
    this.callCount++;
    entry.fields.set('_markerStrategyApplied', 'true');
  }

  supports(template: ITemplate): boolean {
    return this.supported;
  }

  getTemplateName(template: ITemplate): string {
    return 'Marker';
  }

  getTemplateIconId(template: ITemplate): number | string {
    return 99;
  }
}

/**
 * TemplateFactory 单元测试
 * 覆盖率目标：构造 / registerStrategy / createEntry（策略路径+回退） / createEntries /
 *             createEntryFromPresetId / createEmptyEntry / createTemplateFromEntry / cloneEntry / getters
 */
export default function TemplateFactoryTest() {
  describe('TemplateFactory', () => {
    let db: Kdbx;
    let rootGroup: KdbxGroup;
    let factory: TemplateFactory;

    beforeAll(async () => {
      db = await TestUtils.createTestDatabase('TemplateFactory Test DB');
    });

    // beforeEachIt：Hypium 中父级 beforeEach 不会传播到嵌套 describe 的用例，需用 beforeEachIt
    beforeEachIt(() => {
      FileService.resetDbFileParam(db, Date.now());
      rootGroup = db.getDefaultGroup();
      factory = new TemplateFactory();
    });

    afterEach(() => {});
    afterAll(() => {});

    describe('constructor', () => {
      it('shouldRegisterPresetStrategy', 0, () => {
        expect(factory.getPresetStrategy() instanceof PresetTemplateStrategy).assertTrue();
      });

      it('shouldRegisterUserStrategy', 0, () => {
        expect(factory.getUserStrategy() instanceof UserTemplateStrategy).assertTrue();
      });
    });

    describe('registerStrategy', () => {
      it('shouldRegisterCustomStrategy', 0, () => {
        const stub: MarkerStrategy = new MarkerStrategy(true);
        factory.registerStrategy('marker', stub);
        const fake: FakeTemplate = new FakeTemplate();
        const entry: KdbxEntry = factory.createEntry(fake as ITemplate, rootGroup);
        expect(stub.callCount).assertEqual(1);
        expect(entry.fields.get('_markerStrategyApplied')).assertEqual('true');
      });

      it('shouldNotUseStrategyThatDoesNotSupport', 0, () => {
        const stub: MarkerStrategy = new MarkerStrategy(false);
        factory.registerStrategy('marker-noop', stub);
        const preset: IPresetTemplate = TemplateConstants.GENERAL;
        factory.createEntry(preset as ITemplate, rootGroup);
        expect(stub.callCount).assertEqual(0);
      });

      it('shouldOverwriteExistingStrategyName', 0, () => {
        const stub1: MarkerStrategy = new MarkerStrategy(true);
        const stub2: MarkerStrategy = new MarkerStrategy(true);
        factory.registerStrategy('preset', stub1);
        factory.registerStrategy('preset', stub2);
        const fake: FakeTemplate = new FakeTemplate();
        factory.createEntry(fake as ITemplate, rootGroup);
        expect(stub2.callCount).assertEqual(1);
      });
    });

    describe('createEntry_with_preset_template', () => {
      it('shouldCreateEntryFromEmailTemplate', 0, () => {
        const entry: KdbxEntry = factory.createEntry(TemplateConstants.EMAIL as ITemplate, rootGroup);
        expect(entry.fields.get('smtp_port')).assertEqual('465');
        expect(entry.fields.get('imap_port')).assertEqual('993');
      });

      it('shouldApplyIconWhenCopyIconDefault', 0, () => {
        const entry: KdbxEntry = factory.createEntry(TemplateConstants.EMAIL as ITemplate, rootGroup);
        expect(entry.icon).assertEqual(TemplateConstants.EMAIL.iconId);
      });

      it('shouldSkipIconWhenCopyIconFalse', 0, () => {
        const entry: KdbxEntry = factory.createEntry(
          TemplateConstants.EMAIL as ITemplate,
          rootGroup,
          { overwriteExisting: false, copyTags: false, copyIcon: false, copyExpiry: false }
        );
        expect(entry.icon).assertEqual(0);
      });

      it('shouldCreateEntryFromGeneralTemplate', 0, () => {
        const entry: KdbxEntry = factory.createEntry(TemplateConstants.GENERAL as ITemplate, rootGroup);
        expect(entry).not().assertNull();
      });

      it('shouldCreateEntryFromBankCardTemplate', 0, () => {
        const entry: KdbxEntry = factory.createEntry(TemplateConstants.BANK_CARD as ITemplate, rootGroup);
        expect(entry.fields.get('bank_card_number')).not().assertNull();
        expect(KdbxUtils.getValueString(entry.fields.get('cvv'))).assertEqual('');
      });

      it('shouldNotOverwriteExistingFieldsWhenOverwriteExistingFalse', 0, () => {
        const entry: KdbxEntry = factory.createEntry(
          TemplateConstants.EMAIL as ITemplate,
          rootGroup,
          { overwriteExisting: false, copyTags: true, copyIcon: true, copyExpiry: false }
        );
        expect(entry.fields.get('smtp_port')).assertEqual('465');
      });
    });

    describe('createEntry_fallback_path', () => {
      it('shouldFallBackToManualWhenNoStrategySupports', 0, () => {
        const fake: FakeTemplate = new FakeTemplate();
        const entry: KdbxEntry = factory.createEntry(fake as ITemplate, rootGroup);
        expect(entry.fields.get('Title')).assertEqual('FakeTitle');
        expect(entry.fields.get('fake_cf')).assertEqual('fcv');
        expect(entry.fields.get('Tags')).assertEqual('t1,t2');
        expect(entry.icon).assertEqual(7);
      });

      it('shouldSkipCustomFieldsWhenEmptyInFallback', 0, () => {
        const fake: FakeTemplate = new FakeTemplate();
        fake.customFields = [];
        const entry: KdbxEntry = factory.createEntry(fake as ITemplate, rootGroup);
        expect(entry.fields.get('Title')).assertEqual('FakeTitle');
      });

      it('shouldSkipIconWhenCopyIconFalseInFallback', 0, () => {
        const fake: FakeTemplate = new FakeTemplate();
        const entry: KdbxEntry = factory.createEntry(
          fake as ITemplate,
          rootGroup,
          { overwriteExisting: false, copyTags: false, copyIcon: false, copyExpiry: false }
        );
        expect(entry.icon).assertEqual(0);
      });

      it('shouldSkipTagsWhenCopyTagsFalseInFallback', 0, () => {
        const fake: FakeTemplate = new FakeTemplate();
        const entry: KdbxEntry = factory.createEntry(
          fake as ITemplate,
          rootGroup,
          { overwriteExisting: false, copyTags: false, copyIcon: true, copyExpiry: false }
        );
        expect(entry.fields.get('Tags')).assertUndefined();
      });
    });

    describe('createEntries', () => {
      it('shouldCreateMultipleEntries', 0, () => {
        const templates: ITemplate[] = [
          TemplateConstants.GENERAL as ITemplate,
          TemplateConstants.EMAIL as ITemplate,
          TemplateConstants.WEBSITE as ITemplate
        ];
        const entries: KdbxEntry[] = factory.createEntries(templates, rootGroup);
        expect(entries.length).assertEqual(3);
      });

      it('shouldReturnEmptyArrayForEmptyInput', 0, () => {
        const entries: KdbxEntry[] = factory.createEntries([], rootGroup);
        expect(entries.length).assertEqual(0);
      });

      it('shouldCreateEntriesWithCustomOptions', 0, () => {
        const templates: ITemplate[] = [
          TemplateConstants.GENERAL as ITemplate,
          TemplateConstants.WIFI as ITemplate
        ];
        const entries: KdbxEntry[] = factory.createEntries(
          templates,
          rootGroup,
          { overwriteExisting: false, copyTags: false, copyIcon: false, copyExpiry: false }
        );
        expect(entries.length).assertEqual(2);
      });
    });

    describe('createEntryFromPresetId', () => {
      it('shouldCreateEntryForKnownId', 0, () => {
        const entry: KdbxEntry | null = factory.createEntryFromPresetId('email', rootGroup);
        expect(entry).not().assertNull();
        expect(entry?.fields.get('smtp_port')).assertEqual('465');
      });

      it('shouldReturnNullForUnknownId', 0, () => {
        const entry: KdbxEntry | null = factory.createEntryFromPresetId('nonexistent', rootGroup);
        expect(entry).assertNull();
      });

      it('shouldCreateEntryWithOptions', 0, () => {
        const entry: KdbxEntry | null = factory.createEntryFromPresetId(
          'general',
          rootGroup,
          { overwriteExisting: false, copyTags: false, copyIcon: false, copyExpiry: false }
        );
        expect(entry).not().assertNull();
      });
    });

    describe('createEmptyEntry', () => {
      it('shouldCreateEntryWithoutFields', 0, () => {
        const before: number = rootGroup.entries.length;
        const entry: KdbxEntry = factory.createEmptyEntry(rootGroup);
        expect(entry instanceof KdbxEntry).assertTrue();
        expect(rootGroup.entries.length).assertEqual(before + 1);
      });

      it('shouldNotSetTitle', 0, () => {
        const entry: KdbxEntry = factory.createEmptyEntry(rootGroup);
        // KdbxEntry.create 预置 Title 为空串
        expect(entry.fields.get('Title')).assertEqual('');
      });
    });

    describe('createTemplateFromEntry', () => {
      it('shouldCreateTemplateEntryWithFlag', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src', 'su', 'sp');
        const templateGroup: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const template: KdbxEntry = factory.createTemplateFromEntry(source, templateGroup, db.meta);
        expect(template.fields.get('KeePassHO_Template')).assertEqual('true');
      });

      it('shouldCopyFieldsFromSource', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src', 'su', 'sp');
        source.fields.set('custom_f', 'cv');
        const templateGroup: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const template: KdbxEntry = factory.createTemplateFromEntry(source, templateGroup, db.meta);
        expect(template.fields.get('Title')).assertEqual('Src');
        expect(template.fields.get('UserName')).assertEqual('su');
        expect(KdbxUtils.getValueString(template.fields.get('Password'))).assertEqual('sp');
        expect(template.fields.get('custom_f')).assertEqual('cv');
      });

      it('shouldAddEntryToTemplateGroup', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        const templateGroup: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const before: number = templateGroup.entries.length;
        factory.createTemplateFromEntry(source, templateGroup, db.meta);
        expect(templateGroup.entries.length).assertEqual(before + 1);
      });

      it('shouldCopyIconFromSource', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        source.icon = 33;
        const templateGroup: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const template: KdbxEntry = factory.createTemplateFromEntry(source, templateGroup, db.meta);
        expect(template.icon).assertEqual(33);
      });

      it('shouldSetCreationAndModTime', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        const templateGroup: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const before: number = Date.now();
        const template: KdbxEntry = factory.createTemplateFromEntry(source, templateGroup, db.meta);
        const creationTime: Date = template.times.creationTime ?? new Date(0);
        const lastModTime: Date = template.times.lastModTime ?? new Date(0);
        expect(creationTime.getTime()).assertLargerOrEqual(before);
        expect(lastModTime.getTime()).assertLargerOrEqual(before);
      });
    });

    describe('cloneEntry', () => {
      it('shouldCloneAllFields', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Original', 'u', 'p', 'https://x', 'n');
        const clone: KdbxEntry = factory.cloneEntry(source, rootGroup);
        expect(clone.fields.get('Title')).assertEqual('Original');
        expect(clone.fields.get('UserName')).assertEqual('u');
        expect(KdbxUtils.getValueString(clone.fields.get('Password'))).assertEqual('p');
        expect(clone.fields.get('URL')).assertEqual('https://x');
        expect(clone.fields.get('Notes')).assertEqual('n');
      });

      it('shouldNotRenameTitleByDefault', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Original');
        const clone: KdbxEntry = factory.cloneEntry(source, rootGroup);
        expect(clone.fields.get('Title')).assertEqual('Original');
      });

      it('shouldRenameTitleWhenRenameTitleTrue', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Original');
        const clone: KdbxEntry = factory.cloneEntry(source, rootGroup, {
          newUuid: true,
          resetTimeInfo: true,
          copyHistory: false,
          renameTitle: true
        });
        expect(clone.fields.get('Title')).assertEqual('Original - 副本');
      });

      it('shouldHandleEmptyTitleWhenRenaming', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, '');
        const clone: KdbxEntry = factory.cloneEntry(source, rootGroup, {
          newUuid: true,
          resetTimeInfo: true,
          copyHistory: false,
          renameTitle: true
        });
        expect(clone.fields.get('Title')).assertEqual(' - 副本');
      });

      it('shouldCopyCustomFields', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Original');
        source.fields.set('cf1', 'cv1');
        source.fields.set('cf2', ProtectedValue.fromString('cv2'));
        const clone: KdbxEntry = factory.cloneEntry(source, rootGroup);
        expect(clone.fields.get('cf1')).assertEqual('cv1');
        expect(KdbxUtils.getValueString(clone.fields.get('cf2'))).assertEqual('cv2');
      });

      it('shouldUseDefaultOptionsWhenUndefined', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Original', 'u');
        const clone: KdbxEntry = factory.cloneEntry(source, rootGroup);
        expect(clone.fields.get('Title')).assertEqual('Original');
        expect(clone.fields.get('UserName')).assertEqual('u');
      });
    });

    describe('getPresetStrategy', () => {
      it('shouldReturnPresetStrategyInstance', 0, () => {
        const s: PresetTemplateStrategy = factory.getPresetStrategy();
        expect(s instanceof PresetTemplateStrategy).assertTrue();
      });

      it('shouldReturnConsistentInstance', 0, () => {
        const a: PresetTemplateStrategy = factory.getPresetStrategy();
        expect(a === factory.getPresetStrategy()).assertTrue();
      });
    });

    describe('getUserStrategy', () => {
      it('shouldReturnUserStrategyInstance', 0, () => {
        const s: UserTemplateStrategy = factory.getUserStrategy();
        expect(s instanceof UserTemplateStrategy).assertTrue();
      });

      it('shouldReturnSameInstanceAcrossCalls', 0, () => {
        expect(factory.getUserStrategy() === factory.getUserStrategy()).assertTrue();
      });
    });
  });
}
