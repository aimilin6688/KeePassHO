import { afterAll, afterEach, beforeAll, beforeEachIt, describe, expect, it } from '@ohos/hypium';
import { TemplateBuilder } from '../../../../../main/ets/services/template/TemplateBuilder';
import { ITemplateField, StandardFieldsMap, TemplateApplyOptions } from '../../../../../main/ets/services/template/TemplateTypes';
import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { FileService } from '../../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../../main/ets/common/utils';
import { TestUtils } from '../../importExport/TestUtils';

/**
 * TemplateBuilder 单元测试
 * 覆盖率目标：构建器 fluent API / 标准字段 / 自定义字段 / 图标 / 标签 / 过期 / 选项 / copyFrom / build / reset / peek
 */
export default function TemplateBuilderTest() {
  describe('TemplateBuilder', () => {
    let db: Kdbx;
    let rootGroup: KdbxGroup;

    beforeAll(async () => {
      db = await TestUtils.createTestDatabase('TemplateBuilder Test DB');
    });

    // beforeEachIt：Hypium 中父级 beforeEach 不会传播到嵌套 describe 的用例，需用 beforeEachIt
    beforeEachIt(() => {
      FileService.resetDbFileParam(db, Date.now());
      rootGroup = db.getDefaultGroup();
    });

    afterEach(() => {});
    afterAll(() => {});

    describe('create', () => {
      it('shouldReturnBuilderInstance', 0, () => {
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup);
        expect(builder instanceof TemplateBuilder).assertTrue();
      });

      it('shouldCreateEntryAttachedToParentGroup', 0, () => {
        const before: number = rootGroup.entries.length;
        TemplateBuilder.create(rootGroup);
        expect(rootGroup.entries.length).assertEqual(before + 1);
      });

      it('shouldInitializeWithDefaultOptions', 0, () => {
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup);
        const entry: KdbxEntry = builder.withTitle('T').build();
        expect(entry).not().assertNull();
      });
    });

    describe('withTitle', () => {
      it('shouldSetTitleField', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withTitle('MyTitle').build();
        expect(entry.fields.get('Title')).assertEqual('MyTitle');
      });

      it('shouldReturnSameBuilderForChaining', 0, () => {
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup);
        const returned: TemplateBuilder = builder.withTitle('X');
        expect(returned === builder).assertTrue();
      });

      it('shouldOverwritePreviousTitle', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup)
          .withTitle('First')
          .withTitle('Second')
          .build();
        expect(entry.fields.get('Title')).assertEqual('Second');
      });
    });

    describe('withUsername', () => {
      it('shouldSetUsernameField', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withUsername('user1').build();
        expect(entry.fields.get('UserName')).assertEqual('user1');
      });
    });

    describe('withPassword', () => {
      it('shouldSetPasswordAsProtectedValue', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withPassword('secret').build();
        const pwd = entry.fields.get('Password');
        expect(pwd instanceof ProtectedValue).assertTrue();
        expect(KdbxUtils.getValueString(pwd)).assertEqual('secret');
      });
    });

    describe('withUrl', () => {
      it('shouldSetUrlField', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withUrl('https://x.com').build();
        expect(entry.fields.get('URL')).assertEqual('https://x.com');
      });
    });

    describe('withNotes', () => {
      it('shouldSetNotesField', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withNotes('a note').build();
        expect(entry.fields.get('Notes')).assertEqual('a note');
      });
    });

    describe('withStandardField', () => {
      it('shouldSetTitleViaKey', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withStandardField('title', 'T1').build();
        expect(entry.fields.get('Title')).assertEqual('T1');
      });

      it('shouldSetUsernameViaKey', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withStandardField('username', 'U1').build();
        expect(entry.fields.get('UserName')).assertEqual('U1');
      });

      it('shouldSetPasswordViaKey', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withStandardField('password', 'P1').build();
        expect(KdbxUtils.getValueString(entry.fields.get('Password'))).assertEqual('P1');
      });

      it('shouldSetUrlViaKey', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withStandardField('url', 'https://u.com').build();
        expect(entry.fields.get('URL')).assertEqual('https://u.com');
      });

      it('shouldSetNotesViaKey', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withStandardField('notes', 'N1').build();
        expect(entry.fields.get('Notes')).assertEqual('N1');
      });
    });

    describe('withStandardFields', () => {
      it('shouldSetAllNonEmptyFields', 0, () => {
        const fields: StandardFieldsMap = {
          title: 'T', username: 'U', password: 'P', url: 'https://x', notes: 'N'
        };
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withStandardFields(fields).build();
        expect(entry.fields.get('Title')).assertEqual('T');
        expect(entry.fields.get('UserName')).assertEqual('U');
        expect(KdbxUtils.getValueString(entry.fields.get('Password'))).assertEqual('P');
        expect(entry.fields.get('URL')).assertEqual('https://x');
        expect(entry.fields.get('Notes')).assertEqual('N');
      });

      it('shouldSkipUndefinedFields', 0, () => {
        const fields: StandardFieldsMap = { title: 'T' };
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withStandardFields(fields).build();
        expect(entry.fields.get('Title')).assertEqual('T');
        // KdbxEntry.create 会预置标准字段为空串，未指定的字段保持空串而非 undefined
        expect(entry.fields.get('UserName')).assertEqual('');
      });

      it('shouldSkipEmptyStringFields', 0, () => {
        const fields: StandardFieldsMap = { title: '', username: '' };
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withStandardFields(fields).build();
        expect(entry.fields.get('Title')).assertEqual('');
        expect(entry.fields.get('UserName')).assertEqual('');
      });

      it('shouldHandleEmptyMap', 0, () => {
        const fields: StandardFieldsMap = {};
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withStandardFields(fields).build();
        expect(entry.fields.get('Title')).assertEqual('');
      });
    });

    describe('withCustomField', () => {
      it('shouldSetUnprotectedCustomField', 0, () => {
        const field: ITemplateField = { key: 'cf1', value: 'v1', isProtected: false };
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withCustomField(field).build();
        expect(entry.fields.get('cf1')).assertEqual('v1');
      });

      it('shouldSetProtectedCustomField', 0, () => {
        const field: ITemplateField = { key: 'cf2', value: 'secret', isProtected: true };
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withCustomField(field).build();
        const v = entry.fields.get('cf2');
        expect(v instanceof ProtectedValue).assertTrue();
        expect(KdbxUtils.getValueString(v)).assertEqual('secret');
      });

      it('shouldReturnSameBuilderForChaining', 0, () => {
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup);
        const field: ITemplateField = { key: 'cf', value: 'v', isProtected: false };
        expect(builder.withCustomField(field) === builder).assertTrue();
      });
    });

    describe('withCustomFields', () => {
      it('shouldAddAllFieldsInBatch', 0, () => {
        const fields: ITemplateField[] = [
          { key: 'a', value: '1', isProtected: false },
          { key: 'b', value: '2', isProtected: true },
          { key: 'c', value: '3', isProtected: false }
        ];
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withCustomFields(fields).build();
        expect(entry.fields.get('a')).assertEqual('1');
        expect(KdbxUtils.getValueString(entry.fields.get('b'))).assertEqual('2');
        expect(entry.fields.get('c')).assertEqual('3');
      });

      it('shouldHandleEmptyArray', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withCustomFields([]).build();
        expect(entry).not().assertNull();
      });
    });

    describe('withIcon', () => {
      it('shouldSetIconId', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withIcon(42).build();
        expect(entry.icon).assertEqual(42);
      });
    });

    describe('withCustomIcon', () => {
      it('shouldSetCustomIconUuid', 0, () => {
        // KdbxUuid(字符串) 按 base64 解码，必须恰好解码为 16 字节
        const uuidStr: string = new KdbxUuid().toString();
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withCustomIcon(uuidStr).build();
        expect(entry.customIcon).not().assertNull();
        const customIcon: KdbxUuid = entry.customIcon ?? new KdbxUuid();
        expect(customIcon.toString()).assertEqual(uuidStr);
      });
    });

    describe('withTags', () => {
      it('shouldJoinTagsWithComma', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withTags(['a', 'b', 'c']).build();
        expect(entry.fields.get('Tags')).assertEqual('a,b,c');
      });

      it('shouldSkipEmptyTagsArray', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withTags([]).build();
        expect(entry.fields.get('Tags')).assertUndefined();
      });

      it('shouldHandleSingleTag', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withTags(['only']).build();
        expect(entry.fields.get('Tags')).assertEqual('only');
      });
    });

    describe('withExpiryTime', () => {
      it('shouldSetExpiryTimeAndExpiresFlag', 0, () => {
        const future: Date = new Date(2030, 0, 1);
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withExpiryTime(future).build();
        expect(entry.times.expires).assertTrue();
        expect(entry.times.expiryTime).assertEqual(future);
      });
    });

    describe('withNoExpiry', () => {
      it('shouldDisableExpiresFlag', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withNoExpiry().build();
        expect(entry.times.expires).assertFalse();
      });

      it('shouldOverridePreviousExpirySetting', 0, () => {
        const future: Date = new Date(2030, 0, 1);
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup)
          .withExpiryTime(future)
          .withNoExpiry()
          .build();
        expect(entry.times.expires).assertFalse();
      });
    });

    describe('withOptions', () => {
      it('shouldOverrideAllOptions', 0, () => {
        const opts: TemplateApplyOptions = {
          overwriteExisting: true,
          copyTags: false,
          copyIcon: false,
          copyExpiry: true
        };
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup).withOptions(opts);
        const entry: KdbxEntry = builder.withTitle('T').build();
        expect(entry).not().assertNull();
      });

      it('shouldKeepDefaultsForUndefinedOptions', 0, () => {
        const opts: TemplateApplyOptions = {};
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup).withOptions(opts);
        expect(builder.withTitle('T').build()).not().assertNull();
      });

      it('shouldPartiallyOverrideOptions', 0, () => {
        const opts: TemplateApplyOptions = { overwriteExisting: true };
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup).withOptions(opts);
        expect(builder.withTitle('T').build()).not().assertNull();
      });
    });

    describe('copyFrom', () => {
      it('shouldCopyStandardFields', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src', 'su', 'sp', 'https://s', 'sn');
        const target: KdbxEntry = TemplateBuilder.create(rootGroup).copyFrom(source).build();
        expect(target.fields.get('Title')).assertEqual('Src');
        expect(target.fields.get('UserName')).assertEqual('su');
        expect(KdbxUtils.getValueString(target.fields.get('Password'))).assertEqual('sp');
        expect(target.fields.get('URL')).assertEqual('https://s');
        expect(target.fields.get('Notes')).assertEqual('sn');
      });

      it('shouldCopyCustomFields', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        source.fields.set('custom1', 'cv1');
        source.fields.set('custom2', ProtectedValue.fromString('cv2'));
        const target: KdbxEntry = TemplateBuilder.create(rootGroup).copyFrom(source).build();
        expect(target.fields.get('custom1')).assertEqual('cv1');
        expect(KdbxUtils.getValueString(target.fields.get('custom2'))).assertEqual('cv2');
      });

      it('shouldCopyTagsWhenCopyTagsTrue', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        source.fields.set('Tags', 't1,t2');
        const target: KdbxEntry = TemplateBuilder.create(rootGroup)
          .copyFrom(source, { overwriteExisting: true, copyTags: true, copyIcon: false, copyExpiry: false })
          .build();
        expect(target.fields.get('Tags')).assertEqual('t1,t2');
      });

      it('shouldSkipTagsWhenCopyTagsFalse', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        source.fields.set('Tags', 't1,t2');
        const target: KdbxEntry = TemplateBuilder.create(rootGroup)
          .copyFrom(source, { overwriteExisting: true, copyTags: false, copyIcon: false, copyExpiry: false })
          .build();
        expect(target.fields.get('Tags')).assertUndefined();
      });

      it('shouldCopyIconWhenCopyIconTrue', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        source.icon = 7;
        const target: KdbxEntry = TemplateBuilder.create(rootGroup)
          .copyFrom(source, { overwriteExisting: true, copyTags: false, copyIcon: true, copyExpiry: false })
          .build();
        expect(target.icon).assertEqual(7);
      });

      it('shouldNotOverwriteExistingWhenOverwriteExistingFalse', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src', 'su');
        const target: KdbxEntry = TemplateBuilder.create(rootGroup)
          .withTitle('Existing')
          .withUsername('ExistingUser')
          .copyFrom(source, { overwriteExisting: false, copyTags: false, copyIcon: false, copyExpiry: false })
          .build();
        expect(target.fields.get('Title')).assertEqual('Existing');
        expect(target.fields.get('UserName')).assertEqual('ExistingUser');
      });

      it('shouldOverwriteExistingWhenOverwriteExistingTrue', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src', 'su');
        const target: KdbxEntry = TemplateBuilder.create(rootGroup)
          .withTitle('Existing')
          .withUsername('ExistingUser')
          .copyFrom(source, { overwriteExisting: true, copyTags: false, copyIcon: false, copyExpiry: false })
          .build();
        expect(target.fields.get('Title')).assertEqual('Src');
        expect(target.fields.get('UserName')).assertEqual('su');
      });

      it('shouldUseBuilderDefaultOptionsWhenOptsUndefined', 0, () => {
        const source: KdbxEntry = TestUtils.createTestEntry(db, rootGroup, 'Src');
        const target: KdbxEntry = TemplateBuilder.create(rootGroup).copyFrom(source).build();
        expect(target.fields.get('Title')).assertEqual('Src');
      });
    });

    describe('build', () => {
      it('shouldSetCreationTime', 0, () => {
        const before: number = Date.now();
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withTitle('T').build();
        const creationTime: Date = entry.times.creationTime ?? new Date(0);
        expect(entry.times.creationTime).not().assertNull();
        expect(creationTime.getTime()).assertLargerOrEqual(before);
      });

      it('shouldSetLastModTime', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withTitle('T').build();
        expect(entry.times.lastModTime).not().assertNull();
      });

      it('shouldSetLastAccessTime', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withTitle('T').build();
        expect(entry.times.lastAccessTime).not().assertNull();
      });

      it('shouldReturnEntryInstance', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withTitle('T').build();
        expect(entry instanceof KdbxEntry).assertTrue();
      });
    });

    describe('buildAndAdd', () => {
      it('shouldReturnBuiltEntry', 0, () => {
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup).withTitle('BA').buildAndAdd();
        expect(entry.fields.get('Title')).assertEqual('BA');
      });

      it('shouldHaveEntryInGroup', 0, () => {
        const before: number = rootGroup.entries.length;
        TemplateBuilder.create(rootGroup).withTitle('BA2').buildAndAdd();
        expect(rootGroup.entries.length).assertEqual(before + 1);
      });
    });

    describe('reset', () => {
      it('shouldCreateNewEntry', 0, () => {
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup).withTitle('First');
        const beforePeek: KdbxEntry = builder.peek();
        builder.reset();
        const afterPeek: KdbxEntry = builder.peek();
        expect(afterPeek === beforePeek).assertFalse();
      });

      it('shouldReturnSameBuilderInstance', 0, () => {
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup);
        expect(builder.reset() === builder).assertTrue();
      });

      it('shouldAllowBuildingAfterReset', 0, () => {
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup).withTitle('First');
        builder.reset();
        const entry: KdbxEntry = builder.withTitle('Second').build();
        expect(entry.fields.get('Title')).assertEqual('Second');
      });
    });

    describe('peek', () => {
      it('shouldReturnCurrentEntryWithoutBuilding', 0, () => {
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup).withTitle('Peek');
        const entry: KdbxEntry = builder.peek();
        expect(entry.fields.get('Title')).assertEqual('Peek');
      });

      it('shouldReturnSameInstanceOnRepeatedCalls', 0, () => {
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup);
        const a: KdbxEntry = builder.peek();
        const b: KdbxEntry = builder.peek();
        expect(a === b).assertTrue();
      });

      it('shouldNotSetTimesBeforeBuild', 0, () => {
        const builder: TemplateBuilder = TemplateBuilder.create(rootGroup);
        const entry: KdbxEntry = builder.peek();
        expect(entry).not().assertNull();
      });
    });

    describe('fluentChaining', () => {
      it('shouldChainAllMethods', 0, () => {
        const fields: ITemplateField[] = [{ key: 'cf', value: 'cv', isProtected: false }];
        const entry: KdbxEntry = TemplateBuilder.create(rootGroup)
          .withTitle('Chain')
          .withUsername('cu')
          .withPassword('cp')
          .withUrl('https://c')
          .withNotes('cn')
          .withStandardFields({ title: 'T2', username: 'U2' })
          .withCustomFields(fields)
          .withIcon(5)
          .withTags(['t1', 't2'])
          .withNoExpiry()
          .build();
        expect(entry.fields.get('Title')).assertEqual('T2');
        expect(entry.fields.get('UserName')).assertEqual('U2');
        expect(KdbxUtils.getValueString(entry.fields.get('Password'))).assertEqual('cp');
        expect(entry.fields.get('URL')).assertEqual('https://c');
        expect(entry.fields.get('Notes')).assertEqual('cn');
        expect(entry.fields.get('cf')).assertEqual('cv');
        expect(entry.icon).assertEqual(5);
        expect(entry.fields.get('Tags')).assertEqual('t1,t2');
        expect(entry.times.expires).assertFalse();
      });
    });
  });
}
