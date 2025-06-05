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
import { KdbxWriter } from '../../../main/ets/kdbx/KdbxWriter';
import { KdbxReader } from '../../../main/ets/kdbx/KdbxReader';
import { InnerRandomStreamID } from '../../../main/ets/kdbx/KdbxFormat';
import { Binary } from '../../../main/ets/kdbx/models/KdbxTypes';
import { KdbxUtils } from '../../main/ets/kdbx/utils/KdbxUtils';

describe('KdbxWriter', () => {
  let writer: KdbxWriter;

  // 创建测试用的数据库对象
  function createTestDatabase() {
    return {
      meta: {
        generator: 'KeePassHO',
        databaseName: 'Test Database',
        databaseDescription: 'Test database for KdbxWriter',
        recycleBinEnabled: true,
        recycleBinUUID: '00000000-0000-0000-0000-000000000000',
        historyMaxItems: 10,
        historyMaxSize: 6291456, // 6MB
      },
      root: {
        uuid: '11111111-1111-1111-1111-111111111111',
        name: 'Root',
        notes: '',
        iconId: 48,
        times: {
          lastModificationTime: new Date(),
          creationTime: new Date(),
          lastAccessTime: new Date(),
          expiryTime: new Date(),
          expires: false,
          usageCount: 0,
          locationChanged: new Date()
        },
        groups: [
          {
            uuid: '22222222-2222-2222-2222-222222222222',
            name: 'Test Group',
            notes: 'Test group notes',
            iconId: 49,
            times: {
              lastModificationTime: new Date(),
              creationTime: new Date(),
              lastAccessTime: new Date(),
              expiryTime: new Date(),
              expires: false,
              usageCount: 0,
              locationChanged: new Date()
            },
            entries: [
              {
                uuid: '33333333-3333-3333-3333-333333333333',
                iconId: 0,
                fields: {
                  Title: 'Test Entry',
                  UserName: 'testuser',
                  Password: 'testpassword',
                  URL: 'https://example.com',
                  Notes: 'Test entry notes'
                },
                times: {
                  lastModificationTime: new Date(),
                  creationTime: new Date(),
                  lastAccessTime: new Date(),
                  expiryTime: new Date(),
                  expires: false,
                  usageCount: 0,
                  locationChanged: new Date()
                }
              }
            ]
          }
        ]
      }
    };
  }

  beforeAll(() => {
    // 测试套件开始前的设置
  });

  beforeEach(() => {
    // 每个测试用例开始前的设置
    writer = new KdbxWriter();
  });

  afterEach(() => {
    // 每个测试用例结束后的清理
  });

  afterAll(() => {
    // 测试套件结束后的清理
  });

  it('should create writer instance', () => {
    expect(writer).toBeDefined();
  });

  it('should write database with password only', async () => {
    const database = createTestDatabase();
    const password = 'testpassword';

    const data = await writer.write(database, password);
    expect(data).toBeInstanceOf(Uint8Array);
    expect(data.length).toBeGreaterThan(0);

    // 验证生成的文件格式
    // 1. 检查文件签名
    const view = new DataView(data.buffer);
    expect(view.getUint32(0, true)).toBe(0x9AA2D903);
    expect(view.getUint32(4, true)).toBe(0xB54BFB67);

    // 2. 检查版本号
    expect(view.getUint32(8, true)).toBe(0x00040000); // KDBX 4.0

    // 3. 尝试读取写入的文件
    const reader = new KdbxReader(data);
    const readDatabase = await reader.read(password);
    expect(readDatabase).toBeDefined();
    expect(readDatabase.meta.generator).toBe('KeePassHO');
    expect(readDatabase.meta.databaseName).toBe('Test Database');
  });

  it('should write database with password and key file', async () => {
    const database = createTestDatabase();
    const password = 'testpassword';
    const keyFile = KdbxUtils.generateRandom(new Uint8Array(32));

    const data = await writer.write(database, password, keyFile);
    expect(data).toBeInstanceOf(Uint8Array);
    expect(data.length).toBeGreaterThan(0);

    // 尝试读取写入的文件
    const reader = new KdbxReader(data);
    const readDatabase = await reader.read(password, keyFile);
    expect(readDatabase).toBeDefined();
    expect(readDatabase.meta.generator).toBe('KeePassHO');
  });

  it('should handle large databases', async () => {
    const database = createTestDatabase();

    // 添加大量条目
    for (let i = 0; i < 1000; i++) {
      database.root.groups[0].entries.push({
        uuid: crypto.randomUUID(),
        iconId: 0,
        fields: {
          Title: `Entry ${i}`,
          UserName: `user${i}`,
          Password: `pass${i}`,
          URL: `https://example${i}.com`,
          Notes: `Notes for entry ${i}`
        },
        times: {
          lastModificationTime: new Date(),
          creationTime: new Date(),
          lastAccessTime: new Date(),
          expiryTime: new Date(),
          expires: false,
          usageCount: 0,
          locationChanged: new Date()
        }
      });
    }

    const data = await writer.write(database, 'testpassword');
    expect(data).toBeInstanceOf(Uint8Array);
    expect(data.length).toBeGreaterThan(100000); // 应该生成较大的文件

    // 验证可以读取大文件
    const reader = new KdbxReader(data);
    const readDatabase = await reader.read('testpassword');
    expect(readDatabase.root.groups[0].entries.length).toBe(1001);
  });

  it('should handle protected fields', async () => {
    const database = createTestDatabase();

    // 添加受保护的字段
    database.root.groups[0].entries[0].fields.Password = {
      value: 'protected_password',
      protected: true
    };

    const data = await writer.write(database, 'testpassword');

    // 验证受保护字段的处理
    const reader = new KdbxReader(data);
    const readDatabase = await reader.read('testpassword');
    const entry = readDatabase.root.groups[0].entries[0];
    expect(entry.fields.Password.protected).toBe(true);
    expect(entry.fields.Password.value).toBe('protected_password');
  });

  it('should handle binary attachments', async () => {
    const database = createTestDatabase();

    // 添加二进制附件
    const attachment = KdbxUtils.generateRandom(new Uint8Array(1024));
    database.root.groups[0].entries[0].binaries = {
      'test.bin': {
        data: attachment,
        protected: false
      }
    };

    const data = await writer.write(database, 'testpassword');

    // 验证二进制附件的处理
    const reader = new KdbxReader(data);
    const readDatabase = await reader.read('testpassword');
    const entry = readDatabase.root.groups[0].entries[0];
    expect(entry.binaries['test.bin']).toBeDefined();
    expect(entry.binaries['test.bin'].data).toEqual(attachment);
  });

  it('should handle custom data', async () => {
    const database = createTestDatabase();

    // 添加自定义数据
    database.meta.customData = {
      'TestKey1': 'TestValue1',
      'TestKey2': 'TestValue2'
    };

    const data = await writer.write(database, 'testpassword');

    // 验证自定义数据的处理
    const reader = new KdbxReader(data);
    const readDatabase = await reader.read('testpassword');
    expect(readDatabase.meta.customData['TestKey1']).toBe('TestValue1');
    expect(readDatabase.meta.customData['TestKey2']).toBe('TestValue2');
  });

  it('should handle error conditions gracefully', async () => {
    // 测试无效的数据库对象
    await expect(writer.write(null, 'testpassword')).rejects.toThrow();
    await expect(writer.write(undefined, 'testpassword')).rejects.toThrow();
    await expect(writer.write({}, 'testpassword')).rejects.toThrow();

    // 测试无效的密码
    const database = createTestDatabase();
    await expect(writer.write(database, '')).rejects.toThrow();
    await expect(writer.write(database, null)).rejects.toThrow();

    // 测试无效的密钥文件
    await expect(writer.write(database, 'testpassword', new Uint8Array(0))).rejects.toThrow();
  });

  it('should maintain data integrity', async () => {
    const database = createTestDatabase();
    const password = 'testpassword';

    // 写入数据库
    const data = await writer.write(database, password);

    // 读取并验证所有字段
    const reader = new KdbxReader(data);
    const readDatabase = await reader.read(password);

    // 验证元数据
    expect(readDatabase.meta.generator).toBe(database.meta.generator);
    expect(readDatabase.meta.databaseName).toBe(database.meta.databaseName);
    expect(readDatabase.meta.databaseDescription).toBe(database.meta.databaseDescription);
    expect(readDatabase.meta.recycleBinEnabled).toBe(database.meta.recycleBinEnabled);
    expect(readDatabase.meta.recycleBinUUID).toBe(database.meta.recycleBinUUID);
    expect(readDatabase.meta.historyMaxItems).toBe(database.meta.historyMaxItems);
    expect(readDatabase.meta.historyMaxSize).toBe(database.meta.historyMaxSize);

    // 验证根组
    expect(readDatabase.root.uuid).toBe(database.root.uuid);
    expect(readDatabase.root.name).toBe(database.root.name);
    expect(readDatabase.root.iconId).toBe(database.root.iconId);

    // 验证子组
    const group = readDatabase.root.groups[0];
    const originalGroup = database.root.groups[0];
    expect(group.uuid).toBe(originalGroup.uuid);
    expect(group.name).toBe(originalGroup.name);
    expect(group.notes).toBe(originalGroup.notes);
    expect(group.iconId).toBe(originalGroup.iconId);

    // 验证条目
    const entry = group.entries[0];
    const originalEntry = originalGroup.entries[0];
    expect(entry.uuid).toBe(originalEntry.uuid);
    expect(entry.iconId).toBe(originalEntry.iconId);
    expect(entry.fields.Title).toBe(originalEntry.fields.Title);
    expect(entry.fields.UserName).toBe(originalEntry.fields.UserName);
    expect(entry.fields.Password).toBe(originalEntry.fields.Password);
    expect(entry.fields.URL).toBe(originalEntry.fields.URL);
    expect(entry.fields.Notes).toBe(originalEntry.fields.Notes);
  });
});
