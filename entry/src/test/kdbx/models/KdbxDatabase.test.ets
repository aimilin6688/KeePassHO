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
      expect(db.deletedObjects).assertDeepEquals([]);

      // 验证元数据
      expect(db.meta).not().assertNull();
      expect(db.meta.databaseName).assertEqual('新数据库');
      expect(db.meta.historyMaxItems).assertEqual(10);
      expect(db.meta.historyMaxSize).assertEqual(6 * 1024 * 1024);
      expect(db.meta.recycleBinEnabled).assertEqual(true);
      expect(db.meta.recycleBinUUID).assertInstanceOf('String');
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

    it('should record all deleted objects when deleting a group with subgroups and entries', 0, () => {
      // 禁用回收站
      db.meta.recycleBinEnabled = false;

      // 创建一个复杂的组结构
      const mainGroup = db.createGroup('Main Group');
      
      // 创建两个子组
      const subGroup1 = db.createGroup('Sub Group 1', mainGroup);
      const subGroup2 = db.createGroup('Sub Group 2', mainGroup);
      
      // 在主组中创建一个条目
      const mainEntry = db.createEntry(mainGroup);
      mainEntry.title = 'Main Entry';
      
      // 在第一个子组中创建两个条目
      const subEntry1 = db.createEntry(subGroup1);
      subEntry1.title = 'Sub Entry 1';
      const subEntry2 = db.createEntry(subGroup1);
      subEntry2.title = 'Sub Entry 2';
      
      // 在第二个子组中创建一个条目
      const subEntry3 = db.createEntry(subGroup2);
      subEntry3.title = 'Sub Entry 3';

      // 删除主组
      const result = db.deleteGroup(mainGroup, false);
      expect(result).assertEqual(true);

      // 验证组被删除
      expect(db.root.groups).not().assertContain(mainGroup);
      expect(db.findGroup(mainGroup.uuid)).assertUndefined();

      // 验证deletedObjects中的记录
      // 应该包含：
      // 1个主组 + 2个子组 + 4个条目 = 7条记录
      expect(db.deletedObjects.length).assertEqual(7);

      // 验证所有UUID都被记录
      const deletedUuids = db.deletedObjects.map(obj => obj.uuid);
      expect(deletedUuids).assertContain(mainGroup.uuid);
      expect(deletedUuids).assertContain(subGroup1.uuid);
      expect(deletedUuids).assertContain(subGroup2.uuid);
      expect(deletedUuids).assertContain(mainEntry.uuid);
      expect(deletedUuids).assertContain(subEntry1.uuid);
      expect(deletedUuids).assertContain(subEntry2.uuid);
      expect(deletedUuids).assertContain(subEntry3.uuid);

      // 验证删除时间
      for (const obj of db.deletedObjects) {
        expect(obj.deletionTime).assertInstanceOf('Date');
        // 所有对象应该在同一时间被删除
        expect(obj.deletionTime.getTime()).assertEqual(db.deletedObjects[0].deletionTime.getTime());
      }
    });

    it('should handle database with custom version', 0, () => {
      const customDb = new KdbxDatabase(0x00030001); // KeePass 3.1
      expect(customDb.version).assertEqual(0x00030001);

      // 其他功能应该正常工作
      const group = customDb.createGroup('Test Group');
      expect(customDb.findGroup(group.uuid)).assertEqual(group);
    });

    it('should handle edge cases in search', 0, () => {
      const group = db.createGroup('Test Group');
      const entry = db.createEntry(group);
      entry.title = 'Test Entry @#$%';
      entry.username = 'user.name+email@example.com';
      entry.notes = 'Special chars: !@#$%^&*()';

      // 空搜索字符串
      const emptyResults = db.searchEntries('');
      expect(emptyResults.length).assertEqual(0);

      // 特殊字符搜索
      const specialResults = db.searchEntries('@#$%');
      expect(specialResults.length).assertEqual(1);
      expect(specialResults[0]).assertEqual(entry);

      // 搜索不存在的组UUID
      const nonExistentResults = db.searchEntries('test', {
        searchInGroups: ['non-existent-uuid']
      });
      expect(nonExistentResults.length).assertEqual(0);

      // 组合搜索选项
      const combinedResults = db.searchEntries('user', {
        caseSensitive: true,
        includeProtected: false,
        fieldNames: ['UserName'],
        excludeGroups: ['non-existent-uuid']
      });
      expect(combinedResults.length).assertEqual(1);
      expect(combinedResults[0]).assertEqual(entry);
    });

    it('should handle edge cases in group operations', 0, () => {
      const group = db.createGroup('Test Group');
      
      // 移动到不存在的组
      const nonExistentGroup = new KdbxGroup('non-existent-uuid', 'Non-existent');
      expect(db.moveGroup(group, nonExistentGroup)).assertEqual(false);
      
      // 移动到回收站
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        if (recycleBin) {
          expect(db.moveGroup(group, recycleBin)).assertEqual(true);
          expect(group.parentGroup).assertEqual(recycleBin.uuid);
        }
      }
      
      // 尝试移动回收站（应该失败，因为回收站必须保持在根目录下）
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        const newGroup = db.createGroup('New Group');
        if (recycleBin) {
          // 回收站不应该被移动到其他组
          expect(db.moveGroup(recycleBin, newGroup)).assertEqual(false);
          // 回收站应该仍然在根目录下
          expect(recycleBin.parentGroup).assertEqual(db.root.uuid);
        }
      }
    });

    it('should handle recycle bin edge cases', 0, () => {
      // 在回收站中创建和删除项目
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        if (recycleBin) {
          // 在回收站中创建条目
          const entry = db.createEntry(recycleBin);
          entry.title = 'Recycled Entry';
          
          // 删除回收站中的条目（应该直接删除，不会再次移动到回收站）
          expect(db.deleteEntry(entry, true)).assertEqual(true);
          expect(recycleBin.entries.length).assertEqual(0);
          // 验证删除的条目在 deletedObjects 中
          const deletedEntry = db.deletedObjects.find(obj => obj.uuid === entry.uuid);
          expect(deletedEntry).not().assertUndefined();
          expect(deletedEntry?.uuid).assertEqual(entry.uuid);
          expect(deletedEntry?.deletionTime).assertInstanceOf('Date');

          // 删除并重新创建回收站
          const oldRecycleBinUuid = db.meta.recycleBinUUID;
          expect(db.deleteGroup(recycleBin, false)).assertEqual(true);
          expect(db.findGroup(oldRecycleBinUuid)).assertUndefined();

          // 创建新条目并删除（应该创建新的回收站）
          const newGroup = db.createGroup('New Group');
          const newEntry = db.createEntry(newGroup);
          expect(db.deleteEntry(newEntry, true)).assertEqual(true);

          // 验证新回收站
          expect(db.meta.recycleBinUUID).not().assertEqual(oldRecycleBinUuid);
          const newRecycleBin = db.findGroup(db.meta.recycleBinUUID!);
          expect(newRecycleBin).not().assertUndefined();
          if (newRecycleBin) {
            expect(newRecycleBin.name).assertEqual('回收站');
            expect(newRecycleBin.entries).assertContain(newEntry);
          }
        }
      }
    });

    it('should handle statistics edge cases', 0, () => {
      // 空数据库统计
      const emptyStats = db.getStatistics();
      expect(emptyStats.groupCount).assertEqual(1); // 只有回收站
      expect(emptyStats.entryCount).assertEqual(0);
      expect(emptyStats.attachmentCount).assertEqual(0);
      expect(emptyStats.attachmentSize).assertEqual(0);
      expect(emptyStats.passwordCount).assertEqual(0);
      expect(emptyStats.expiredEntryCount).assertEqual(0);

      // 创建大量数据
      const group = db.createGroup('Test Group');
      for (let i = 0; i < 100; i++) {
        const entry = db.createEntry(group);
        entry.title = `Entry ${i}`;
        if (i % 2 === 0) {
          entry.password = `password${i}`;
        }
        if (i % 3 === 0) {
          entry.addAttachment(`file${i}.txt`, new Uint8Array(i + 1));
        }
        if (i % 4 === 0) {
          entry.expires = true;
          const pastDate = new Date();
          pastDate.setDate(pastDate.getDate() - 1);
          entry.expiryTime = pastDate;
        }
      }

      const stats = db.getStatistics();
      expect(stats.groupCount).assertEqual(2); // 测试组 + 回收站
      expect(stats.entryCount).assertEqual(100);
      expect(stats.passwordCount).assertEqual(50); // 偶数索引的条目有密码
      expect(stats.attachmentCount).assertEqual(34); // 每3个条目有一个附件
      expect(stats.expiredEntryCount).assertEqual(25); // 每4个条目过期
    });

    it('should handle entry move edge cases', 0, () => {
      const group1 = db.createGroup('Group 1');
      const group2 = db.createGroup('Group 2');
      const entry = db.createEntry(group1);
      entry.title = 'Test Entry';

      // 移动到不存在的组
      const nonExistentGroup = new KdbxGroup('non-existent-uuid', 'Non-existent');
      expect(db.moveEntry(entry, nonExistentGroup)).assertEqual(false);
      expect(entry.parentGroup).assertEqual(group1.uuid);

      // 移动到回收站
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        if (recycleBin) {
          expect(db.moveEntry(entry, recycleBin)).assertEqual(true);
          expect(entry.parentGroup).assertEqual(recycleBin.uuid);
          expect(recycleBin.entries).assertContain(entry);
          expect(group1.entries).not().assertContain(entry);
        }
      }

      // 从回收站移动到普通组
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        if (recycleBin && recycleBin.entries.includes(entry)) {
          expect(db.moveEntry(entry, group2)).assertEqual(true);
          expect(entry.parentGroup).assertEqual(group2.uuid);
          expect(group2.entries).assertContain(entry);
          expect(recycleBin.entries).not().assertContain(entry);
        }
      }
    });

    it('should handle advanced search scenarios', 0, () => {
      // 创建测试数据
      const group1 = db.createGroup('Search Group 1');
      const group2 = db.createGroup('Search Group 2');
      const subGroup = db.createGroup('Sub Search Group', group1);

      // 创建具有各种特殊字段的条目
      const entry1 = db.createEntry(group1);
      entry1.title = 'Test Entry 123';
      entry1.username = 'user@example.com';
      entry1.password = 'p@ssw0rd!';
      entry1.url = 'https://example.com';
      entry1.notes = 'This is a test note with some keywords: test123';
      entry1.setCustomField('CustomField1', 'CustomValue1');
      entry1.setCustomField('CustomField2', 'CustomValue2');

      const entry2 = db.createEntry(subGroup);
      entry2.title = 'Another Test';
      entry2.username = 'another-user';
      entry2.password = 'another-password';
      entry2.url = 'https://another-example.com';
      entry2.notes = 'Another test note';
      entry2.setCustomField('CustomField1', 'AnotherCustomValue');

      const entry3 = db.createEntry(group2);
      entry3.title = 'Third Test Entry';
      entry3.username = 'third-user';
      entry3.password = 'third-password';
      entry3.url = 'https://third-example.com';
      entry3.notes = 'Third test note with CustomValue1 text';

      // 测试搜索自定义字段
      const customFieldResults = db.searchEntries('CustomValue1');
      expect(customFieldResults.length).assertEqual(2); // entry1 和 entry3 (entry3 的 notes 中包含)
      expect(customFieldResults).assertContain(entry1);
      expect(customFieldResults).assertContain(entry3);

      // 测试搜索多个字段
      const multiFieldResults = db.searchEntries('test', {
        fieldNames: ['Title', 'Notes']
      });
      expect(multiFieldResults.length).assertEqual(3); // 所有条目的标题或备注中都包含 "test"
      expect(multiFieldResults).assertContain(entry1);
      expect(multiFieldResults).assertContain(entry2);
      expect(multiFieldResults).assertContain(entry3);

      // 测试搜索特定组及其子组
      const groupSearchResults = db.searchEntries('test', {
        searchInGroups: [group1.uuid]
      });
      expect(groupSearchResults.length).assertEqual(2); // entry1 和 entry2
      expect(groupSearchResults).assertContain(entry1);
      expect(groupSearchResults).assertContain(entry2);

      // 测试搜索数字
      const numberResults = db.searchEntries('123');
      expect(numberResults.length).assertEqual(1);
      expect(numberResults[0]).assertEqual(entry1);

      // 测试搜索 URL
      const urlResults = db.searchEntries('https://');
      expect(urlResults.length).assertEqual(3); // 所有条目都有 URL
      expect(urlResults).assertContain(entry1);
      expect(urlResults).assertContain(entry2);
      expect(urlResults).assertContain(entry3);

      // 测试复杂组合搜索
      const complexResults = db.searchEntries('test', {
        caseSensitive: true,
        includeProtected: false,
        fieldNames: ['Title', 'Notes'],
        searchInGroups: [group1.uuid],
        excludeGroups: [subGroup.uuid]
      });
      expect(complexResults.length).assertEqual(1); // 只有 entry1
      expect(complexResults[0]).assertEqual(entry1);
    });

    it('should handle meta data operations', 0, () => {
      // 测试修改元数据
      db.meta.databaseName = 'Test Database';
      expect(db.meta.databaseName).assertEqual('Test Database');

      db.meta.databaseDescription = 'This is a test database';
      expect(db.meta.databaseDescription).assertEqual('This is a test database');

      // 测试修改历史设置
      db.meta.historyMaxItems = 20;
      expect(db.meta.historyMaxItems).assertEqual(20);

      db.meta.historyMaxSize = 10 * 1024 * 1024; // 10MB
      expect(db.meta.historyMaxSize).assertEqual(10 * 1024 * 1024);

      // 测试修改内存保护设置
      if (db.meta.memoryProtection) {
        db.meta.memoryProtection.protectTitle = true;
        expect(db.meta.memoryProtection.protectTitle).assertEqual(true);

        db.meta.memoryProtection.protectUserName = true;
        expect(db.meta.memoryProtection.protectUserName).assertEqual(true);

        db.meta.memoryProtection.protectPassword = false;
        expect(db.meta.memoryProtection.protectPassword).assertEqual(false);
      }

      // 测试禁用回收站
      db.meta.recycleBinEnabled = false;
      expect(db.meta.recycleBinEnabled).assertEqual(false);

      // 测试启用回收站
      db.meta.recycleBinEnabled = true;
      expect(db.meta.recycleBinEnabled).assertEqual(true);
      expect(db.meta.recycleBinUUID).not().assertUndefined();
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        expect(recycleBin).not().assertUndefined();
        if (recycleBin) {
          expect(recycleBin.name).assertEqual('回收站');
        }
      }
    });

    it('should handle recycle bin operations', 0, () => {
      // 创建测试数据
      const group1 = db.createGroup('Test Group 1');
      const subGroup = db.createGroup('Sub Group', group1);
      const entry1 = db.createEntry(group1);
      entry1.title = 'Entry 1';
      const entry2 = db.createEntry(subGroup);
      entry2.title = 'Entry 2';

      // 测试禁用回收站时的删除操作
      db.meta.recycleBinEnabled = false;
      expect(db.deleteGroup(group1, true)).assertEqual(true);
      expect(db.findGroup(group1.uuid)).assertUndefined();
      expect(db.findGroup(subGroup.uuid)).assertUndefined();
      expect(db.findEntry(entry1.uuid)).assertUndefined();
      expect(db.findEntry(entry2.uuid)).assertUndefined();
      // 验证所有对象都被添加到已删除对象列表
      expect(db.deletedObjects.find(obj => obj.uuid === group1.uuid)).not().assertUndefined();
      expect(db.deletedObjects.find(obj => obj.uuid === subGroup.uuid)).not().assertUndefined();
      expect(db.deletedObjects.find(obj => obj.uuid === entry1.uuid)).not().assertUndefined();
      expect(db.deletedObjects.find(obj => obj.uuid === entry2.uuid)).not().assertUndefined();

      // 重新启用回收站
      db.meta.recycleBinEnabled = true;
      const group2 = db.createGroup('Test Group 2');
      const entry3 = db.createEntry(group2);
      entry3.title = 'Entry 3';

      // 测试回收站操作
      if (db.meta.recycleBinUUID) {
        const recycleBin = db.findGroup(db.meta.recycleBinUUID);
        if (recycleBin) {
          // 测试移动到回收站
          expect(db.deleteGroup(group2, true)).assertEqual(true);
          expect(group2.parentGroup).assertEqual(recycleBin.uuid);
          expect(recycleBin.groups).assertContain(group2);

          // 测试清空回收站
          expect(db.emptyRecycleBin()).assertEqual(true);
          expect(recycleBin.groups.length).assertEqual(0);
          expect(recycleBin.entries.length).assertEqual(0);
          // 验证所有对象都被添加到已删除对象列表
          expect(db.deletedObjects.find(obj => obj.uuid === group2.uuid)).not().assertUndefined();
          expect(db.deletedObjects.find(obj => obj.uuid === entry3.uuid)).not().assertUndefined();
        }
      }
    });

    it('should handle delete operations edge cases', 0, () => {
      // 测试删除根组（应该失败）
      expect(db.deleteGroup(db.root, true)).assertEqual(false);
      expect(db.root).not().assertUndefined();

      // 测试删除不存在的组
      const nonExistentGroup = new KdbxGroup('non-existent-uuid', 'Non-existent');
      expect(db.deleteGroup(nonExistentGroup, true)).assertEqual(false);

      // 测试删除包含子组和条目的组
      const parentGroup = db.createGroup('Parent Group');
      const childGroup1 = db.createGroup('Child Group 1', parentGroup);
      const childGroup2 = db.createGroup('Child Group 2', parentGroup);
      const entry1 = db.createEntry(parentGroup);
      entry1.title = 'Parent Entry';
      const entry2 = db.createEntry(childGroup1);
      entry2.title = 'Child Entry 1';
      const entry3 = db.createEntry(childGroup2);
      entry3.title = 'Child Entry 2';

      // 删除父组
      expect(db.deleteGroup(parentGroup, false)).assertEqual(true);
      // 验证所有子组和条目都被删除
      expect(db.findGroup(parentGroup.uuid)).assertUndefined();
      expect(db.findGroup(childGroup1.uuid)).assertUndefined();
      expect(db.findGroup(childGroup2.uuid)).assertUndefined();
      expect(db.findEntry(entry1.uuid)).assertUndefined();
      expect(db.findEntry(entry2.uuid)).assertUndefined();
      expect(db.findEntry(entry3.uuid)).assertUndefined();
      // 验证所有对象都被添加到已删除对象列表
      expect(db.deletedObjects.find(obj => obj.uuid === parentGroup.uuid)).not().assertUndefined();
      expect(db.deletedObjects.find(obj => obj.uuid === childGroup1.uuid)).not().assertUndefined();
      expect(db.deletedObjects.find(obj => obj.uuid === childGroup2.uuid)).not().assertUndefined();
      expect(db.deletedObjects.find(obj => obj.uuid === entry1.uuid)).not().assertUndefined();
      expect(db.deletedObjects.find(obj => obj.uuid === entry2.uuid)).not().assertUndefined();
      expect(db.deletedObjects.find(obj => obj.uuid === entry3.uuid)).not().assertUndefined();

      // 测试删除不存在的条目
      const nonExistentEntry = new KdbxEntry('non-existent-uuid', db.root.uuid);
      expect(db.deleteEntry(nonExistentEntry, true)).assertEqual(false);
    });
  });
}

