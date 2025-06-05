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
import { KdbxDatabase } from '../../../main/ets/kdbx/models/KdbxDatabase';
import { KdbxGroup } from '../../../main/ets/kdbx/models/KdbxGroup';
import { KdbxEntry } from '../../../main/ets/kdbx/models/KdbxEntry';
import { InnerRandomStreamID } from '../../../main/ets/kdbx/KdbxFormat';

export default function KdbxDatabaseUnitTest() {
  describe('KdbxDatabase', () => {
    let db: KdbxDatabase;

    beforeAll(() => {
      // 测试套件开始前的设置
    });

    beforeEach(() => {
      // 每个测试用例开始前的设置
      db = new KdbxDatabase();
    });

    afterEach(() => {
      // 每个测试用例结束后的清理
    });

    afterAll(() => {
      // 测试套件结束后的清理
    });

    it('should initialize with correct default values', 0, () => {
      expect(db.version).assertEqual(0x00040000);
      expect(db.innerRandomStreamId).assertEqual(InnerRandomStreamID.CHACHA20);
      expect(db.protectedStreamKey).assertInstanceOf('Uint8Array');
      expect(db.protectedStreamKey).assertInstanceOf('Uint8Array');
      expect(db.protectedStreamKey.length).assertEqual(32);
      expect(db.root instanceof  KdbxGroup).assertEqual(true);
      expect(db.deletedObjects).assertEqual([]);

      // 验证元数据
      expect(db.meta).not().assertNull();
      expect(db.meta.databaseName).assertEqual('新数据库');
      expect(db.meta.historyMaxItems).assertEqual(10);
      expect(db.meta.historyMaxSize).assertEqual(6 * 1024 * 1024);
      expect(db.meta.recycleBinEnabled).assertEqual(true);
      expect(db.meta.recycleBinUUID).assertInstanceOf('Uint8Array');
      expect(db.meta.masterKeyChanged).assertInstanceOf('Date');

      // 验证内存保护设置
      expect(db.meta.memoryProtection?.protectTitle).assertEqual(false);
      expect(db.meta.memoryProtection?.protectUserName).assertEqual(false);
      expect(db.meta.memoryProtection?.protectPassword).assertEqual(true);
      expect(db.meta.memoryProtection?.protectUrl).assertEqual(false);
      expect(db.meta.memoryProtection?.protectNotes).assertEqual(false);
      expect(db.meta.recycleBinUUID).not().assertNull();
      // 验证回收站
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        expect(recycleBin).not().assertUndefined();
        if (recycleBin) {
          expect(recycleBin.name).assertEqual('回收站');
          expect(recycleBin.icon.id).assertEqual(43);
        }
      }
    });

    it('should create groups', 0, () => {
      const group1 = db.createGroup('Group 1');
      expect(group1 instanceof KdbxGroup).assertTrue();
      expect(group1.name).assertEqual('Group 1');
      expect(group1.parentGroup).assertEqual(db.root.uuid);
      expect(db.root.groups).assertContain(group1);

      // 创建子组
      const group2 = db.createGroup('Group 2', group1);
      expect(group2.name).assertEqual('Group 2');
      expect(group2.parentGroup).assertEqual(group1.uuid);
      expect(group1.groups).assertContain(group2);
    });

    it('should create entries', 0, () => {
      const group = db.createGroup('Test Group');
      const entry = db.createEntry(group);

      expect(entry instanceof  KdbxEntry).assertTrue();
      expect(entry.parentGroup).assertEqual(group.uuid);
      expect(group.entries).assertContain(entry);

      // 设置条目字段
      entry.title = 'Test Entry';
      entry.username = 'testuser';
      entry.password = 'testpassword';

      expect(entry.title).assertEqual('Test Entry');
      expect(entry.username).assertEqual('testuser');
      expect(entry.password).assertEqual('testpassword');
    });

    it('should find groups', 0, () => {
      const group1 = db.createGroup('Group 1');
      const group2 = db.createGroup('Group 2', group1);
      const group3 = db.createGroup('Group 3', group2);

      expect(db.findGroup(group1.uuid)).assertDeepEquals(group1);
      expect(db.findGroup(group2.uuid)).assertDeepEquals(group2);
      expect(db.findGroup(group3.uuid)).assertDeepEquals(group3);
      expect(db.findGroup('nonexistent-uuid')).assertUndefined();
    });

    it('should find entries', 0, () => {
      const group1 = db.createGroup('Group 1');
      const group2 = db.createGroup('Group 2', group1);

      const entry1 = db.createEntry(group1);
      const entry2 = db.createEntry(group2);

      expect(db.findEntry(entry1.uuid)).assertDeepEquals(entry1);
      expect(db.findEntry(entry2.uuid)).assertDeepEquals(entry2);
      expect(db.findEntry('nonexistent-uuid')).assertUndefined();
    });

    it('should move groups', 0, () => {
      const group1 = db.createGroup('Group 1');
      const group2 = db.createGroup('Group 2');
      const group3 = db.createGroup('Group 3', group1);

      // 移动组
      const result = db.moveGroup(group3, group2);
      expect(result).assertEqual(true);
      expect(group3.parentGroup).assertEqual(group2.uuid);
      expect(group1.groups).not().assertContain(group3);
      expect(group2.groups).assertContain(group3);

      // 不能移动到自己
      const selfMoveResult = db.moveGroup(group2, group2);
      expect(selfMoveResult).assertEqual(false);

      // 不能移动到子组
      const childMoveResult = db.moveGroup(group2, group3);
      expect(childMoveResult).assertEqual(false);

      // 不能移动不存在的组
      const nonExistentGroup = new KdbxGroup('nonexistent-uuid', 'Nonexistent');
      const nonExistentResult = db.moveGroup(nonExistentGroup, group1);
      expect(nonExistentResult).assertEqual(false);
    });

    it('should move entries', 0, () => {
      const group1 = db.createGroup('Group 1');
      const group2 = db.createGroup('Group 2');
      const entry = db.createEntry(group1);

      // 移动条目
      const result = db.moveEntry(entry, group2);
      expect(result).assertEqual(true);
      expect(entry.parentGroup).assertEqual(group2.uuid);
      expect(group1.entries).not().assertContain(entry);
      expect(group2.entries).assertContain(entry);

      // 不能移动不存在的条目
      const nonExistentEntry = new KdbxEntry('nonexistent-uuid', 'nonexistent-group');
      const nonExistentResult = db.moveEntry(nonExistentEntry, group1);
      expect(nonExistentResult).assertEqual(false);
    });

    it('should delete groups with recycle bin', 0, () => {
      const group = db.createGroup('Test Group');
      const subGroup = db.createGroup('Sub Group', group);
      const entry = db.createEntry(subGroup);

      // 删除组（使用回收站）
      const result = db.deleteGroup(group, true);
      expect(result).assertEqual(true);

      // 组应该被移动到回收站
      expect(db.meta.recycleBinUUID).not().assertUndefined();
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        expect(recycleBin).not().assertUndefined();
        if (recycleBin) {
          expect(recycleBin.groups).assertContain(group);
          expect(db.root.groups).not().assertContain(group);
        }
      }

      // 子组和条目应该保持原样
      expect(group.groups).assertContain(subGroup);
      expect(subGroup.entries).assertContain(entry);

      // 不能删除根组
      const rootDeleteResult = db.deleteGroup(db.root);
      expect(rootDeleteResult).assertEqual(false);
    });

    it('should delete groups without recycle bin', 0, () => {
      const group = db.createGroup('Test Group');

      // 删除组（不使用回收站）
      const result = db.deleteGroup(group, false);
      expect(result).assertEqual(true);

      // 组应该被完全删除
      expect(db.root.groups).not().assertContain(group);
      expect(db.findGroup(group.uuid)).assertUndefined();

      // 组应该被添加到已删除对象列表
      expect(db.deletedObjects.length).assertEqual(1);
      expect(db.deletedObjects[0].uuid).assertEqual(group.uuid);
      expect(db.deletedObjects[0].deletionTime).assertInstanceOf('Date');
    });

    it('should delete entries with recycle bin', 0, () => {
      const group = db.createGroup('Test Group');
      const entry = db.createEntry(group);

      // 删除条目（使用回收站）
      const result = db.deleteEntry(entry, true);
      expect(result).assertEqual(true);

      // 条目应该被移动到回收站
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        if (recycleBin) {
          expect(recycleBin.entries).assertContain(entry);
          expect(group.entries).not().assertContain(entry);
          expect(entry.parentGroup).assertEqual(recycleBin.uuid);
        }
      }
    });

    it('should delete entries without recycle bin', 0, () => {
      const group = db.createGroup('Test Group');
      const entry = db.createEntry(group);

      // 删除条目（不使用回收站）
      const result = db.deleteEntry(entry, false);
      expect(result).assertEqual(true);

      // 条目应该被完全删除
      expect(group.entries).not().assertContain(entry);
      expect(db.findEntry(entry.uuid)).assertUndefined();

      // 条目应该被添加到已删除对象列表
      expect(db.deletedObjects.length).assertEqual(1);
      expect(db.deletedObjects[0].uuid).assertEqual(entry.uuid);
      expect(db.deletedObjects[0].deletionTime).assertInstanceOf('Date');
      expect(db.deletedObjects[0].deletionTime).assertInstanceOf('Date');
    });

    it('should empty recycle bin', 0, () => {
      const group = db.createGroup('Test Group');
      const entry = db.createEntry(group);

      // 删除组和条目（使用回收站）
      db.deleteGroup(group, true);

      // 清空回收站
      const result = db.emptyRecycleBin();
      expect(result).assertEqual(true);

      // 回收站应该为空
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        if (recycleBin) {
          expect(recycleBin.groups.length).assertEqual(0);
          expect(recycleBin.entries.length).assertEqual(0);
        }
      }

      // 组和条目应该被添加到已删除对象列表
      expect(db.deletedObjects.length).assertEqual(2);
      expect(db.deletedObjects.some(obj => obj.uuid === group.uuid)).assertEqual(true);
      expect(db.deletedObjects.some(obj => obj.uuid === entry.uuid)).assertEqual(true);
    });

    it('should search entries', 0, () => {
      // 创建测试数据
      const group1 = db.createGroup('Group 1');
      const group2 = db.createGroup('Group 2');

      const entry1 = db.createEntry(group1);
      entry1.title = 'Bank Account';
      entry1.username = 'john.doe';
      entry1.password = 'secret123';

      const entry2 = db.createEntry(group1);
      entry2.title = 'Email Account';
      entry2.username = 'john.doe@example.com';
      entry2.password = 'password456';

      const entry3 = db.createEntry(group2);
      entry3.title = 'Shopping Account';
      entry3.username = 'johndoe';
      entry3.password = 'shop789';
      entry3.url = 'https://shopping.example.com';

      // 基本搜索
      const results1 = db.searchEntries('bank');
      expect(results1.length).assertEqual(1);
      expect(results1[0]).assertEqual(entry1);

      // 搜索多个结果
      const results2 = db.searchEntries('john');
      expect(results2.length).assertEqual(3);
      expect(results2).assertContain(entry1);
      expect(results2).assertContain(entry2);
      expect(results2).assertContain(entry3);

      // 区分大小写搜索
      const results3 = db.searchEntries('Bank', { caseSensitive: true });
      expect(results3.length).assertEqual(1);
      expect(results3[0]).assertEqual(entry1);

      // 搜索受保护字段
      const results4 = db.searchEntries('secret', { includeProtected: true });
      expect(results4.length).assertEqual(1);
      expect(results4[0]).assertEqual(entry1);

      const results5 = db.searchEntries('secret', { includeProtected: false });
      expect(results5.length).assertEqual(0);

      // 指定字段搜索
      const results6 = db.searchEntries('john', { fieldNames: ['UserName'] });
      expect(results6.length).assertEqual(3);

      const results7 = db.searchEntries('example', { fieldNames: ['URL'] });
      expect(results7.length).assertEqual(1);
      expect(results7[0]).assertEqual(entry3);

      // 指定搜索组
      const results8 = db.searchEntries('john', { searchInGroups: [group1.uuid] });
      expect(results8.length).assertEqual(2);
      expect(results8).assertContain(entry1);
      expect(results8).assertContain(entry2);

      // 排除组
      const results9 = db.searchEntries('john', { excludeGroups: [group1.uuid] });
      expect(results9.length).assertEqual(1);
      expect(results9[0]).assertEqual(entry3);
    });

    it('should get statistics', 0, () => {
      // 创建测试数据
      const group1 = db.createGroup('Group 1');
      const group2 = db.createGroup('Group 2', group1);

      const entry1 = db.createEntry(group1);
      entry1.title = 'Entry 1';
      entry1.password = 'password1';
      entry1.addAttachment('file1.txt', new Uint8Array(100));

      const entry2 = db.createEntry(group2);
      entry2.title = 'Entry 2';
      entry2.password = 'password2';
      entry2.addAttachment('file2.txt', new Uint8Array(200));
      entry2.addAttachment('file3.txt', new Uint8Array(300));

      const entry3 = db.createEntry(group2);
      entry3.title = 'Entry 3';
      // 无密码

      // 设置过期条目
      const pastDate = new Date();
      pastDate.setDate(pastDate.getDate() - 1); // 昨天
      entry3.expires = true;
      entry3.expiryTime = pastDate;

      // 获取统计信息
      const stats = db.getStatistics();

      expect(stats.groupCount).assertEqual(3); // 2个创建的组 + 1个回收站
      expect(stats.entryCount).assertEqual(3);
      expect(stats.attachmentCount).assertEqual(3);
      expect(stats.attachmentSize).assertEqual(600); // 100 + 200 + 300
      expect(stats.passwordCount).assertEqual(2);
      expect(stats.expiredEntryCount).assertEqual(1);
    });

    it('should handle disabled recycle bin', 0, () => {
      // 禁用回收站
      db.meta.recycleBinEnabled = false;

      const group = db.createGroup('Test Group');
      const entry = db.createEntry(group);

      // 删除组（尝试使用回收站，但回收站已禁用）
      const result1 = db.deleteGroup(group, true);
      expect(result1).assertEqual(true);

      // 组应该被完全删除，而不是移动到回收站
      expect(db.root.groups).not().assertContain(group);
      expect(db.findGroup(group.uuid)).assertUndefined();
      expect(db.deletedObjects.length).assertEqual(2); // 组和条目都被删除

      // 清空回收站应该失败
      const result2 = db.emptyRecycleBin();
      expect(result2).assertEqual(false);
    });

    it('should handle database with custom version', 0, () => {
      const customDb = new KdbxDatabase(0x00030001); // KeePass 3.1
      expect(customDb.version).assertEqual(0x00030001);

      // 其他功能应该正常工作
      const group = customDb.createGroup('Test Group');
      expect(customDb.findGroup(group.uuid)).assertEqual(group);
    });
  });
}

