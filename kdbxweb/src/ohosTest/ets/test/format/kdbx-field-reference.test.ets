import { describe, expect, it } from '@ohos/hypium';
import {
  createFieldReferenceValue,
  createFieldReferenceValueFromUuid,
  FieldReference,
  FieldReferenceParser,
  FieldReferenceValue,
  isFieldReference,
  isFieldReferenceValue,
  Kdbx,
  KdbxContext,
  KdbxCredentials,
  KdbxEntry,
  KdbxGroup,
  KdbxUuid,
} from '../../../../main/ets/index';

export default function KdbxFieldReferenceTest() {
  describe('FieldReference', () => {
    it('isFieldReferenceValue returns true for FieldReferenceValue', 0, () => {
      const value = {
        ref: { field: 'UserName', entryUuid: 'test' }
      } as FieldReferenceValue;
      expect(isFieldReferenceValue(value)).assertTrue();
    });

    it('isFieldReferenceValue returns false for string', 0, () => {
      expect(isFieldReferenceValue('normal text')).assertFalse();
    });

    it('isFieldReferenceValue returns false for undefined', 0, () => {
      expect(isFieldReferenceValue(undefined)).assertFalse();
    });

    it('isFieldReference returns true for FieldReference', 0, () => {
      const ref: FieldReference = {
        field: 'Password',
        entryUuid: 'test'
      };
      expect(isFieldReference(ref)).assertTrue();
    });

    it('isFieldReference returns false for other objects', 0, () => {
      expect(isFieldReference('bar')).assertFalse();
    });

    it('createFieldReferenceValue creates valid reference', 0, () => {
      const value = createFieldReferenceValue('UserName', 'test');
      expect(isFieldReferenceValue(value)).assertTrue();
      expect(value.ref.field).assertEqual('UserName');
      expect(value.ref.entryUuid).assertEqual('test');
    });

    it('createFieldReferenceValueFromUuid creates valid reference', 0, () => {
      const uuid = new KdbxUuid('AQIDBAUGBwgJCgECAwQFBg==');
      const value = createFieldReferenceValueFromUuid('Password', uuid);
      expect(isFieldReferenceValue(value)).assertTrue();
      expect(value.ref.field).assertEqual('Password');
      expect(value.ref.entryUuid).assertEqual(uuid.id);
    });
  });

  describe('FieldReferenceParser', () => {
    it('parses field reference', 0, () => {
      const ref = FieldReferenceParser.parseFieldRef('{REF:Title@AQIDBAUGBwgJCgECAwQFBg==}');
      expect(ref).not().assertNull();
      expect(ref?.field).assertEqual('Title');
      expect(ref?.entryUuid).assertEqual('AQIDBAUGBwgJCgECAwQFBg==');
    });

    it('parses field reference with UserName', 0, () => {
      const ref = FieldReferenceParser.parseFieldRef('{REF:UserName@test123}');
      expect(ref).not().assertNull();
      expect(ref?.field).assertEqual('UserName');
      expect(ref?.entryUuid).assertEqual('test123');
    });

    it('parses field reference with Password', 0, () => {
      const ref = FieldReferenceParser.parseFieldRef('{REF:Password@abc123}');
      expect(ref).not().assertNull();
      expect(ref?.field).assertEqual('Password');
      expect(ref?.entryUuid).assertEqual('abc123');
    });

    it('returns null for non-reference text', 0, () => {
      const ref = FieldReferenceParser.parseFieldRef('normal text');
      expect(ref).assertNull();
    });

    it('returns null for malformed reference', 0, () => {
      const ref = FieldReferenceParser.parseFieldRef('{REF:Title}');
      expect(ref).assertNull();
    });

    it('returns null for undefined', 0, () => {
      const ref = FieldReferenceParser.parseFieldRef(undefined);
      expect(ref).assertNull();
    });

    it('detects field reference', 0, () => {
      expect(FieldReferenceParser.isFieldReference('{REF:UserName@test}')).assertTrue();
      expect(FieldReferenceParser.isFieldReference('normal text')).assertFalse();
    });

    it('detects non-reference', 0, () => {
      expect(FieldReferenceParser.isFieldReference('{REF:UserName@test}')).assertTrue();
      expect(FieldReferenceParser.isFieldReference('{REF:test}')).assertFalse();
      expect(FieldReferenceParser.isFieldReference('')).assertFalse();
    });

    it('formats field reference', 0, () => {
      const ref: FieldReference = { field: 'Password', entryUuid: 'test' };
      const formatted = FieldReferenceParser.formatFieldRef(ref);
      expect(formatted).assertEqual('{REF:Password@test}');
    });

    it('formats field reference with underscores', 0, () => {
      const ref: FieldReference = { field: 'Custom_Field', entryUuid: 'test' };
      const formatted = FieldReferenceParser.formatFieldRef(ref);
      expect(formatted).assertEqual('{REF:Custom_Field@test}');
    });
  });

  describe('FieldReferenceParser.resolveFieldRef', () => {
    it('resolves field reference to actual value', 0, async () => {
      const credentials = new KdbxCredentials(null);
      const kdbx = Kdbx.create(credentials, 'test');
      const ctx = new KdbxContext({ kdbx });

      // 创建两个Entry
      const group = new KdbxGroup();
      group.uuid = KdbxUuid.random();

      const entry1 = new KdbxEntry();
      entry1.uuid = KdbxUuid.random();
      entry1.setField('Title', 'Entry 1');
      entry1.setField('UserName', 'user1');
      group.entries.push(entry1);

      const entry2 = new KdbxEntry();
      entry2.uuid = KdbxUuid.random();
      entry2.setField('Title', 'Entry 2');
      entry2.setField('UserName', 'user2');
      group.entries.push(entry2);

      kdbx.groups.push(group);
      ctx.buildEntryMap();

      // 创建引用
      const ref: FieldReference = { field: 'UserName', entryUuid: entry1.uuid.id };
      const resolved = FieldReferenceParser.resolveFieldRef(ref, ctx, entry2);

      expect(resolved).assertEqual('user1');
    });

    it('returns empty string for non-existent entry', 0, () => {
      const credentials = new KdbxCredentials(null);
      const kdbx = Kdbx.create(credentials, 'test');
      const ctx = new KdbxContext({ kdbx });

      const group = new KdbxGroup();
      const entry = new KdbxEntry();
      entry.uuid = KdbxUuid.random();
      entry.setField('Title', 'Test');
      group.entries.push(entry);

      kdbx.groups.push(group);
      ctx.buildEntryMap();

      const ref: FieldReference = { field: 'UserName', entryUuid: 'nonexistent' };
      const resolved = FieldReferenceParser.resolveFieldRef(ref, ctx, entry);

      expect(resolved).assertEqual('');
    });

    it('returns empty string for non-existent field', 0, () => {
      const credentials = new KdbxCredentials(null);
      const kdbx = Kdbx.create(credentials, 'test');
      const ctx = new KdbxContext({ kdbx });

      const group = new KdbxGroup();
      const entry = new KdbxEntry();
      entry.uuid = KdbxUuid.random();
      entry.setField('Title', 'Test');
      group.entries.push(entry);

      kdbx.groups.push(group);
      ctx.buildEntryMap();

      const ref: FieldReference = { field: 'NonExistentField', entryUuid: entry.uuid.id };
      const resolved = FieldReferenceParser.resolveFieldRef(ref, ctx, entry);

      expect(resolved).assertEqual('');
    });

    it('handles ProtectedValue', 0, () => {
      const credentials = new KdbxCredentials(null);
      const kdbx = Kdbx.create(credentials, 'test');
      const ctx = new KdbxContext({ kdbx });

      const group = new KdbxGroup();
      const entry1 = new KdbxEntry();
      entry1.uuid = KdbxUuid.random();
      entry1.setField('Password', 'secret123', true);
      group.entries.push(entry1);

      const entry2 = new KdbxEntry();
      entry2.uuid = KdbxUuid.random();
      group.entries.push(entry2);

      kdbx.groups.push(group);
      ctx.buildEntryMap();

      const ref: FieldReference = { field: 'Password', entryUuid: entry1.uuid.id };
      const resolved = FieldReferenceParser.resolveFieldRef(ref, ctx, entry2);

      expect(resolved).assertEqual('secret123');
    });
  });

  describe('KdbxEntry.field.reference.methods', () => {
    it('getFieldValue resolves field reference', 0, () => {
      const credentials = new KdbxCredentials(null);
      const kdbx = Kdbx.create(credentials, 'test');
      const ctx = new KdbxContext({ kdbx });

      const group = new KdbxGroup();
      const entry1 = new KdbxEntry();
      entry1.uuid = KdbxUuid.random();
      entry1.setField('UserName', 'alice');
      group.entries.push(entry1);

      const entry2 = new KdbxEntry();
      entry2.uuid = KdbxUuid.random();
      entry2.setFieldReference('UserName', 'UserName', entry1.uuid.id);
      group.entries.push(entry2);

      kdbx.groups.push(group);
      ctx.buildEntryMap();

      const resolved = entry2.getFieldValue('UserName', ctx);
      expect(resolved).assertEqual('alice');
    });

    it('getFieldValue returns raw value for non-reference', 0, () => {
      const credentials = new KdbxCredentials(null);
      const kdbx = Kdbx.create(credentials, 'test');
      const ctx = new KdbxContext({ kdbx });

      const entry = new KdbxEntry();
      entry.setField('UserName', 'bob');

      const value = entry.getFieldValue('UserName', ctx);
      expect(value).assertEqual('bob');
    });

    it('getRawFieldValue returns FieldReferenceValue', 0, () => {
      const entry = new KdbxEntry();
      entry.setFieldReference('UserName', 'UserName', 'test');

      const rawValue = entry.getRawFieldValue('UserName');
      expect(isFieldReferenceValue(rawValue)).assertTrue();
    });

    it('hasFieldReference detects field reference', 0, () => {
      const entry = new KdbxEntry();
      entry.setFieldReference('UserName', 'UserName', 'test');

      expect(entry.hasFieldReference('UserName')).assertTrue();
      expect(entry.hasFieldReference('Password')).assertFalse();
    });

    it('setFieldReferenceFromUuid creates reference', 0, () => {
      const entry = new KdbxEntry();
      const uuid = new KdbxUuid('AQIDBAUGBwgJCgECAwQFBg==');
      entry.setFieldReferenceFromUuid('Password', 'Password', uuid);

      const rawValue = entry.getRawFieldValue('Password');
      expect(isFieldReferenceValue(rawValue)).assertTrue();
      if (isFieldReferenceValue(rawValue)) {
        expect(rawValue.ref.field).assertEqual('Password');
        expect(rawValue.ref.entryUuid).assertEqual(uuid.id);
      }
    });
  });

  describe('FieldReferenceParser.containsFieldReference', () => {
    it('detects reference in string', 0, () => {
      expect(FieldReferenceParser.containsFieldReference('{REF:Title@test}')).assertTrue();
      expect(FieldReferenceParser.containsFieldReference('normal')).assertFalse();
    });

    it('detects reference in object', 0, () => {
      const value = { ref: { field: 'Title', entryUuid: 'test' } } as FieldReferenceValue;
      expect(FieldReferenceParser.containsFieldReference(value)).assertTrue();
    });

    it('returns false for undefined', 0, () => {
      expect(FieldReferenceParser.containsFieldReference(undefined)).assertFalse();
    });
  });

  describe('FieldReferenceParser.getReferencedEntryUuid', () => {
    it('extracts UUID from string reference', 0, () => {
      const uuid = FieldReferenceParser.getReferencedEntryUuid('{REF:Title@AQIDBAUGBwgJCgECAwQFBg==}');
      expect(uuid).assertEqual('AQIDBAUGBwgJCgECAwQFBg==');
    });

    it('extracts UUID from object reference', 0, () => {
      const value = { ref: { field: 'Title', entryUuid: 'test123' } } as FieldReferenceValue;
      const uuid = FieldReferenceParser.getReferencedEntryUuid(value);
      expect(uuid).assertEqual('test123');
    });

    it('returns null for non-reference', 0, () => {
      const uuid = FieldReferenceParser.getReferencedEntryUuid('normal text');
      expect(uuid).assertNull();
    });
  });
}
