import { describe, expect, it, beforeAll } from "@ohos/hypium";
import { ByteUtils, Kdbx, Credentials, KdbxFieldReference, ProtectedValue } from "../../../../main/ets/index";
import { TestResources } from "../test-support/test-resources";

export default function KdbxFieldReferenceTest() {
  describe('KdbxFieldReference', () => {
    let db: Kdbx;

    beforeAll(async () => {
      const cred = new Credentials(
        ProtectedValue.fromString('demo'),
        TestResources.demoKey
      );
      db = await Kdbx.load(TestResources.demoKdbx, cred);
    });

    describe('resolveFieldRefsInText', () => {
      it('returns original text for null input', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('', db, entry);
        expect(result).assertEqual('');
      });

      it('returns original text for non-reference text', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('Hello World', db, entry);
        expect(result).assertEqual('Hello World');
      });

      it('resolves simple field reference by Title', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:T@T:Sample Entry}', db, entry);
        expect(result).assertEqual('Sample Entry');
      });

      it('resolves field reference by UserName', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:U@T:Sample Entry}', db, entry);
        expect(result).assertEqual('User Name');
      });

      it('resolves field reference by URL', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:A@T:Sample Entry}', db, entry);
        expect(result).assertEqual('http://keepass.info/');
      });

      it('resolves field reference by Notes', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:N@T:Sample Entry}', db, entry);
        expect(result).assertEqual('Notes');
      });

      it('resolves embedded reference in text', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText(
          'User: {REF:U@T:Sample Entry}, URL: {REF:A@T:Sample Entry}',
          db,
          entry
        );
        expect(result).assertEqual('User: User Name, URL: http://keepass.info/');
      });

      it('returns original text for invalid reference format', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:X@T:Test}', db, entry);
        expect(result).assertEqual('{REF:X@T:Test}');
      });

      it('returns original text for non-matching search', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:T@T:NonExistent}', db, entry);
        expect(result).assertEqual('{REF:T@T:NonExistent}');
      });

      it('resolves local placeholder for string field', 0, () => {
        const entry = db.groups[0].entries[0];
        entry.fields.set('CustomField', 'CustomValue');
        const result = KdbxFieldReference.resolveFieldRefsInText('{S:CustomField}', db, entry);
        expect(result).assertEqual('CustomValue');
      });

      it('resolves local placeholder for ProtectedValue field', 0, () => {
        const entry = db.groups[0].entries[0];
        const protectedValue = ProtectedValue.fromString('SecretPassword');
        entry.fields.set('SecretField', protectedValue);
        const result = KdbxFieldReference.resolveFieldRefsInText('{S:SecretField}', db, entry);
        expect(result).assertEqual('SecretPassword');
      });

      it('returns original text for non-existent local placeholder', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{S:NonExistent}', db, entry);
        expect(result).assertEqual('{S:NonExistent}');
      });

      it('resolves mixed references and local placeholders', 0, () => {
        const entry = db.groups[0].entries[0];
        entry.fields.set('MyField', 'MyValue');
        const result = KdbxFieldReference.resolveFieldRefsInText(
          'Local: {S:MyField}, Remote: {REF:U@T:Sample Entry}',
          db,
          entry
        );
        expect(result).assertEqual('Local: MyValue, Remote: User Name');
      });
    });

    describe('field.code.mapping', () => {
      it('T maps to Title', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:T@T:Sample Entry}', db, entry);
        expect(result).assertEqual('Sample Entry');
      });

      it('U maps to UserName', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:U@T:Sample Entry}', db, entry);
        expect(result).assertEqual('User Name');
      });

      it('P maps to Password', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:P@T:Sample Entry}', db, entry);
        expect(result).assertEqual('Password');
      });

      it('A maps to URL', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:A@T:Sample Entry}', db, entry);
        expect(result).assertEqual('http://keepass.info/');
      });

      it('N maps to Notes', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:N@T:Sample Entry}', db, entry);
        expect(result).assertEqual('Notes');
      });

      it('I maps to UUID', 0, () => {
        const entry = db.groups[0].entries[0];
        const targetEntry = db.groups[0].entries[0];
        const uuidStr = targetEntry.uuid.id;
        const result = KdbxFieldReference.resolveFieldRefsInText(`{REF:T@I:${uuidStr}}`, db, entry);
        expect(result).assertEqual('Sample Entry');
      });
    });

    describe('search.by.different.fields', () => {
      it('searches by Title (T)', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:U@T:Sample Entry}', db, entry);
        expect(result).assertEqual('User Name');
      });

      it('searches by UserName (U)', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:T@U:User Name}', db, entry);
        expect(result).assertEqual('Sample Entry');
      });

      it('searches by URL (A)', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:T@A:http://example.com}', db, entry);
        expect(result).assertEqual('{REF:T@A:http://example.com}');
      });

      it('searches by Notes (N)', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:T@N:sample entry notes}', db, entry);
        expect(result).assertEqual('{REF:T@N:sample entry notes}');
      });

      it('searches by UUID (I)', 0, () => {
        const entry = db.groups[0].entries[0];
        const targetEntry = db.groups[0].entries[0];
        const uuidStr = targetEntry.uuid.id;
        const result = KdbxFieldReference.resolveFieldRefsInText(`{REF:U@I:${uuidStr}}`, db, entry);
        expect(result).assertEqual('User Name');
      });
    });

    describe('search.by.custom.field.O', () => {
      it('searches by custom field name', 0, () => {
        const entry = db.groups[0].entries[0];
        const targetEntry = db.groups[0].entries[0];
        targetEntry.fields.set('CustomTestField', 'TestValue');
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:T@O:CustomTestField}', db, entry);
        expect(result).assertEqual('Sample Entry');
      });
    });

    describe('circular.reference.detection', () => {
      it('handles circular references gracefully', 0, () => {
        const group = db.groups[0];
        const entry1 = db.createEntry(group);
        entry1.fields.set('Title', 'Entry1');
        entry1.fields.set('RefField', '{REF:T@T:Entry2}');

        const entry2 = db.createEntry(group);
        entry2.fields.set('Title', 'Entry2');
        entry2.fields.set('RefField', '{REF:T@T:Entry1}');

        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:T@T:Entry1}', db, entry2);
        expect(result).assertEqual('Entry1');
      });
    });

    describe('case.insensitivity', () => {
      it('handles lowercase field codes', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:t@t:Sample Entry}', db, entry);
        expect(result).assertEqual('Sample Entry');
      });

      it('handles mixed case field codes', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:U@T:Sample Entry}', db, entry);
        expect(result).assertEqual('User Name');
      });
    });

    describe('protected.value.handling', () => {
      it('resolves ProtectedValue fields', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:P@T:Sample Entry}', db, entry);
        expect(result).assertEqual('Password');
      });
    });

    describe('nested.group.search', () => {
      it('finds entries in nested groups', 0, () => {
        const rootGroup = db.groups[0];
        if (rootGroup.groups.length > 0) {
          const nestedGroup = rootGroup.groups[0];
          if (nestedGroup.entries.length > 0) {
            const nestedEntry = nestedGroup.entries[0];
            const title = nestedEntry.fields.get('Title');
            if (typeof title === 'string') {
              const entry = db.groups[0].entries[0];
              const result = KdbxFieldReference.resolveFieldRefsInText(`{REF:U@T:${title}}`, db, entry);
              expect(result.length).assertLarger(0);
            }
          }
        }
      });
    });

    describe('invalid.codes', () => {
      it('returns original text for invalid WantedField code O', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:O@T:Sample Entry}', db, entry);
        expect(result).assertEqual('{REF:O@T:Sample Entry}');
      });

      it('returns original text for invalid field code', 0, () => {
        const entry = db.groups[0].entries[0];
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:X@T:Test}', db, entry);
        expect(result).assertEqual('{REF:X@T:Test}');
      });
    });

    describe('hex.uuid.support', () => {
      it('searches by UUID with hex format', 0, () => {
        const entry = db.groups[0].entries[0];
        const targetEntry = db.groups[0].entries[0];
        const uuidBase64 = targetEntry.uuid.id;
        // Base64 转十六进制：先转字节数组，再转十六进制字符串
        const uuidBytes = ByteUtils.base64ToBytes(uuidBase64);
        const hexUuid = ByteUtils.bytesToHex(uuidBytes).toUpperCase();
        const result = KdbxFieldReference.resolveFieldRefsInText(`{REF:U@I:${hexUuid}}`, db, entry);
        expect(result).assertEqual('User Name');
      });

      it('searches by UUID with lowercase hex format', 0, () => {
        const entry = db.groups[0].entries[0];
        const targetEntry = db.groups[0].entries[0];
        const uuidBase64 = targetEntry.uuid.id;
        const uuidBytes = ByteUtils.base64ToBytes(uuidBase64);
        const hexUuid = ByteUtils.bytesToHex(uuidBytes).toLowerCase();
        const result = KdbxFieldReference.resolveFieldRefsInText(`{REF:T@I:${hexUuid}}`, db, entry);
        expect(result).assertEqual('Sample Entry');
      });

      it('searches by UUID with mixed case hex format', 0, () => {
        const entry = db.groups[0].entries[0];
        const targetEntry = db.groups[0].entries[0];
        const uuidBase64 = targetEntry.uuid.id;
        const uuidBytes = ByteUtils.base64ToBytes(uuidBase64);
        let hexUuid = ByteUtils.bytesToHex(uuidBytes);
        // 混合大小写
        hexUuid = hexUuid.slice(0, 16).toUpperCase() + hexUuid.slice(16).toLowerCase();
        const result = KdbxFieldReference.resolveFieldRefsInText(`{REF:T@I:${hexUuid}}`, db, entry);
        expect(result).assertEqual('Sample Entry');
      });

      it('returns original text for invalid hex UUID', 0, () => {
        const entry = db.groups[0].entries[0];
        // 无效的十六进制字符串（奇数长度）
        const result = KdbxFieldReference.resolveFieldRefsInText('{REF:T@I:ABCDEF}', db, entry);
        expect(result).assertEqual('{REF:T@I:ABCDEF}');
      });

      it('returns original text for non-matching hex UUID', 0, () => {
        const entry = db.groups[0].entries[0];
        // 有效的十六进制格式，但UUID不存在
        const result = KdbxFieldReference.resolveFieldRefsInText(
          '{REF:T@I:AABBCCDD11223344556677889900AABB}',
          db,
          entry
        );
        expect(result).assertEqual('{REF:T@I:AABBCCDD11223344556677889900AABB}');
      });
    });
  });
}
