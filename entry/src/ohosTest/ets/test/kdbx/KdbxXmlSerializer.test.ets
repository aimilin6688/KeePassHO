/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { KdbxXmlSerializer } from '../../../../main/ets/kdbx/KdbxXmlSerializer';
import { KdbxDatabase } from '../../../../main/ets/kdbx/models/KdbxDatabase';
import { KdbxGroup } from '../../../../main/ets/kdbx/models/KdbxGroup';
import { KdbxEntry } from '../../../../main/ets/kdbx/models/KdbxEntry';
import { Binary } from '../../../../main/ets/kdbx/models/KdbxTypes';
import { InnerRandomStreamID } from '../../../../main/ets/kdbx/KdbxFormat';
import { KdbxUtils } from '../../../../main/ets/kdbx/utils/KdbxUtils';

export default function KdbxXmlSerializerUnitTest() {
  describe('KdbxXmlSerializer', () => {
    let serializer: KdbxXmlSerializer;
    let db: KdbxDatabase;
    let protectedStreamKey: Uint8Array;
    
    // 辅助函数：创建测试数据库
    function createTestDatabase(): KdbxDatabase {
      const testDb = new KdbxDatabase();
      testDb.meta.databaseName = '测试数据库';
      testDb.meta.databaseDescription = '这是一个测试数据库';
      testDb.meta.generator = 'KeePassHO';
      
      // 创建根组
      const rootUuid = new Uint8Array(16);
      KdbxUtils.fillRandom(rootUuid);
      const rootGroup = new KdbxGroup(rootUuid, '根组');
      rootGroup.icon = { id: 0 };
      testDb.root = rootGroup;
      
      // 添加子组
      const subGroupUuid = new Uint8Array(16);
      KdbxUtils.fillRandom(subGroupUuid);
      const subGroup = new KdbxGroup(subGroupUuid, '子组');
      subGroup.icon = { id: 1 };
      rootGroup.addGroup(subGroup);
      
      // 添加条目
      const entryUuid = new Uint8Array(16);
      KdbxUtils.fillRandom(entryUuid);
      const entry = new KdbxEntry(entryUuid, subGroup.uuid);
      entry.icon = { id: 0 };
      entry.fields = [
        { name: 'Title', value: '测试条目', protected: false },
        { name: 'UserName', value: 'testuser', protected: false },
        { name: 'Password', value: 'testpass', protected: true },
        { name: 'URL', value: 'https://example.com', protected: false },
        { name: 'Notes', value: '这是一个测试条目', protected: false }
      ];
      entry.creationTime = new Date(2023, 0, 1);
      entry.lastModifiedTime = new Date(2023, 0, 2);
      entry.lastAccessTime = new Date(2023, 0, 3);
      entry.expiryTime = new Date(2024, 0, 1);
      entry.expires = true;
      
      subGroup.addEntry(entry);
      
      return testDb;
    }
    
    beforeAll(() => {
      // 测试套件开始前的设置
    });
    
    beforeEach(() => {
      // 每个测试用例开始前的设置
      protectedStreamKey = new Uint8Array(32);
      KdbxUtils.fillRandom(protectedStreamKey);
      serializer = new KdbxXmlSerializer(protectedStreamKey, InnerRandomStreamID.CHACHA20);
      db = createTestDatabase();
    });
    
    afterEach(() => {
      // 每个测试用例结束后的清理
    });
    
    afterAll(() => {
      // 测试套件结束后的清理
    });
    
    it('should create serializer with valid parameters', 0, () => {
      expect(serializer).not().assertUndefined();
    });
    
    it('should serialize database to XML', 0, () => {
      // 序列化数据库
      const xml = serializer.serializeToXml(db);
      
      // 验证XML包含必要的元素
      expect(xml).assertContain('<KeePassFile');
      expect(xml).assertContain('<Meta>');
      expect(xml).assertContain('<Root>');
      expect(xml).assertContain('<Group>');
      expect(xml).assertContain('<Entry>');
      expect(xml).assertContain('测试数据库');
      expect(xml).assertContain('根组');
      expect(xml).assertContain('子组');
      expect(xml).assertContain('测试条目');
      expect(xml).assertContain('KeePassHO');
    });
    
    it('should deserialize database from XML', 0, () => {
      // 先序列化数据库
      const xml = serializer.serializeToXml(db);
      
      // 再反序列化
      const deserializedDb = serializer.deserializeFromXml(xml);
      
      // 验证反序列化的数据库
      expect(deserializedDb.meta.databaseName).assertEqual('测试数据库');
      expect(deserializedDb.meta.databaseDescription).assertEqual('这是一个测试数据库');
      expect(deserializedDb.meta.generator).assertEqual('KeePassHO');
      expect(deserializedDb.root.name).assertEqual('根组');
      expect(deserializedDb.root.groups.length).assertEqual(1);
      expect(deserializedDb.root.groups[0].name).assertEqual('子组');
      expect(deserializedDb.root.groups[0].entries.length).assertEqual(1);
    });
    
    it('should serialize and deserialize entry fields correctly', 0, () => {
      // 序列化和反序列化
      const xml = serializer.serializeToXml(db);
      const deserializedDb = serializer.deserializeFromXml(xml);
      
      // 获取原始条目和反序列化后的条目
      const originalEntry = db.root.groups[0].entries[0];
      const deserializedEntry = deserializedDb.root.groups[0].entries[0];
      
      // 验证字段
      expect(deserializedEntry.fields.length).assertEqual(originalEntry.fields.length);
      
      // 验证每个字段
      for (const field of originalEntry.fields) {
        const deserializedField = deserializedEntry.fields.find(f => f.name === field.name);
        expect(deserializedField).not().assertUndefined();
        expect(deserializedField.value).assertEqual(field.value);
        expect(deserializedField.protected).assertEqual(field.protected);
      }
    });
    
    it('should serialize and deserialize entry times correctly', 0, () => {
      // 序列化和反序列化
      const xml = serializer.serializeToXml(db);
      const deserializedDb = serializer.deserializeFromXml(xml);
      
      // 获取原始条目和反序列化后的条目
      const originalEntry = db.root.groups[0].entries[0];
      const deserializedEntry = deserializedDb.root.groups[0].entries[0];
      
      // 验证时间字段
      expect(deserializedEntry.creationTime.getTime()).assertEqual(originalEntry.creationTime.getTime());
      expect(deserializedEntry.lastModifiedTime.getTime()).assertEqual(originalEntry.lastModifiedTime.getTime());
      expect(deserializedEntry.lastAccessTime.getTime()).assertEqual(originalEntry.lastAccessTime.getTime());
      expect(deserializedEntry.expiryTime.getTime()).assertEqual(originalEntry.expiryTime.getTime());
      expect(deserializedEntry.expires).assertEqual(originalEntry.expires);
    });
    
    it('should handle protected fields correctly', 0, () => {
      // 序列化数据库
      const xml = serializer.serializeToXml(db);
      
      // 验证受保护字段被加密
      expect(xml).assertContain('Protected="True"');
      expect(xml).assertNotContain('testpass'); // 密码不应该以明文形式出现
      
      // 反序列化并验证字段被正确解密
      const deserializedDb = serializer.deserializeFromXml(xml);
      const deserializedEntry = deserializedDb.root.groups[0].entries[0];
      const passwordField = deserializedEntry.fields.find(f => f.name === 'Password');
      
      expect(passwordField).not().assertUndefined();
      expect(passwordField.value).assertEqual('testpass');
      expect(passwordField.protected).assertEqual(true);
    });
    
    it('should handle custom icons', 0, () => {
      // 添加自定义图标
      const iconUuid = new Uint8Array(16);
      KdbxUtils.fillRandom(iconUuid);
      const iconData = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
      db.meta.customIcons.set(iconUuid, iconData);
      
      // 使用自定义图标
      db.root.icon = { uuid: iconUuid };
      
      // 序列化数据库
      const xml = serializer.serializeToXml(db);
      
      // 验证自定义图标被包含在XML中
      expect(xml).assertContain('<CustomIcons>');
      expect(xml).assertContain('<Icon>');
      expect(xml).assertContain('<UUID>');
      expect(xml).assertContain('<Data>');
      
      // 反序列化并验证自定义图标
      const deserializedDb = serializer.deserializeFromXml(xml);
      expect(deserializedDb.meta.customIcons.size).assertGreaterThan(0);
      
      // 验证根组使用了自定义图标
      expect(deserializedDb.root.icon).not().assertUndefined();
      expect(deserializedDb.root.icon.uuid).not().assertUndefined();
      
      // 验证图标数据
      const deserializedIconUuid = deserializedDb.root.icon.uuid;
      const deserializedIconData = deserializedDb.meta.customIcons.get(deserializedIconUuid);
      expect(deserializedIconData).not().assertUndefined();
      expect(deserializedIconData.length).assertEqual(iconData.length);
      
      // 比较图标数据
      for (let i = 0; i < iconData.length; i++) {
        expect(deserializedIconData[i]).assertEqual(iconData[i]);
      }
    });
    
    it('should handle empty database', 0, () => {
      // 创建空数据库
      const emptyDb = new KdbxDatabase();
      const rootUuid = new Uint8Array(16);
      KdbxUtils.fillRandom(rootUuid);
      emptyDb.root = new KdbxGroup(rootUuid, '根组');
      
      // 序列化和反序列化
      const xml = serializer.serializeToXml(emptyDb);
      const deserializedDb = serializer.deserializeFromXml(xml);
      
      // 验证
      expect(deserializedDb.root).not().assertUndefined();
      expect(deserializedDb.root.name).assertEqual('根组');
      expect(deserializedDb.root.groups.length).assertEqual(0);
      expect(deserializedDb.root.entries.length).assertEqual(0);
    });
    
    it('should handle nested groups', 0, () => {
      // 创建嵌套组结构
      const nestedGroupUuid = new Uint8Array(16);
      KdbxUtils.fillRandom(nestedGroupUuid);
      const nestedGroup = new KdbxGroup(nestedGroupUuid, '嵌套组');
      db.root.groups[0].addGroup(nestedGroup);
      
      // 序列化和反序列化
      const xml = serializer.serializeToXml(db);
      const deserializedDb = serializer.deserializeFromXml(xml);
      
      // 验证嵌套组结构
      expect(deserializedDb.root.groups.length).assertEqual(1);
      expect(deserializedDb.root.groups[0].groups.length).assertEqual(1);
      expect(deserializedDb.root.groups[0].groups[0].name).assertEqual('嵌套组');
    });
    
    it('should handle binary attachments', 0, () => {
      // 创建二进制附件
      const attachmentData = new Uint8Array(100);
      KdbxUtils.fillRandom(attachmentData);
      
      // 添加附件到数据库
      const attachmentId = '1';
      db.binaries.set(attachmentId, attachmentData);
      
      // 添加附件引用到条目
      const entry = db.root.groups[0].entries[0];
      entry.binaries.set('attachment.bin', { id: attachmentId });
      
      // 序列化和反序列化
      const xml = serializer.serializeToXml(db);
      const deserializedDb = serializer.deserializeFromXml(xml);
      
      // 验证附件数据
      expect(deserializedDb.binaries.size).assertEqual(1);
      const deserializedAttachmentData = deserializedDb.binaries.get(attachmentId);
      expect(deserializedAttachmentData).not().assertUndefined();
      expect(deserializedAttachmentData.length).assertEqual(attachmentData.length);
      
      // 验证条目的附件引用
      const deserializedEntry = deserializedDb.root.groups[0].entries[0];
      expect(deserializedEntry.binaries.size).assertEqual(1);
      expect(deserializedEntry.binaries.has('attachment.bin')).assertTrue();
      expect(deserializedEntry.binaries.get('attachment.bin').id).assertEqual(attachmentId);
    });
    
    it('should handle error conditions gracefully', 0, () => {
      // 测试无效的XML
      const invalidXml = '<KeePassFile><Invalid></KeePassFile>';
      expect(() => serializer.deserializeFromXml(invalidXml)).toThrow();
      
      // 测试空XML
      expect(() => serializer.deserializeFromXml('')).toThrow();
      
      // 测试null数据库
      expect(() => serializer.serializeToXml(null)).toThrow();
    });
    
    it('should deserialize entry string fields correctly', 0, () => {
      // 创建包含多种字段的条目
      const entryUuid = new Uint8Array(16);
      KdbxUtils.fillRandom(entryUuid);
      const entry = new KdbxEntry(entryUuid, db.root.uuid);
      
      // 添加各种类型的字段
      entry.fields = [
        { name: 'Title', value: '测试标题', protected: false },
        { name: 'UserName', value: 'testuser', protected: false },
        { name: 'Password', value: 'testpass', protected: true },
        { name: 'URL', value: 'https://example.com', protected: false },
        { name: 'Notes', value: '这是一个测试笔记\n包含多行内容', protected: false },
        { name: 'CustomField', value: '自定义字段值', protected: false },
        { name: 'EmptyField', value: '', protected: false },
        { name: 'ProtectedCustomField', value: 'protected-value', protected: true }
      ];
      
      db.root.addEntry(entry);
      
      // 序列化和反序列化
      const xml = serializer.serializeToXml(db);
      const deserializedDb = serializer.deserializeFromXml(xml);
      
      // 获取反序列化后的条目
      const deserializedEntry = deserializedDb.root.entries[0];
      
      // 验证所有字段都被正确反序列化
      expect(deserializedEntry.fields.length).assertEqual(entry.fields.length);
      
      // 验证每个字段
      for (const field of entry.fields) {
        const deserializedField = deserializedEntry.fields.find(f => f.name === field.name);
        expect(deserializedField).not().assertUndefined();
        expect(deserializedField.value).assertEqual(field.value);
        expect(deserializedField.protected).assertEqual(field.protected);
      }
    });
  });
}