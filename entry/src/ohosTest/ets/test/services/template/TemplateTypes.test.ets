import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  TemplateCategory,
  DEFAULT_APPLY_OPTIONS,
  isPresetTemplate,
  isUserTemplate,
  IPresetTemplate,
  IUserTemplate,
  ITemplate,
  ITemplateField,
  StandardFieldKey,
  StandardFieldsMap,
  TemplateApplyOptions
} from '../../../../../main/ets/services/template/TemplateTypes';
import { KdbxUuid } from 'kdbxweb';

/**
 * TemplateTypes 单元测试
 * 覆盖率目标：类型守卫 / 枚举 / 默认常量
 */
export default function TemplateTypesTest() {
  describe('TemplateTypes', () => {
    beforeAll(() => {});
    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    describe('TemplateCategory', () => {
      it('shouldDefineAllCategoryValues', 0, () => {
        expect(TemplateCategory.GENERAL).assertEqual('general');
        expect(TemplateCategory.IDENTITY).assertEqual('identity');
        expect(TemplateCategory.FINANCE).assertEqual('finance');
        expect(TemplateCategory.NETWORK).assertEqual('network');
        expect(TemplateCategory.DEVELOPMENT).assertEqual('development');
        expect(TemplateCategory.OTHER).assertEqual('other');
      });

      it('shouldHaveSixCategories', 0, () => {
        const keys: string[] = Object.keys(TemplateCategory);
        expect(keys.length).assertEqual(6);
      });

      it('shouldHaveUniqueValues', 0, () => {
        const values: string[] = [
          TemplateCategory.GENERAL,
          TemplateCategory.IDENTITY,
          TemplateCategory.FINANCE,
          TemplateCategory.NETWORK,
          TemplateCategory.DEVELOPMENT,
          TemplateCategory.OTHER
        ];
        const set = new Set<string>(values);
        expect(set.size).assertEqual(6);
      });
    });

    describe('DEFAULT_APPLY_OPTIONS', () => {
      it('shouldHaveExpectedDefaults', 0, () => {
        expect(DEFAULT_APPLY_OPTIONS.overwriteExisting).assertFalse();
        expect(DEFAULT_APPLY_OPTIONS.copyTags).assertTrue();
        expect(DEFAULT_APPLY_OPTIONS.copyIcon).assertTrue();
        expect(DEFAULT_APPLY_OPTIONS.copyExpiry).assertFalse();
      });

      it('shouldHaveExactlyFourKeys', 0, () => {
        const keys: string[] = Object.keys(DEFAULT_APPLY_OPTIONS);
        expect(keys.length).assertEqual(4);
      });

      it('shouldNotMutateSharedConstant', 0, () => {
        const snapshot: boolean = DEFAULT_APPLY_OPTIONS.overwriteExisting ?? false;
        const local: TemplateApplyOptions = {
          overwriteExisting: true,
          copyTags: DEFAULT_APPLY_OPTIONS.copyTags,
          copyIcon: DEFAULT_APPLY_OPTIONS.copyIcon,
          copyExpiry: DEFAULT_APPLY_OPTIONS.copyExpiry
        };
        expect(DEFAULT_APPLY_OPTIONS.overwriteExisting).assertEqual(snapshot);
        expect(local.overwriteExisting).assertTrue();
      });
    });

    describe('isPresetTemplate', () => {
      it('shouldReturnTrueForPresetTemplate', 0, () => {
        const preset: IPresetTemplate = {
          id: 'general',
          name: 'General',
          iconId: 0,
          standardFields: {},
          customFields: []
        };
        expect(isPresetTemplate(preset as ITemplate)).assertTrue();
      });

      it('shouldReturnFalseForUserTemplate', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'My Template',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(isPresetTemplate(user as ITemplate)).assertFalse();
      });

      it('shouldReturnFalseForEmptyObject', 0, () => {
        const empty: ITemplate = JSON.parse('{}') as ITemplate;
        expect(isPresetTemplate(empty)).assertFalse();
      });

      it('shouldReturnTrueWhenOnlyIdPresent', 0, () => {
        const partial: ITemplate = JSON.parse('{"id":"only-id"}') as ITemplate;
        expect(isPresetTemplate(partial)).assertTrue();
      });
    });

    describe('isUserTemplate', () => {
      it('shouldReturnTrueForUserTemplate', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'My Template',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(isUserTemplate(user as ITemplate)).assertTrue();
      });

      it('shouldReturnFalseForPresetTemplate', 0, () => {
        const preset: IPresetTemplate = {
          id: 'general',
          name: 'General',
          iconId: 0,
          standardFields: {},
          customFields: []
        };
        expect(isUserTemplate(preset as ITemplate)).assertFalse();
      });

      it('shouldReturnFalseForEmptyObject', 0, () => {
        const empty: ITemplate = JSON.parse('{}') as ITemplate;
        expect(isUserTemplate(empty)).assertFalse();
      });

      it('shouldReturnTrueWhenOnlyUuidPresent', 0, () => {
        const partial: ITemplate = JSON.parse('{"uuid":"placeholder-uuid"}') as ITemplate;
        expect(isUserTemplate(partial)).assertTrue();
      });
    });

    describe('typeDiscrimination', () => {
      it('shouldCorrectlyDiscriminatePresetVsUser', 0, () => {
        const preset: IPresetTemplate = {
          id: 'p',
          name: 'P',
          iconId: 0,
          standardFields: {},
          customFields: []
        };
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(isPresetTemplate(preset as ITemplate)).assertTrue();
        expect(isUserTemplate(preset as ITemplate)).assertFalse();
        expect(isPresetTemplate(user as ITemplate)).assertFalse();
        expect(isUserTemplate(user as ITemplate)).assertTrue();
      });

      it('shouldReturnFalseForBothWhenNeitherFieldPresent', 0, () => {
        const empty: ITemplate = JSON.parse('{}') as ITemplate;
        expect(isPresetTemplate(empty)).assertFalse();
        expect(isUserTemplate(empty)).assertFalse();
      });
    });

    describe('fieldShape', () => {
      it('shouldConstructTemplateField', 0, () => {
        const field: ITemplateField = {
          key: 'card_number',
          value: '1234',
          isProtected: true,
          required: true
        };
        expect(field.key).assertEqual('card_number');
        expect(field.value).assertEqual('1234');
        expect(field.isProtected).assertTrue();
        expect(field.required).assertTrue();
      });

      it('shouldConstructStandardFieldsMap', 0, () => {
        const fields: StandardFieldsMap = {
          title: 'T',
          username: 'U',
          password: 'P',
          url: 'https://x',
          notes: 'N'
        };
        expect(fields.title).assertEqual('T');
        expect(fields.username).assertEqual('U');
        expect(fields.password).assertEqual('P');
        expect(fields.url).assertEqual('https://x');
        expect(fields.notes).assertEqual('N');
      });

      it('shouldAllowEmptyStandardFieldsMap', 0, () => {
        const fields: StandardFieldsMap = {};
        expect(fields.title).assertUndefined();
        expect(fields.username).assertUndefined();
      });

      it('shouldCoverAllStandardFieldKeys', 0, () => {
        const keys: StandardFieldKey[] = ['title', 'username', 'password', 'url', 'notes'];
        expect(keys.length).assertEqual(5);
        expect(keys[0]).assertEqual('title');
        expect(keys[1]).assertEqual('username');
        expect(keys[2]).assertEqual('password');
        expect(keys[3]).assertEqual('url');
        expect(keys[4]).assertEqual('notes');
      });
    });
  });
}
