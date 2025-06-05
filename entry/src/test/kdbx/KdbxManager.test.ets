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
import { KdbxManager } from '../../../main/ets/kdbx/KdbxManager';
import { KeePassDatabase } from '../../../main/ets/kdbx/models/KeePassDatabase';
import { PwGroup } from '../../../main/ets/kdbx/models/PwGroup';
import { PwEntry } from '../../../main/ets/kdbx/models/PwEntry';
import { Binary } from '../../../main/ets/kdbx/models/KdbxTypes';
import { KdbxUtils } from '../../main/ets/kdbx/utils/KdbxUtils';

describe('KdbxManager', () => {
  // 测试数据
  const testPassword = 'testPassword123';
  let database: KeePassDatabase;

  beforeAll(() => {
    // 测试套件开始前的设置
  });

  beforeEach(async () => {
    // 每个测试用例开始前的设置
    // 创建一个新的测试数据库
    database = await KdbxManager.create('Test Database', testPassword);
  });

  afterEach(() => {
    // 每个测试用例结束后的清理
  });

  afterAll(() => {
    // 测试套件结束后的清理
  });

  it('should create a new database', async () => {
    expect(database).toBeDefined();
    expect(database.meta.databaseName).assertEqual('Test Database');
    expect(database.meta.generator).assertEqual('KeePassHO');

    // 验证根组
    expect(database.root).toBeDefined();
    expect(database.root.name).assertEqual('Root');
    expect(database.root.iconId).assertEqual(48);

    // 验证回收站
    expect(database.root.groups.length).assertEqual(1);
    expect(database.root.groups[0].name).assertEqual('Recycle Bin');
    expect(database.root.groups[0].iconId).assertEqual(43);
    expect(database.root.groups[0].uuid).toEqual(database.meta.recycleBinUUID);
  });

  it('should save and open database', async () => {
    // 保存数据库
    const data = await KdbxManager.save(database, testPassword);
    expect(data).toBeDefined();
    expect(data.byteLength).toBeGreaterThan(0);

    // 打开数据库
    const loadedDatabase = await KdbxManager.open(data, testPassword);
    expect(loadedDatabase).toBeDefined();
    expect(loadedDatabase.meta.databaseName).assertEqual('Test Database');
    expect(loadedDatabase.root.name).assertEqual('Root');

    // 验证回收站
    expect(loadedDatabase.root.groups.length).assertEqual(1);
    expect(loadedDatabase.root.groups[0].name).assertEqual('Recycle Bin');
  });

  it('should create and add entries', () => {
    // 创建条目
    const entry = KdbxManager.createEntry(
      'Test Entry',
      'testuser',
      'testpassword',
      'https://example.com',
      'Test notes'
    );

    expect(entry).toBeDefined();
    expect(entry.fields.get('Title')).assertEqual('Test Entry');
    expect(entry.fields.get('UserName')).assertEqual('testuser');
    expect(entry.fields.get('Password')).assertEqual('testpassword');
    expect(entry.fields.get('URL')).assertEqual('https://example.com');
    expect(entry.fields.get('Notes')).assertEqual('Test notes');

    // 添加条目到根组
    KdbxManager.addEntryToGroup(database.root, entry);
    expect(database.root.entries.length).assertEqual(1);
    expect(database.root.entries[0]).assertEqual(entry);

    // 验证最后修改时间已更新
    expect(database.root.times.lastModificationTime.getTime()).toBeGreaterThan(
      database.root.times.creationTime.getTime()
    );
  });

  it('should create and add groups', () => {
    // 创建组
    const group = KdbxManager.createGroup('Test Group', 'Test group notes');

    expect(group).toBeDefined();
    expect(group.name).assertEqual('Test Group');
    expect(group.notes).assertEqual('Test group notes');

    // 添加组到根组
    KdbxManager.addGroupToGroup(database.root, group);
    expect(database.root.groups.length).assertEqual(2); // 回收站 + 新组
    expect(database.root.groups[1]).assertEqual(group);

    // 验证最后修改时间已更新
    expect(database.root.times.lastModificationTime.getTime()).toBeGreaterThan(
      database.root.times.creationTime.getTime()
    );
  });

  it('should find groups by UUID', () => {
    // 创建组
    const group = KdbxManager.createGroup('Test Group');
    KdbxManager.addGroupToGroup(database.root, group);

    // 查找组
    const foundGroup = KdbxManager.findGroupByUUID(database.root, group.uuid);
    expect(foundGroup).assertEqual(group);

    // 查找不存在的组
    const notFoundGroup = KdbxManager.findGroupByUUID(database.root, new Uint8Array(16));
    expect(notFoundGroup).toBeUndefined();
  });

  it('should find entries by UUID', () => {
    // 创建条目
    const entry = KdbxManager.createEntry('Test Entry', 'testuser', 'testpassword');

    // 创建组并添加条目
    const group = KdbxManager.createGroup('Test Group');
    KdbxManager.addEntryToGroup(group, entry);
    KdbxManager.addGroupToGroup(database.root, group);

    // 查找条目
    const foundEntry = KdbxManager.findEntryByUUID(database.root, entry.uuid);
    expect(foundEntry).assertEqual(entry);

    // 查找不存在的条目
    const notFoundEntry = KdbxManager.findEntryByUUID(database.root, new Uint8Array(16));
    expect(notFoundEntry).toBeUndefined();
  });

  it('should handle nested groups and entries', () => {
    // 创建组结构
    const group1 = KdbxManager.createGroup('Group 1');
    const group2 = KdbxManager.createGroup('Group 2');
    const group3 = KdbxManager.createGroup('Group 3');

    // 创建条目
    const entry1 = KdbxManager.createEntry('Entry 1', 'user1', 'pass1');
    const entry2 = KdbxManager.createEntry('Entry 2', 'user2', 'pass2');
    const entry3 = KdbxManager.createEntry('Entry 3', 'user3', 'pass3');

    // 构建嵌套结构
    KdbxManager.addEntryToGroup(group1, entry1);
    KdbxManager.addGroupToGroup(group1, group2);
    KdbxManager.addEntryToGroup(group2, entry2);
    KdbxManager.addGroupToGroup(group2, group3);
    KdbxManager.addEntryToGroup(group3, entry3);
    KdbxManager.addGroupToGroup(database.root, group1);

    // 验证结构
    expect(database.root.groups.length).assertEqual(2); // 回收站 + group1
    expect(database.root.groups[1]).assertEqual(group1);
    expect(group1.entries.length).assertEqual(1);
    expect(group1.entries[0]).assertEqual(entry1);
    expect(group1.groups.length).assertEqual(1);
    expect(group1.groups[0]).assertEqual(group2);
    expect(group2.entries.length).assertEqual(1);
    expect(group2.entries[0]).assertEqual(entry2);
    expect(group2.groups.length).assertEqual(1);
    expect(group2.groups[0]).assertEqual(group3);
    expect(group3.entries.length).assertEqual(1);
    expect(group3.entries[0]).assertEqual(entry3);

    // 测试深层查找
    const foundEntry3 = KdbxManager.findEntryByUUID(database.root, entry3.uuid);
    expect(foundEntry3).assertEqual(entry3);

    const foundGroup3 = KdbxManager.findGroupByUUID(database.root, group3.uuid);
    expect(foundGroup3).assertEqual(group3);
  });

  it('should handle database with key file', async () => {
    // 创建密钥文件
    const keyFile = KdbxUtils.generateRandom(new Uint8Array(32));

    // 创建数据库
    const dbWithKeyFile = await KdbxManager.create('Key File Database', testPassword, keyFile);
    expect(dbWithKeyFile).toBeDefined();

    // 保存数据库
    const data = await KdbxManager.save(dbWithKeyFile, testPassword, keyFile);
    expect(data).toBeDefined();

    // 使用密码和密钥文件打开
    const loadedDb = await KdbxManager.open(data, testPassword, keyFile);
    expect(loadedDb).toBeDefined();
    expect(loadedDb.meta.databaseName).assertEqual('Key File Database');

    // 尝试仅使用密码打开（应该失败）
    await expect(KdbxManager.open(data, testPassword)).rejects.toThrow();
  });

  it('should handle error conditions gracefully', async () => {
    // 测试无效的密码
    await expect(KdbxManager.create('Test', '')).rejects.toThrow();

    // 测试无效的数据库对象
    await expect(KdbxManager.save(null, testPassword)).rejects.toThrow();

    // 测试无效的数据
    await expect(KdbxManager.open(new ArrayBuffer(0), testPassword)).rejects.toThrow();
  });

  it('should handle large databases', async () => {
    // 创建大型数据库
    for (let i = 0; i < 10; i++) {
      const group = KdbxManager.createGroup(`Group ${i}`);

      // 每个组添加100个条目
      for (let j = 0; j < 100; j++) {
        const entry = KdbxManager.createEntry(
          `Entry ${i}-${j}`,
          `user${i}-${j}`,
          `pass${i}-${j}`,
          `https://example.com/${i}/${j}`,
          `Notes for entry ${i}-${j}`
        );
        KdbxManager.addEntryToGroup(group, entry);
      }

      KdbxManager.addGroupToGroup(database.root, group);
    }

    // 保存大型数据库
    const data = await KdbxManager.save(database, testPassword);
    expect(data).toBeDefined();
    expect(data.byteLength).toBeGreaterThan(100000); // 应该生成较大的文件

    // 打开大型数据库
    const loadedDatabase = await KdbxManager.open(data, testPassword);
    expect(loadedDatabase).toBeDefined();
    expect(loadedDatabase.root.groups.length).assertEqual(11); // 回收站 + 10个组

    // 验证条目数量
    let entryCount = 0;
    for (let i = 1; i < loadedDatabase.root.groups.length; i++) { // 跳过回收站
      entryCount += loadedDatabase.root.groups[i].entries.length;
    }
    expect(entryCount).assertEqual(1000); // 10组 * 100条目
  });

  it('should maintain data integrity through save/open cycle', async () => {
    // 创建复杂的数据库结构
    const group = KdbxManager.createGroup('Test Group');
    const entry = KdbxManager.createEntry(
      'Test Entry',
      'testuser',
      'testpassword',
      'https://example.com',
      'Test notes'
    );
    KdbxManager.addEntryToGroup(group, entry);
    KdbxManager.addGroupToGroup(database.root, group);

    // 保存数据库
    const data = await KdbxManager.save(database, testPassword);

    // 打开数据库
    const loadedDatabase = await KdbxManager.open(data, testPassword);

    // 验证结构完整性
    expect(loadedDatabase.meta.databaseName).assertEqual(database.meta.databaseName);
    expect(loadedDatabase.root.name).assertEqual(database.root.name);
    expect(loadedDatabase.root.groups.length).assertEqual(database.root.groups.length);

    // 验证组
    const loadedGroup = loadedDatabase.root.groups[1]; // 跳过回收站
    expect(loadedGroup.name).assertEqual(group.name);
    expect(loadedGroup.entries.length).assertEqual(group.entries.length);

    // 验证条目
    const loadedEntry = loadedGroup.entries[0];
    expect(loadedEntry.fields.get('Title')).assertEqual(entry.fields.get('Title'));
    expect(loadedEntry.fields.get('UserName')).assertEqual(entry.fields.get('UserName'));
    expect(loadedEntry.fields.get('Password')).assertEqual(entry.fields.get('Password'));
    expect(loadedEntry.fields.get('URL')).assertEqual(entry.fields.get('URL'));
    expect(loadedEntry.fields.get('Notes')).assertEqual(entry.fields.get('Notes'));
  });
});
