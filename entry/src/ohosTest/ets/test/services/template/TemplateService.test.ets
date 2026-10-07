import { afterAll, afterEach, beforeAll, beforeEachIt, describe, expect, it } from '@ohos/hypium';
import { TemplateService } from '../../../../../main/ets/services/template/TemplateService';
import {
  ITemplate,
  IPresetTemplate,
  IUserTemplate,
  TemplateApplyOptions,
  TemplateCategory
} from '../../../../../main/ets/services/template/TemplateTypes';
import { TemplateConstants } from '../../../../../main/ets/services/template/TemplateConstants';
import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid } from 'kdbxweb';
import { FileService } from '../../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../../main/ets/common/utils';
import { TestUtils } from '../../importExport/TestUtils';

/**
 * TemplateService 单元测试
 * 覆盖率目标：单例 / 模板获取 / 条目创建 / 模板管理（save/delete/update） /
 *             模板分组管理 / 辅助方法 / cloneEntry / applyTemplateToEntry
 */
export default function TemplateServiceTest() {
  describe('TemplateService', () => {
    let service: TemplateService;
    let db: Kdbx;
    let rootGroup: KdbxGroup;

    beforeAll(async () => {
      service = TemplateService.getInstance();
      db = await TestUtils.createTestDatabase('TemplateService Test DB');
    });

    // beforeEachIt：Hypium 中父级 beforeEach 不会传播到嵌套 describe 的用例，需用 beforeEachIt
    beforeEachIt(() => {
      FileService.resetDbFileParam(db, Date.now());
      rootGroup = db.getDefaultGroup();
    });

    afterEach(() => {});
    afterAll(() => {});

    describe('TEMPLATES_GROUP_NAME', () => {
      it('shouldEqualTemplatesString', 0, () => {
        expect(TemplateService.TEMPLATES_GROUP_NAME).assertEqual('Templates');
      });
    });

    describe('getInstance', () => {
      it('shouldReturnSingletonInstance', 0, () => {
        const a: TemplateService = TemplateService.getInstance();
        const b: TemplateService = TemplateService.getInstance();
        expect(a === b).assertTrue();
      });
    });

    describe('getPresetTemplates', () => {
      it('shouldReturnAllPresetTemplates', 0, () => {
        const list: IPresetTemplate[] = service.getPresetTemplates();
        expect(list.length).assertEqual(25);
      });
    });

    describe('getPresetTemplatesByCategory', () => {
      it('shouldReturnTemplatesForCategory', 0, () => {
        const list: IPresetTemplate[] = service.getPresetTemplatesByCategory(TemplateCategory.DEVELOPMENT);
        expect(list.length).assertEqual(7);
      });

      it('shouldReturnEmptyForUnknownCategory', 0, () => {
        const list: IPresetTemplate[] = service.getPresetTemplatesByCategory('unknown' as TemplateCategory);
        expect(list.length).assertEqual(0);
      });
    });

    describe('getPresetTemplateById', () => {
      it('shouldReturnTemplateForKnownId', 0, () => {
        const t: IPresetTemplate | undefined = service.getPresetTemplateById('general');
        expect(t?.id).assertEqual('general');
      });

      it('shouldReturnUndefinedForUnknownId', 0, () => {
        const t: IPresetTemplate | undefined = service.getPresetTemplateById('nonexistent');
        expect(t).assertUndefined();
      });
    });

    describe('getAllCategories', () => {
      it('shouldReturnSixCategories', 0, () => {
        const cats: TemplateCategory[] = service.getAllCategories();
        expect(cats.length).assertEqual(6);
      });
    });

    describe('getAllTemplates', () => {
      it('shouldReturnPresetPlusUserTemplates', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('getAllTemplates DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const all: ITemplate[] = service.getAllTemplates(localDb);
        expect(all.length).assertEqual(25);
      });

      it('shouldIncludeUserTemplatesAfterSave', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('WithUserTemplates DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const entry: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'MyT', 'u', 'p');
        service.saveAsTemplate(entry, localDb, 'SavedTemplate');
        const all: ITemplate[] = service.getAllTemplates(localDb);
        expect(all.length).assertEqual(26);
      });
    });

    describe('getUserTemplates', () => {
      it('shouldReturnEmptyWhenNoTemplatesGroup', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('NoTemplatesGroup DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const list: IUserTemplate[] = service.getUserTemplates(localDb);
        expect(list.length).assertEqual(0);
      });

      it('shouldReturnEmptyWhenGroupHasNoTemplateEntries', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('EmptyTemplatesGroup DB');
        FileService.resetDbFileParam(localDb, Date.now());
        TestUtils.createTestGroup(localDb, localDb.getDefaultGroup(), 'Templates');
        const list: IUserTemplate[] = service.getUserTemplates(localDb);
        expect(list.length).assertEqual(0);
      });

      it('shouldReturnSavedTemplates', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('WithSavedTemplate DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const entry: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'Src', 'su', 'sp');
        service.saveAsTemplate(entry, localDb, 'T1');
        const list: IUserTemplate[] = service.getUserTemplates(localDb);
        expect(list.length).assertEqual(1);
        expect(list[0].name).assertEqual('T1');
      });
    });

    describe('getUserTemplateById', () => {
      it('shouldReturnTemplateByUuidId', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('GetById DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const entry: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'Src');
        const saved: IUserTemplate | null = service.saveAsTemplate(entry, localDb, 'FindMe');
        expect(saved).not().assertNull();
        const found: IUserTemplate | null = service.getUserTemplateById(localDb, saved!.uuid.id);
        expect(found).not().assertNull();
        expect(found?.name).assertEqual('FindMe');
      });

      it('shouldReturnNullForUnknownId', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('GetByIdNotFound DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const found: IUserTemplate | null = service.getUserTemplateById(localDb, 'nonexistent-uuid');
        expect(found).assertNull();
      });
    });

    describe('createEntryFromTemplate', () => {
      it('shouldCreateEntryFromPresetTemplate', 0, () => {
        const entry: KdbxEntry = service.createEntryFromTemplate(
          TemplateConstants.EMAIL as ITemplate,
          rootGroup
        );
        expect(entry.fields.get('smtp_port')).assertEqual('465');
      });

      it('shouldCreateEntryWithCustomOptions', 0, () => {
        const entry: KdbxEntry = service.createEntryFromTemplate(
          TemplateConstants.EMAIL as ITemplate,
          rootGroup,
          { overwriteExisting: false, copyTags: false, copyIcon: false, copyExpiry: false }
        );
        expect(entry.fields.get('smtp_port')).assertEqual('465');
        expect(entry.icon).assertEqual(0);
      });
    });

    describe('createEntryFromPresetId', () => {
      it('shouldCreateEntryForKnownId', 0, () => {
        const entry: KdbxEntry | null = service.createEntryFromPresetId('email', rootGroup);
        expect(entry).not().assertNull();
        expect(entry?.fields.get('smtp_port')).assertEqual('465');
      });

      it('shouldReturnNullForUnknownId', 0, () => {
        const entry: KdbxEntry | null = service.createEntryFromPresetId('nonexistent', rootGroup);
        expect(entry).assertNull();
      });
    });

    describe('createEmptyEntry', () => {
      it('shouldCreateEntryWithoutFields', 0, () => {
        const before: number = rootGroup.entries.length;
        const entry: KdbxEntry = service.createEmptyEntry(rootGroup);
        expect(entry instanceof KdbxEntry).assertTrue();
        expect(rootGroup.entries.length).assertEqual(before + 1);
      });
    });

    describe('saveAsTemplate', () => {
      it('shouldCreateTemplateGroupAndSaveEntry', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('SaveAsTemplate DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const entry: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'Src', 'su', 'sp');
        const result: IUserTemplate | null = service.saveAsTemplate(entry, localDb, 'MyTemplate');
        expect(result).not().assertNull();
        expect(result?.name).assertEqual('MyTemplate');
      });

      it('shouldSetEntryTemplatesGroupMeta', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('SaveMeta DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const entry: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'Src');
        service.saveAsTemplate(entry, localDb, 'T');
        expect(localDb.meta.entryTemplatesGroup).not().assertNull();
      });

      it('shouldUseEntryTitleWhenTemplateNameNotProvided', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('SaveDefaultName DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const entry: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'OriginalTitle', 'u');
        const result: IUserTemplate | null = service.saveAsTemplate(entry, localDb);
        expect(result).not().assertNull();
        expect(result?.name).assertEqual('OriginalTitle');
      });

      it('shouldCopyFieldsFromSourceEntry', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('SaveCopyFields DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const entry: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'Src', 'su', 'sp', 'https://x', 'sn');
        const result: IUserTemplate | null = service.saveAsTemplate(entry, localDb, 'Copied');
        expect(result?.standardFields.username).assertEqual('su');
        expect(result?.standardFields.password).assertEqual('sp');
        expect(result?.standardFields.url).assertEqual('https://x');
        expect(result?.standardFields.notes).assertEqual('sn');
      });

      it('shouldPreserveExistingEntryTemplatesGroupMeta', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('SavePreserveMeta DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const grp: KdbxGroup = service.getOrCreateTemplatesGroup(localDb);
        const firstUuid: KdbxUuid = grp.uuid;
        const entry: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'Src');
        service.saveAsTemplate(entry, localDb, 'T');
        expect(localDb.meta.entryTemplatesGroup?.equals(firstUuid)).assertTrue();
      });
    });

    describe('deleteUserTemplate', () => {
      it('shouldReturnFalseWhenNoTemplateGroup', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('DeleteNoGroup DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const fake: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'Fake',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(service.deleteUserTemplate(fake, localDb)).assertFalse();
      });

      it('shouldReturnFalseWhenEntryNotFound', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('DeleteNotFound DB');
        FileService.resetDbFileParam(localDb, Date.now());
        service.getOrCreateTemplatesGroup(localDb);
        const fake: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'Fake',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(service.deleteUserTemplate(fake, localDb)).assertFalse();
      });

      it('shouldDeleteSavedTemplate', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('DeleteSuccess DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const entry: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'Src');
        const saved: IUserTemplate | null = service.saveAsTemplate(entry, localDb, 'ToDelete');
        expect(saved).not().assertNull();
        expect(service.deleteUserTemplate(saved!, localDb)).assertTrue();
        expect(service.getUserTemplates(localDb).length).assertEqual(0);
      });
    });

    describe('updateUserTemplate', () => {
      it('shouldReturnNullWhenNoTemplateGroup', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('UpdateNoGroup DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const fake: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'Fake',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        const source: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'NewTitle');
        expect(service.updateUserTemplate(fake, source, localDb)).assertNull();
      });

      it('shouldReturnNullWhenEntryNotFound', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('UpdateNotFound DB');
        FileService.resetDbFileParam(localDb, Date.now());
        service.getOrCreateTemplatesGroup(localDb);
        const fake: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'Fake',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        const source: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'NewTitle');
        expect(service.updateUserTemplate(fake, source, localDb)).assertNull();
      });

      it('shouldUpdateExistingTemplateFields', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('UpdateSuccess DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const entry: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'Original', 'ou');
        const saved: IUserTemplate | null = service.saveAsTemplate(entry, localDb, 'ToUpdate');
        expect(saved).not().assertNull();

        const source: KdbxEntry = TestUtils.createTestEntry(localDb, localDb.getDefaultGroup(), 'UpdatedTitle', 'uu');
        const updated: IUserTemplate | null = service.updateUserTemplate(saved!, source, localDb);
        expect(updated).not().assertNull();
        expect(updated?.name).assertEqual('UpdatedTitle');
      });
    });

    describe('getTemplatesGroup', () => {
      it('shouldReturnNullWhenNoGroupExists', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('GetGroupNone DB');
        FileService.resetDbFileParam(localDb, Date.now());
        expect(service.getTemplatesGroup(localDb)).assertNull();
      });

      it('shouldReturnGroupByName', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('GetGroupByName DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const grp: KdbxGroup = TestUtils.createTestGroup(localDb, localDb.getDefaultGroup(), 'Templates');
        const found: KdbxGroup | null = service.getTemplatesGroup(localDb);
        expect(found).not().assertNull();
        expect(found?.uuid.equals(grp.uuid)).assertTrue();
      });

      it('shouldReturnGroupByMetaUuid', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('GetGroupByMeta DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const grp: KdbxGroup = service.getOrCreateTemplatesGroup(localDb);
        const found: KdbxGroup | null = service.getTemplatesGroup(localDb);
        expect(found).not().assertNull();
        expect(found?.uuid.equals(grp.uuid)).assertTrue();
      });
    });

    describe('getOrCreateTemplatesGroup', () => {
      it('shouldCreateNewGroupWhenNoneExists', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('CreateGroup DB');
        FileService.resetDbFileParam(localDb, Date.now());
        expect(service.getTemplatesGroup(localDb)).assertNull();
        const grp: KdbxGroup = service.getOrCreateTemplatesGroup(localDb);
        expect(grp).not().assertNull();
        expect(grp.name).assertEqual('Templates');
        expect(localDb.meta.entryTemplatesGroup).not().assertNull();
      });

      it('shouldReturnExistingGroupOnSecondCall', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('CreateGroupTwice DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const first: KdbxGroup = service.getOrCreateTemplatesGroup(localDb);
        const second: KdbxGroup = service.getOrCreateTemplatesGroup(localDb);
        expect(first.uuid.equals(second.uuid)).assertTrue();
      });

      it('shouldSetFolderIcon', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('CreateGroupIcon DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const grp: KdbxGroup = service.getOrCreateTemplatesGroup(localDb);
        expect(grp.icon).assertEqual(48);
      });
    });

    describe('isTemplatesGroup', () => {
      it('shouldReturnTrueForGroupNamedTemplates', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('IsGroupByName DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const grp: KdbxGroup = TestUtils.createTestGroup(localDb, localDb.getDefaultGroup(), 'Templates');
        expect(service.isTemplatesGroup(grp, localDb)).assertTrue();
      });

      it('shouldReturnTrueForGroupMatchingMetaUuid', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('IsGroupByMeta DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const grp: KdbxGroup = service.getOrCreateTemplatesGroup(localDb);
        expect(service.isTemplatesGroup(grp, localDb)).assertTrue();
      });

      it('shouldReturnFalseForOtherGroup', 0, async () => {
        const localDb: Kdbx = await TestUtils.createTestDatabase('IsGroupFalse DB');
        FileService.resetDbFileParam(localDb, Date.now());
        const grp: KdbxGroup = TestUtils.createTestGroup(localDb, localDb.getDefaultGroup(), 'Other');
        expect(service.isTemplatesGroup(grp, localDb)).assertFalse();
      });
    });

    describe('getTemplateName', () => {
      it('shouldReturnNameForCustomStringPresetName', 0, () => {
        const preset: IPresetTemplate = {
          id: 'test',
          name: 'TestName',
          iconId: 0,
          standardFields: {},
          customFields: []
        };
        expect(service.getTemplateName(preset as ITemplate)).assertEqual('TestName');
      });

      it('shouldReturnNameForUserTemplate', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'UserTmpl',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        expect(service.getTemplateName(user as ITemplate)).assertEqual('UserTmpl');
      });

      it('shouldReturnStringForPresetTemplate', 0, () => {
        const name: string = service.getTemplateName(TemplateConstants.GENERAL as ITemplate);
        expect(typeof name === 'string').assertTrue();
      });
    });

    describe('getTemplateIconId', () => {
      it('shouldReturnIconIdForPresetTemplate', 0, () => {
        const icon: number | string = service.getTemplateIconId(TemplateConstants.GENERAL as ITemplate);
        expect(icon).assertEqual(TemplateConstants.GENERAL.iconId);
      });

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
        expect(service.getTemplateIconId(user as ITemplate)).assertEqual(42);
      });
    });

    describe('cloneEntry', () => {
      it('shouldCloneWithoutRenamingByDefault', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Original', 'u');
        const clone: KdbxEntry = service.cloneEntry(source, rootGroup);
        expect(clone.fields.get('Title')).assertEqual('Original');
        expect(clone.fields.get('UserName')).assertEqual('u');
      });

      it('shouldCloneWithRenameWhenRequested', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Original');
        const clone: KdbxEntry = service.cloneEntry(source, rootGroup, true);
        expect(clone.fields.get('Title')).assertEqual('Original - 副本');
      });
    });

    describe('applyTemplateToEntry', () => {
      it('shouldApplyPresetTemplateToEntry', 0, () => {
        const entry: KdbxEntry = service.createEmptyEntry(rootGroup);
        service.applyTemplateToEntry(entry, TemplateConstants.EMAIL as ITemplate);
        expect(entry.fields.get('smtp_port')).assertEqual('465');
      });

      it('shouldApplyPresetTemplateWithOptions', 0, () => {
        const entry: KdbxEntry = service.createEmptyEntry(rootGroup);
        const opts: TemplateApplyOptions = {
          overwriteExisting: false,
          copyTags: false,
          copyIcon: false,
          copyExpiry: false
        };
        service.applyTemplateToEntry(entry, TemplateConstants.EMAIL as ITemplate, opts);
        expect(entry.fields.get('smtp_port')).assertEqual('465');
      });

      it('shouldApplyUserTemplateToEntry', 0, () => {
        const entry: KdbxEntry = service.createEmptyEntry(rootGroup);
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'UT',
          iconId: 5,
          standardFields: { title: 'Applied', username: 'applied_user' },
          customFields: [{ key: 'ucf', value: 'ucv', isProtected: false }],
          tags: ['ut1', 'ut2'],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        service.applyTemplateToEntry(entry, user as ITemplate);
        expect(entry.fields.get('Title')).assertEqual('Applied');
        expect(entry.fields.get('UserName')).assertEqual('applied_user');
        expect(entry.fields.get('ucf')).assertEqual('ucv');
        expect(entry.fields.get('Tags')).assertEqual('ut1,ut2');
        expect(entry.icon).assertEqual(5);
      });

      it('shouldNotApplyWhenEntryHasExistingAndNoOverwrite', 0, () => {
        const entry: KdbxEntry = service.createEmptyEntry(rootGroup);
        entry.fields.set('Title', 'Existing');
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'UT',
          iconId: 0,
          standardFields: { title: 'New' },
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        service.applyTemplateToEntry(entry, user as ITemplate, {
          overwriteExisting: false,
          copyTags: true,
          copyIcon: true,
          copyExpiry: false
        });
        expect(entry.fields.get('Title')).assertEqual('Existing');
      });
    });
  });
}
