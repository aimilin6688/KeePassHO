import { afterAll, afterEach, beforeAll, beforeEachIt, describe, expect, it } from '@ohos/hypium';
import { UserTemplateStrategy } from '../../../../../../main/ets/services/template/strategies/UserTemplateStrategy';
import {
  ITemplate,
  IUserTemplate,
  IPresetTemplate,
  ITemplateField,
  TemplateApplyOptions
} from '../../../../../../main/ets/services/template/TemplateTypes';
import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { FileService } from '../../../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../../../main/ets/common/utils';
import { TestUtils } from '../../../importExport/TestUtils';

/**
 * UserTemplateStrategy 单元测试
 * 覆盖率目标：getTemplates / applyTemplate（标准/自定义/图标/标签分支） /
 *             supports / getTemplateName / getTemplateIconId / entryToTemplate / createTemplateFromEntry
 */
export default function UserTemplateStrategyTest() {
  describe('UserTemplateStrategy', () => {
    let strategy: UserTemplateStrategy;
    let db: Kdbx;
    let rootGroup: KdbxGroup;

    beforeAll(async () => {
      db = await TestUtils.createTestDatabase('UserStrategy Test DB');
    });

    // beforeEachIt：Hypium 中父级 beforeEach 不会传播到嵌套 describe 的用例，需用 beforeEachIt
    beforeEachIt(() => {
      FileService.resetDbFileParam(db, Date.now());
      rootGroup = db.getDefaultGroup();
      strategy = new UserTemplateStrategy();
    });

    afterEach(() => {});
    afterAll(() => {});

    describe('supports', () => {
      it('shouldReturnTrueForUserTemplate', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(strategy.supports(user as ITemplate)).assertTrue();
      });

      it('shouldReturnFalseForPresetTemplate', 0, () => {
        const preset: IPresetTemplate = {
          id: 'p', name: 'P', iconId: 0, standardFields: {}, customFields: []
        };
        expect(strategy.supports(preset as ITemplate)).assertFalse();
      });

      it('shouldReturnFalseForEmptyObject', 0, () => {
        expect(strategy.supports({} as ITemplate)).assertFalse();
      });
    });

    describe('getTemplateName', () => {
      it('shouldReturnNameForUserTemplate', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'MyName',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(strategy.getTemplateName(user as ITemplate)).assertEqual('MyName');
      });

      it('shouldReturnEmptyStringForPresetTemplate', 0, () => {
        const preset: IPresetTemplate = {
          id: 'p', name: 'P', iconId: 0, standardFields: {}, customFields: []
        };
        expect(strategy.getTemplateName(preset as ITemplate)).assertEqual('');
      });
    });

    describe('getTemplateIconId', () => {
      it('shouldReturnIconIdForUserTemplate', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 42,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(strategy.getTemplateIconId(user as ITemplate)).assertEqual(42);
      });

      it('shouldReturnStringIconId', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 'custom-icon-uuid',
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(strategy.getTemplateIconId(user as ITemplate)).assertEqual('custom-icon-uuid');
      });

      it('shouldReturnZeroForPresetTemplate', 0, () => {
        const preset: IPresetTemplate = {
          id: 'p', name: 'P', iconId: 99, standardFields: {}, customFields: []
        };
        expect(strategy.getTemplateIconId(preset as ITemplate)).assertEqual(0);
      });
    });

    describe('getTemplates', () => {
      it('shouldReturnEmptyWhenNoTemplateGroup', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('NoGroup DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const list: IUserTemplate[] = strategy.getTemplates(localDb);
        expect(list.length).assertEqual(0);
      });

      it('shouldReturnEmptyWhenGroupHasNoTemplateEntries', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('NoFlaggedEntries DB');
        FileService.resetDbFileParam(localDb, Date.now());
        TestUtils.createTestGroup(localDb, localDb.getDefaultGroup(), 'Templates');
        const list: IUserTemplate[] = strategy.getTemplates(localDb);
        expect(list.length).assertEqual(0);
      });

      it('shouldReturnOnlyFlaggedEntries', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('Flagged DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const grp: KdbxGroup = TestUtils.createTestGroup(localDb, localDb.getDefaultGroup(), 'Templates');
        const flagged: KdbxEntry = localDb.createEntry(grp);
        flagged.fields.set('Title', 'Tmpl');
        flagged.fields.set('KeePassHO_Template', 'true');
        const normal: KdbxEntry = localDb.createEntry(grp);
        normal.fields.set('Title', 'Normal');
        const list: IUserTemplate[] = strategy.getTemplates(localDb);
        expect(list.length).assertEqual(1);
        expect(list[0].name).assertEqual('Tmpl');
      });

      it('shouldCollectFromNestedGroups', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('Nested DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const grp: KdbxGroup = TestUtils.createTestGroup(localDb, localDb.getDefaultGroup(), 'Templates');
        const sub: KdbxGroup = TestUtils.createTestGroup(localDb, grp, 'SubTemplates');
        const flagged: KdbxEntry = localDb.createEntry(sub);
        flagged.fields.set('Title', 'Nested');
        flagged.fields.set('KeePassHO_Template', 'true');
        const list: IUserTemplate[] = strategy.getTemplates(localDb);
        expect(list.length).assertEqual(1);
        expect(list[0].name).assertEqual('Nested');
      });

      it('shouldUseMetaEntryTemplatesGroupUuid', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('MetaUuid DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const grp: KdbxGroup = TestUtils.createTestGroup(localDb, localDb.getDefaultGroup(), 'CustomGroupName');
        localDb.meta.entryTemplatesGroup = grp.uuid;
        const flagged: KdbxEntry = localDb.createEntry(grp);
        flagged.fields.set('Title', 'ViaMeta');
        flagged.fields.set('KeePassHO_Template', 'true');
        const list: IUserTemplate[] = strategy.getTemplates(localDb);
        expect(list.length).assertEqual(1);
        expect(list[0].name).assertEqual('ViaMeta');
      });
    });

    describe('applyTemplate', () => {
      it('shouldNoOpForUnsupportedTemplate', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const preset: IPresetTemplate = {
          id: 'p', name: 'P', iconId: 0, standardFields: {}, customFields: []
        };
        strategy.applyTemplate(entry, preset as ITemplate);
        // KdbxEntry.create 预置 Title 为空串
        expect(entry.fields.get('Title')).assertEqual('');
      });

      it('shouldApplyStandardFields', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: { title: 'T', username: 'U', password: 'P', url: 'https://x', notes: 'N' },
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate);
        expect(entry.fields.get('Title')).assertEqual('T');
        expect(entry.fields.get('UserName')).assertEqual('U');
        expect(KdbxUtils.getValueString(entry.fields.get('Password'))).assertEqual('P');
        expect(entry.fields.get('URL')).assertEqual('https://x');
        expect(entry.fields.get('Notes')).assertEqual('N');
      });

      it('shouldSkipEmptyStandardFields', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: { title: '', username: '' },
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate);
        expect(entry.fields.get('Title')).assertEqual('');
        expect(entry.fields.get('UserName')).assertEqual('');
      });

      it('shouldNotOverwriteExistingWhenOverwriteFalse', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'Existing');
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: { title: 'New' },
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate, {
          overwriteExisting: false, copyTags: true, copyIcon: true, copyExpiry: false
        });
        expect(entry.fields.get('Title')).assertEqual('Existing');
      });

      it('shouldOverwriteExistingWhenOverwriteTrue', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'Existing');
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: { title: 'New' },
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate, {
          overwriteExisting: true, copyTags: true, copyIcon: true, copyExpiry: false
        });
        expect(entry.fields.get('Title')).assertEqual('New');
      });

      it('shouldApplyCustomFields', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [
            { key: 'cf1', value: 'v1', isProtected: false },
            { key: 'cf2', value: 'v2', isProtected: true }
          ],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate);
        expect(entry.fields.get('cf1')).assertEqual('v1');
        expect(KdbxUtils.getValueString(entry.fields.get('cf2'))).assertEqual('v2');
      });

      it('shouldSkipEmptyCustomFields', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate);
        expect(entry).not().assertNull();
      });

      it('shouldApplyNumericIcon', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 15,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate);
        expect(entry.icon).assertEqual(15);
      });

      it('shouldParseStringIconId', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: '23',
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate);
        expect(entry.icon).assertEqual(23);
      });

      it('shouldFallbackToZeroForInvalidStringIconId', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 'not-a-number',
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate);
        expect(entry.icon).assertEqual(0);
      });

      it('shouldSkipIconWhenCopyIconFalse', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 15,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate, {
          overwriteExisting: false, copyTags: true, copyIcon: false, copyExpiry: false
        });
        expect(entry.icon).assertEqual(0);
      });

      it('shouldApplyTags', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [],
          tags: ['a', 'b'],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate);
        expect(entry.fields.get('Tags')).assertEqual('a,b');
      });

      it('shouldNotApplyTagsWhenCopyTagsFalse', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [],
          tags: ['a'],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate, {
          overwriteExisting: false, copyTags: false, copyIcon: true, copyExpiry: false
        });
        expect(entry.fields.get('Tags')).assertUndefined();
      });

      it('shouldNotOverwriteExistingTagsWhenOverwriteFalse', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Tags', 'existing');
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [],
          tags: ['new'],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate, {
          overwriteExisting: false, copyTags: true, copyIcon: true, copyExpiry: false
        });
        expect(entry.fields.get('Tags')).assertEqual('existing');
      });

      it('shouldOverwriteExistingTagsWhenOverwriteTrue', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Tags', 'existing');
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [],
          tags: ['new'],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        strategy.applyTemplate(entry, user as ITemplate, {
          overwriteExisting: true, copyTags: true, copyIcon: true, copyExpiry: false
        });
        expect(entry.fields.get('Tags')).assertEqual('new');
      });
    });

    describe('entryToTemplate', () => {
      it('shouldConvertEntryToUserTemplate', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'MyTmpl');
        entry.fields.set('UserName', 'u');
        entry.fields.set('Password', ProtectedValue.fromString('p'));
        entry.fields.set('URL', 'https://x');
        entry.fields.set('Notes', 'n');
        entry.fields.set('custom1', 'cv1');
        entry.fields.set('KeePassHO_Template', 'true');
        const template: IUserTemplate | null = strategy.entryToTemplate(entry);
        expect(template).not().assertNull();
        expect(template?.name).assertEqual('MyTmpl');
        expect(template?.standardFields.username).assertEqual('u');
        expect(template?.standardFields.password).assertEqual('p');
        expect(template?.standardFields.url).assertEqual('https://x');
        expect(template?.standardFields.notes).assertEqual('n');
      });

      it('shouldUseDefaultNameWhenTitleMissing', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const template: IUserTemplate | null = strategy.entryToTemplate(entry);
        expect(template?.name).assertEqual('未命名模板');
      });

      it('shouldCollectCustomFieldsExcludingStandard', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'T');
        entry.fields.set('custom_a', 'a');
        entry.fields.set('custom_b', ProtectedValue.fromString('b'));
        const template: IUserTemplate | null = strategy.entryToTemplate(entry);
        expect(template?.customFields.length).assertEqual(2);
        const keys: string[] = template!.customFields.map((f: ITemplateField) => f.key);
        expect(keys.includes('custom_a')).assertTrue();
        expect(keys.includes('custom_b')).assertTrue();
      });

      it('shouldMarkProtectedCustomFields', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'T');
        entry.fields.set('protected_cf', ProtectedValue.fromString('secret'));
        entry.fields.set('plain_cf', 'plain');
        const template: IUserTemplate | null = strategy.entryToTemplate(entry);
        const protectedField = template?.customFields.find((f: ITemplateField) => f.key === 'protected_cf');
        const plainField = template?.customFields.find((f: ITemplateField) => f.key === 'plain_cf');
        expect(protectedField?.isProtected).assertTrue();
        expect(plainField?.isProtected).assertFalse();
      });

      it('shouldExtractTags', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'T');
        entry.fields.set('Tags', 't1, t2, t3');
        const template: IUserTemplate | null = strategy.entryToTemplate(entry);
        expect(template?.tags).not().assertUndefined();
        expect(template?.tags?.length).assertEqual(3);
        expect(template?.tags?.[0]).assertEqual('t1');
        expect(template?.tags?.[1]).assertEqual('t2');
        expect(template?.tags?.[2]).assertEqual('t3');
      });

      it('shouldReturnUndefinedTagsWhenEmpty', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'T');
        const template: IUserTemplate | null = strategy.entryToTemplate(entry);
        expect(template?.tags).assertUndefined();
      });

      it('shouldUseNumericIconWhenNoCustomIcon', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'T');
        entry.icon = 12;
        const template: IUserTemplate | null = strategy.entryToTemplate(entry);
        expect(template?.iconId).assertEqual(12);
      });

      it('shouldUseCustomIconStringWhenPresent', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'T');
        entry.customIcon = new KdbxUuid();
        const template: IUserTemplate | null = strategy.entryToTemplate(entry);
        expect(typeof template?.iconId).assertEqual('string');
      });

      it('shouldSetCreatedAtAndUpdatedAt', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'T');
        const before: number = Date.now();
        const template: IUserTemplate | null = strategy.entryToTemplate(entry);
        expect(template?.createdAt.getTime()).assertLargerOrEqual(before);
        expect(template?.updatedAt.getTime()).assertLargerOrEqual(before);
      });

      it('shouldReturnEntryUuid', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        entry.fields.set('Title', 'T');
        const template: IUserTemplate | null = strategy.entryToTemplate(entry);
        expect(template?.uuid.equals(entry.uuid)).assertTrue();
      });
    });

    describe('createTemplateFromEntry', () => {
      it('shouldCreateTemplateEntryWithFlag', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        const grp: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const template: KdbxEntry = strategy.createTemplateFromEntry(source, grp, db.meta);
        expect(template.fields.get('KeePassHO_Template')).assertEqual('true');
      });

      it('shouldCopyFieldsFromSource', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src', 'su', 'sp');
        source.fields.set('custom_f', 'cv');
        const grp: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const template: KdbxEntry = strategy.createTemplateFromEntry(source, grp, db.meta);
        expect(template.fields.get('Title')).assertEqual('Src');
        expect(template.fields.get('UserName')).assertEqual('su');
        expect(KdbxUtils.getValueString(template.fields.get('Password'))).assertEqual('sp');
        expect(template.fields.get('custom_f')).assertEqual('cv');
      });

      it('shouldAddEntryToGroupEntries', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        const grp: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const before: number = grp.entries.length;
        strategy.createTemplateFromEntry(source, grp, db.meta);
        expect(grp.entries.length).assertEqual(before + 1);
      });

      it('shouldCopyProtectedFieldsAsProtected', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        source.fields.set('secret', ProtectedValue.fromString('hidden'));
        const grp: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const template: KdbxEntry = strategy.createTemplateFromEntry(source, grp, db.meta);
        expect(template.fields.get('secret') instanceof ProtectedValue).assertTrue();
        expect(KdbxUtils.getValueString(template.fields.get('secret'))).assertEqual('hidden');
      });

      it('shouldCopyIconFromSource', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        source.icon = 25;
        const grp: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const template: KdbxEntry = strategy.createTemplateFromEntry(source, grp, db.meta);
        expect(template.icon).assertEqual(25);
      });

      it('shouldSetCreationAndModTime', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        const grp: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const before: number = Date.now();
        const template: KdbxEntry = strategy.createTemplateFromEntry(source, grp, db.meta);
        const creationTime: Date = template.times.creationTime ?? new Date(0);
        const lastModTime: Date = template.times.lastModTime ?? new Date(0);
        expect(creationTime.getTime()).assertLargerOrEqual(before);
        expect(lastModTime.getTime()).assertLargerOrEqual(before);
      });

      it('shouldUseFileServiceMetaWhenMetaUndefined', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        const grp: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'Templates');
        const template: KdbxEntry = strategy.createTemplateFromEntry(source, grp);
        expect(template.fields.get('KeePassHO_Template')).assertEqual('true');
      });
    });
  });
}
