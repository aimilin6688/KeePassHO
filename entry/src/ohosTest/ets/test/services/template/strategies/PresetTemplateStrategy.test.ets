import { afterAll, afterEach, beforeAll, beforeEachIt, describe, expect, it } from '@ohos/hypium';
import { PresetTemplateStrategy } from '../../../../../../main/ets/services/template/strategies/PresetTemplateStrategy';
import {
  ITemplate,
  IPresetTemplate,
  IUserTemplate,
  TemplateApplyOptions
} from '../../../../../../main/ets/services/template/TemplateTypes';
import { TemplateConstants } from '../../../../../../main/ets/services/template/TemplateConstants';
import { TemplateCategory } from '../../../../../../main/ets/services/template/TemplateTypes';
import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { FileService } from '../../../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../../../main/ets/common/utils';
import { TestUtils } from '../../../importExport/TestUtils';

/**
 * PresetTemplateStrategy 单元测试
 * 覆盖率目标：getTemplates / applyTemplate（标准/自定义/图标/标签分支） /
 *             supports / getTemplateName / getTemplateIconId
 */
export default function PresetTemplateStrategyTest() {
  describe('PresetTemplateStrategy', () => {
    let strategy: PresetTemplateStrategy;
    let db: Kdbx;
    let rootGroup: KdbxGroup;

    beforeAll(async () => {
      db = await TestUtils.createTestDatabase('PresetStrategy Test DB');
    });

    // beforeEachIt：Hypium 中父级 beforeEach 不会传播到嵌套 describe 的用例，需用 beforeEachIt
    beforeEachIt(() => {
      FileService.resetDbFileParam(db, Date.now());
      rootGroup = db.getDefaultGroup();
      strategy = new PresetTemplateStrategy();
    });

    afterEach(() => {});
    afterAll(() => {});

    describe('getTemplates', () => {
      it('shouldReturnAllPresetTemplates', 0, () => {
        const list: IPresetTemplate[] = strategy.getTemplates();
        expect(list.length).assertEqual(25);
      });

      it('shouldReturnSameCountAsConstants', 0, () => {
        expect(strategy.getTemplates().length).assertEqual(TemplateConstants.getAllTemplates().length);
      });

      it('shouldIncludeGeneralTemplate', 0, () => {
        const list: IPresetTemplate[] = strategy.getTemplates();
        const ids: string[] = list.map((t: IPresetTemplate) => t.id);
        expect(ids.includes('general')).assertTrue();
      });
    });

    describe('supports', () => {
      it('shouldReturnTrueForPresetTemplate', 0, () => {
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0, standardFields: {}, customFields: []
        };
        expect(strategy.supports(preset as ITemplate)).assertTrue();
      });

      it('shouldReturnTrueForRealPresetTemplate', 0, () => {
        expect(strategy.supports(TemplateConstants.GENERAL as ITemplate)).assertTrue();
      });

      it('shouldReturnFalseForUserTemplate', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(strategy.supports(user as ITemplate)).assertFalse();
      });

      it('shouldReturnFalseForEmptyObject', 0, () => {
        expect(strategy.supports({} as ITemplate)).assertFalse();
      });
    });

    describe('getTemplateName', () => {
      it('shouldReturnStringForPresetTemplate', 0, () => {
        const name: string = strategy.getTemplateName(TemplateConstants.GENERAL as ITemplate);
        expect(typeof name === 'string').assertTrue();
      });

      it('shouldReturnStringForCustomStringName', 0, () => {
        const preset: IPresetTemplate = {
          id: 'test', name: 'CustomName', iconId: 0, standardFields: {}, customFields: []
        };
        expect(strategy.getTemplateName(preset as ITemplate)).assertEqual('CustomName');
      });

      it('shouldReturnEmptyStringForUserTemplate', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(strategy.getTemplateName(user as ITemplate)).assertEqual('');
      });
    });

    describe('getTemplateIconId', () => {
      it('shouldReturnIconIdForPresetTemplate', 0, () => {
        expect(strategy.getTemplateIconId(TemplateConstants.GENERAL as ITemplate))
          .assertEqual(TemplateConstants.GENERAL.iconId);
      });

      it('shouldReturnIconIdForCustomPreset', 0, () => {
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 99, standardFields: {}, customFields: []
        };
        expect(strategy.getTemplateIconId(preset as ITemplate)).assertEqual(99);
      });

      it('shouldReturnZeroForUserTemplate', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 55,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(strategy.getTemplateIconId(user as ITemplate)).assertEqual(0);
      });
    });

    describe('applyTemplate', () => {
      it('shouldNoOpForUnsupportedTemplate', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: { title: 'X' },
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate);
        // KdbxEntry.create 预置 Title 为空串
        expect(entry.fields.get('Title')).assertEqual('');
      });

      it('shouldApplyStandardFields', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0,
          standardFields: { title: 'PT', username: 'PU', password: 'PP', url: 'https://p', notes: 'PN' },
          customFields: []
        };
        strategy.applyTemplate(entry, preset as ITemplate);
        expect(entry.fields.get('Title')).assertEqual('PT');
        expect(entry.fields.get('UserName')).assertEqual('PU');
        expect(KdbxUtils.getValueString(entry.fields.get('Password'))).assertEqual('PP');
        expect(entry.fields.get('URL')).assertEqual('https://p');
        expect(entry.fields.get('Notes')).assertEqual('PN');
      });

      it('shouldSkipEmptyStandardFields', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0,
          standardFields: { title: '', username: '' },
          customFields: []
        };
        strategy.applyTemplate(entry, preset as ITemplate);
        expect(entry.fields.get('Title')).assertEqual('');
        expect(entry.fields.get('UserName')).assertEqual('');
      });

      it('shouldNotOverwriteExistingWhenOverwriteFalse', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'Existing');
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0,
          standardFields: { title: 'New' },
          customFields: []
        };
        strategy.applyTemplate(entry, preset as ITemplate, {
          overwriteExisting: false, copyTags: true, copyIcon: true, copyExpiry: false
        });
        expect(entry.fields.get('Title')).assertEqual('Existing');
      });

      it('shouldOverwriteExistingWhenOverwriteTrue', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'Existing');
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0,
          standardFields: { title: 'New' },
          customFields: []
        };
        strategy.applyTemplate(entry, preset as ITemplate, {
          overwriteExisting: true, copyTags: true, copyIcon: true, copyExpiry: false
        });
        expect(entry.fields.get('Title')).assertEqual('New');
      });

      it('shouldApplyCustomFields', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0,
          standardFields: {},
          customFields: [
            { key: 'cf1', value: 'v1', isProtected: false },
            { key: 'cf2', value: 'v2', isProtected: true }
          ]
        };
        strategy.applyTemplate(entry, preset as ITemplate);
        expect(entry.fields.get('cf1')).assertEqual('v1');
        expect(KdbxUtils.getValueString(entry.fields.get('cf2'))).assertEqual('v2');
      });

      it('shouldSkipEmptyCustomFields', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0,
          standardFields: {},
          customFields: []
        };
        strategy.applyTemplate(entry, preset as ITemplate);
        expect(entry).not().assertNull();
      });

      it('shouldApplyIconWhenCopyIconTrue', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 33,
          standardFields: {},
          customFields: []
        };
        strategy.applyTemplate(entry, preset as ITemplate);
        expect(entry.icon).assertEqual(33);
      });

      it('shouldSkipIconWhenCopyIconFalse', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 33,
          standardFields: {},
          customFields: []
        };
        strategy.applyTemplate(entry, preset as ITemplate, {
          overwriteExisting: false, copyTags: true, copyIcon: false, copyExpiry: false
        });
        expect(entry.icon).assertEqual(0);
      });

      it('shouldApplyTagsWhenCopyTagsTrue', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0,
          standardFields: {},
          customFields: [],
          tags: ['pt1', 'pt2']
        };
        strategy.applyTemplate(entry, preset as ITemplate);
        expect(entry.fields.get('Tags')).assertEqual('pt1,pt2');
      });

      it('shouldSkipTagsWhenCopyTagsFalse', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0,
          standardFields: {},
          customFields: [],
          tags: ['pt1']
        };
        strategy.applyTemplate(entry, preset as ITemplate, {
          overwriteExisting: false, copyTags: false, copyIcon: true, copyExpiry: false
        });
        expect(entry.fields.get('Tags')).assertUndefined();
      });

      it('shouldNotOverwriteTagsWhenOverwriteFalse', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Tags', 'existing');
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0,
          standardFields: {},
          customFields: [],
          tags: ['new']
        };
        strategy.applyTemplate(entry, preset as ITemplate, {
          overwriteExisting: false, copyTags: true, copyIcon: true, copyExpiry: false
        });
        expect(entry.fields.get('Tags')).assertEqual('existing');
      });

      it('shouldOverwriteTagsWhenOverwriteTrue', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Tags', 'existing');
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 0,
          standardFields: {},
          customFields: [],
          tags: ['new']
        };
        strategy.applyTemplate(entry, preset as ITemplate, {
          overwriteExisting: true, copyTags: true, copyIcon: true, copyExpiry: false
        });
        expect(entry.fields.get('Tags')).assertEqual('new');
      });

      it('shouldApplyRealEmailTemplate', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        strategy.applyTemplate(entry, TemplateConstants.EMAIL as ITemplate);
        expect(entry.fields.get('smtp_port')).assertEqual('465');
        expect(entry.fields.get('imap_port')).assertEqual('993');
        expect(entry.icon).assertEqual(TemplateConstants.EMAIL.iconId);
      });

      it('shouldApplyRealBankCardTemplate', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        strategy.applyTemplate(entry, TemplateConstants.BANK_CARD as ITemplate);
        expect(entry.fields.get('bank_card_number')).not().assertNull();
        expect(KdbxUtils.getValueString(entry.fields.get('cvv'))).assertEqual('');
        expect(entry.icon).assertEqual(TemplateConstants.BANK_CARD.iconId);
      });

      it('shouldApplyRealIdCardTemplate', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        strategy.applyTemplate(entry, TemplateConstants.ID_CARD as ITemplate);
        expect(entry.fields.get('id_number')).not().assertNull();
        const idField = entry.fields.get('id_number');
        expect(idField instanceof ProtectedValue).assertTrue();
      });
    });

    describe('applyTemplate_with_default_options', () => {
      it('shouldUseDefaultOptionsWhenUndefined', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const preset: IPresetTemplate = {
          id: 'test', name: 'T', iconId: 5,
          standardFields: { title: 'Default' },
          customFields: [{ key: 'cf', value: 'cv', isProtected: false }],
          tags: ['t1']
        };
        strategy.applyTemplate(entry, preset as ITemplate);
        expect(entry.fields.get('Title')).assertEqual('Default');
        expect(entry.fields.get('cf')).assertEqual('cv');
        expect(entry.icon).assertEqual(5);
        expect(entry.fields.get('Tags')).assertEqual('t1');
      });
    });
  });
}
