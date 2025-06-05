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
import { InnerRandomStreamID, KdbxDatabase, KdbxHeader } from '../../main/ets/kdbx/Index';
import { KdbxCredentials } from '../../main/ets/kdbx/KdbxCredentials';
import { KdbxFile } from '../../main/ets/kdbx/KdbxFile';
import { KdbxUtils } from '../../main/ets/kdbx/utils/KdbxUtils';
export default function KdbxFileUnitTest() {
  describe('KdbxFile', () => {
    let credentials: KdbxCredentials;
    let kdbxFile: KdbxFile;

    beforeAll(() => {
      // 测试套件开始前的设置
    });

    beforeEach(async () => {
      // 每个测试用例开始前的设置
      credentials = new KdbxCredentials();
      await credentials.setPassword('testpassword');
      kdbxFile = KdbxFile.createNew(credentials);
    });

    afterEach(() => {
      // 每个测试用例结束后的清理
    });

    afterAll(() => {
      // 测试套件结束后的清理
    });

    it('should create new database with correct defaults', 0,() => {
      expect(kdbxFile.database).assertInstanceOf(KdbxDatabase);
      expect(kdbxFile.header).assertInstanceOf(KdbxHeader);
      expect(kdbxFile.credentials).assertEqual(credentials);

      // 验证头部信息
      expect(kdbxFile.header.version).assertEqual(0x00040000);
      expect(kdbxFile.header.innerRandomStreamId).assertEqual(InnerRandomStreamID.CHACHA20);
      expect(kdbxFile.header.masterSeed).assertInstanceOf('Uint8Array');
      expect(kdbxFile.header.masterSeed.length).assertEqual(32);
      expect(kdbxFile.header.transformSeed).assertInstanceOf('Uint8Array');
      expect(kdbxFile.header.transformSeed?.length).assertEqual(32);
      expect(kdbxFile.header.encryptionIV).assertInstanceOf('Uint8Array');
      expect(kdbxFile.header.encryptionIV.length).assertEqual(16);
      expect(kdbxFile.header.protectedStreamKey).assertInstanceOf('Uint8Array');
      expect(kdbxFile.header.protectedStreamKey?.length).assertEqual(32);

      // 验证数据库
      expect(kdbxFile.database.meta.databaseName).assertEqual('新数据库');
      expect(kdbxFile.database.meta.recycleBinEnabled).assertEqual(true);
      expect(kdbxFile.database.root).not().assertUndefined();
    });

    it('should save and load database',0, async () => {
      // 创建一些测试数据
      const group = kdbxFile.createGroup('Test Group');
      const entry = kdbxFile.createEntry(group);
      entry.title = 'Test Entry';
      entry.username = 'testuser';
      entry.password = 'testpass';

      // 保存数据库
      const binary = await kdbxFile.saveToBinary();
      expect(binary).assertInstanceOf('Uint8Array');
      expect(binary.length).assertLarger(0);

      // 加载数据库
      const loadedFile = await KdbxFile.loadFromBinary(binary, credentials);
      expect(loadedFile instanceof KdbxFile).assertTrue();

      // 验证加载的数据
      const loadedGroup = loadedFile.findGroup(group.uuid);
      expect(loadedGroup).not().assertUndefined();
      expect(loadedGroup?.name).assertEqual('Test Group');

      const loadedEntry = loadedFile.findEntry(entry.uuid);
      expect(loadedEntry).not().assertUndefined();
      expect(loadedEntry?.title).assertEqual('Test Entry');
      expect(loadedEntry?.username).assertEqual('testuser');
      expect(loadedEntry?.password).assertEqual('testpass');
    });

    it('should handle invalid credentials when loading',0, async () => {
      // 保存数据库
      const binary = await kdbxFile.saveToBinary();

      // 使用错误的凭证尝试加载
      const wrongCredentials = new KdbxCredentials();
      await wrongCredentials.setPassword('wrongpassword');

      await expect(async () => {
        await KdbxFile.loadFromBinary(binary, wrongCredentials);
      }).rejects.toThrow(KdbxError);
    });

    it('should change master key', 0,async () => {
      // 创建新凭证
      const newCredentials = new KdbxCredentials();
      await newCredentials.setPassword('newpassword');

      // 更改主密钥
      const initialKeyChanged = kdbxFile.header.masterKeyChanged;
      const initialMasterSeed = kdbxFile.header.masterSeed;

      await kdbxFile.changeMasterKey(newCredentials);

      expect(kdbxFile.credentials).assertEqual(newCredentials);
      expect(kdbxFile.header.masterKeyChanged.getTime()).assertLarger(initialKeyChanged.getTime());
      expect(kdbxFile.header.masterSeed).not.assertEqual(initialMasterSeed);

      // 保存并使用新凭证加载
      const binary = await kdbxFile.saveToBinary();
      const loadedFile = await KdbxFile.loadFromBinary(binary, newCredentials);
      expect(loadedFile).not().assertUndefined();

      // 使用旧凭证应该失败
      await expect(async () => {
        await KdbxFile.loadFromBinary(binary, credentials);
      }).rejects.toThrow(KdbxError);
    });

    it('should handle invalid new credentials when changing master key', 0,async () => {
      const invalidCredentials = new KdbxCredentials();
      // 不设置密码，使其无效

      await expect(async () => {
        await kdbxFile.changeMasterKey(invalidCredentials);
      }).rejects.toThrow(KdbxError);
    });

    it('should handle corrupted data when loading', 0,async () => {
      const corruptedData = new Uint8Array(100);
      KdbxUtils.generateRandom(corruptedData); // 随机数据

      await expect(async () => {
        await KdbxFile.loadFromBinary(corruptedData, credentials);
      }).rejects.toThrow(KdbxError);
    });

    it('should proxy database operations correctly',0, () => {
      // 测试创建组
      const group = kdbxFile.createGroup('Test Group');
      expect(group).not().assertUndefined();
      expect(group.name).assertEqual('Test Group');
      expect(kdbxFile.findGroup(group.uuid)).assertEqual(group);

      // 测试创建条目
      const entry = kdbxFile.createEntry(group);
      expect(entry).not().assertUndefined();
      expect(entry.parentGroup).assertEqual(group.uuid);
      expect(kdbxFile.findEntry(entry.uuid)).assertEqual(entry);

      // 测试移动组
      const newParentGroup = kdbxFile.createGroup('New Parent');
      const moveGroupResult = kdbxFile.moveGroup(group, newParentGroup);
      expect(moveGroupResult).assertEqual(true);
      expect(group.parentGroup).assertEqual(newParentGroup.uuid);

      // 测试移动条目
      const moveEntryResult = kdbxFile.moveEntry(entry, newParentGroup);
      expect(moveEntryResult).assertEqual(true);
      expect(entry.parentGroup).assertEqual(newParentGroup.uuid);

      // 测试删除条目
      const deleteEntryResult = kdbxFile.deleteEntry(entry, true);
      expect(deleteEntryResult).assertEqual(true);
      expect(kdbxFile.findEntry(entry.uuid).parentGroup).assertEqual(kdbxFile.database.meta.recycleBinUUID);

      // 测试删除组
      const deleteGroupResult = kdbxFile.deleteGroup(group, true);
      expect(deleteGroupResult).assertEqual(true);
      expect(kdbxFile.findGroup(group.uuid).parentGroup).assertEqual(kdbxFile.database.meta.recycleBinUUID);

      // 测试清空回收站
      const emptyRecycleBinResult = kdbxFile.emptyRecycleBin();
      expect(emptyRecycleBinResult).assertEqual(true);
      expect(kdbxFile.findEntry(entry.uuid)).assertUndefined();
      expect(kdbxFile.findGroup(group.uuid)).assertUndefined();
    });

    it('should get statistics correctly',0, () => {
      // 创建一些测试数据
      const group1 = kdbxFile.createGroup('Group 1');
      const group2 = kdbxFile.createGroup('Group 2', group1);

      const entry1 = kdbxFile.createEntry(group1);
      entry1.title = 'Entry 1';
      entry1.password = 'password1';
      entry1.addAttachment('file1.txt', new Uint8Array(100));

      const entry2 = kdbxFile.createEntry(group2);
      entry2.title = 'Entry 2';
      entry2.password = 'password2';
      entry2.addAttachment('file2.txt', new Uint8Array(200));

      // 获取统计信息
      const stats = kdbxFile.getStatistics();

      expect(stats.groupCount).assertEqual(3); // 2个创建的组 + 1个回收站
      expect(stats.entryCount).assertEqual(2);
      expect(stats.attachmentCount).assertEqual(2);
      expect(stats.attachmentSize).assertEqual(300);
      expect(stats.passwordCount).assertEqual(2);
    });

    it('should search entries correctly',0, () => {
      // 创建测试数据
      const group1 = kdbxFile.createGroup('Group 1');
      const group2 = kdbxFile.createGroup('Group 2');

      const entry1 = kdbxFile.createEntry(group1);
      entry1.title = 'Bank Account';
      entry1.username = 'john.doe';

      const entry2 = kdbxFile.createEntry(group2);
      entry2.title = 'Email Account';
      entry2.username = 'john.doe@example.com';

      // 基本搜索
      const results1 = kdbxFile.searchEntries('bank');
      expect(results1.length).assertEqual(1);
      expect(results1[0]).assertEqual(entry1);

      // 搜索多个结果
      const results2 = kdbxFile.searchEntries('account');
      expect(results2.length).assertEqual(2);

      // 使用选项搜索
      const results3 = kdbxFile.searchEntries('john', {
        caseSensitive: true,
        fieldNames: ['UserName'],
        searchInGroups: [group1.uuid]
      });
      expect(results3.length).assertEqual(1);
      expect(results3[0]).assertEqual(entry1);
    });

    it('should handle large files',0, async () => {
      // 创建大量数据
      for (let i = 0; i < 100; i++) {
        const group = kdbxFile.createGroup(`Group ${i}`);
        for (let j = 0; j < 10; j++) {
          const entry = kdbxFile.createEntry(group);
          entry.title = `Entry ${i}-${j}`;
          entry.username = `user${i}-${j}`;
          entry.password = `pass${i}-${j}`;
          entry.addAttachment(`file${i}-${j}.txt`, new Uint8Array(1000));
        }
      }

      // 保存和加载
      const binary = await kdbxFile.saveToBinary();
      expect(binary.length).assertLarger(1000000); // 应该大于1MB

      const loadedFile = await KdbxFile.loadFromBinary(binary, credentials);
      expect(loadedFile.database.root.groups.length).assertEqual(101); // 100个组 + 1个回收站

      // 验证统计信息
      const stats = loadedFile.getStatistics();
      expect(stats.groupCount).assertEqual(101);
      expect(stats.entryCount).assertEqual(1000);
      expect(stats.attachmentCount).assertEqual(1000);
      expect(stats.attachmentSize).assertEqual(1000000);
    });
  });
}

