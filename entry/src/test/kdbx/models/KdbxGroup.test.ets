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
import { KdbxGroup } from '../../../main/ets/kdbx/models/KdbxGroup';
import { KdbxEntry } from '../../../main/ets/kdbx/models/KdbxEntry';

describe('KdbxGroup', () => {
  const ROOT_UUID = 'root-uuid';
  const ROOT_NAME = 'Root Group';
  let rootGroup: KdbxGroup;

  beforeAll(() => {
    // 测试套件开始前的设置
  });

  beforeEach(() => {
    // 每个测试用例开始前的设置
    rootGroup = new KdbxGroup(ROOT_UUID, ROOT_NAME);
  });

  afterEach(() => {
    // 每个测试用例结束后的清理
  });

  afterAll(() => {
    // 测试套件结束后的清理
  });

  it('should initialize with correct default values', () => {
    expect(rootGroup.uuid).toBe(ROOT_UUID);
    expect(rootGroup.name).toBe(ROOT_NAME);
    expect(rootGroup.icon).toEqual({ id: 0 });
    expect(rootGroup.expires).toBe(false);
    expect(rootGroup.expiryTime).toBeUndefined();
    expect(rootGroup.parentGroup).toBeUndefined();
    expect(rootGroup.groups).toEqual([]);
    expect(rootGroup.entries).toEqual([]);
    expect(rootGroup.isExpanded).toBe(false);
    expect(rootGroup.isSelected).toBe(false);

    // 验证时间戳
    expect(rootGroup.creationTime).toBeInstanceOf(Date);
    expect(rootGroup.lastModifiedTime).toBeInstanceOf(Date);
    expect(rootGroup.lastAccessTime).toBeInstanceOf(Date);
  });

  it('should add and remove groups', () => {
    const subGroup1 = new KdbxGroup('sub1-uuid', 'Sub Group 1');
    const subGroup2 = new KdbxGroup('sub2-uuid', 'Sub Group 2');
    const initialModifiedTime = rootGroup.lastModifiedTime;

    // 等待一小段时间以确保时间戳不同
    setTimeout(() => {
      // 添加子组
      rootGroup.addGroup(subGroup1);
      expect(rootGroup.groups.length).toBe(1);
      expect(subGroup1.parentGroup).toBe(ROOT_UUID);
      expect(rootGroup.lastModifiedTime.getTime()).toBeGreaterThan(initialModifiedTime.getTime());

      rootGroup.addGroup(subGroup2);
      expect(rootGroup.groups.length).toBe(2);
      expect(subGroup2.parentGroup).toBe(ROOT_UUID);

      // 删除子组
      rootGroup.removeGroup('sub1-uuid');
      expect(rootGroup.groups.length).toBe(1);
      expect(rootGroup.groups[0].uuid).toBe('sub2-uuid');

      // 删除不存在的组不应有影响
      rootGroup.removeGroup('nonexistent-uuid');
      expect(rootGroup.groups.length).toBe(1);
    }, 10);
  });

  it('should add and remove entries', () => {
    const entry1 = new KdbxEntry('entry1-uuid', ROOT_UUID);
    const entry2 = new KdbxEntry('entry2-uuid', ROOT_UUID);
    const initialModifiedTime = rootGroup.lastModifiedTime;

    // 等待一小段时间以确保时间戳不同
    setTimeout(() => {
      // 添加条目
      rootGroup.addEntry(entry1);
      expect(rootGroup.entries.length).toBe(1);
      expect(entry1.parentGroup).toBe(ROOT_UUID);
      expect(rootGroup.lastModifiedTime.getTime()).toBeGreaterThan(initialModifiedTime.getTime());

      rootGroup.addEntry(entry2);
      expect(rootGroup.entries.length).toBe(2);
      expect(entry2.parentGroup).toBe(ROOT_UUID);

      // 删除条目
      rootGroup.removeEntry('entry1-uuid');
      expect(rootGroup.entries.length).toBe(1);
      expect(rootGroup.entries[0].uuid).toBe('entry2-uuid');

      // 删除不存在的条目不应有影响
      rootGroup.removeEntry('nonexistent-uuid');
      expect(rootGroup.entries.length).toBe(1);
    }, 10);
  });

  it('should find groups recursively', () => {
    const subGroup1 = new KdbxGroup('sub1-uuid', 'Sub Group 1');
    const subGroup2 = new KdbxGroup('sub2-uuid', 'Sub Group 2');
    const subGroup3 = new KdbxGroup('sub3-uuid', 'Sub Group 3');

    rootGroup.addGroup(subGroup1);
    subGroup1.addGroup(subGroup2);
    subGroup2.addGroup(subGroup3);

    // 查找根组
    expect(rootGroup.findGroup(ROOT_UUID)).toBe(rootGroup);

    // 查找直接子组
    expect(rootGroup.findGroup('sub1-uuid')).toBe(subGroup1);

    // 查找深层子组
    expect(rootGroup.findGroup('sub3-uuid')).toBe(subGroup3);

    // 查找不存在的组
    expect(rootGroup.findGroup('nonexistent-uuid')).toBeUndefined();
  });

  it('should find entries recursively', () => {
    const subGroup1 = new KdbxGroup('sub1-uuid', 'Sub Group 1');
    const subGroup2 = new KdbxGroup('sub2-uuid', 'Sub Group 2');
    const entry1 = new KdbxEntry('entry1-uuid', ROOT_UUID);
    const entry2 = new KdbxEntry('entry2-uuid', 'sub1-uuid');
    const entry3 = new KdbxEntry('entry3-uuid', 'sub2-uuid');

    rootGroup.addGroup(subGroup1);
    subGroup1.addGroup(subGroup2);
    rootGroup.addEntry(entry1);
    subGroup1.addEntry(entry2);
    subGroup2.addEntry(entry3);

    // 查找根组中的条目
    expect(rootGroup.findEntry('entry1-uuid')).toBe(entry1);

    // 查找子组中的条目
    expect(rootGroup.findEntry('entry2-uuid')).toBe(entry2);

    // 查找深层子组中的条目
    expect(rootGroup.findEntry('entry3-uuid')).toBe(entry3);

    // 查找不存在的条目
    expect(rootGroup.findEntry('nonexistent-uuid')).toBeUndefined();
  });

  it('should traverse groups', () => {
    const subGroup1 = new KdbxGroup('sub1-uuid', 'Sub Group 1');
    const subGroup2 = new KdbxGroup('sub2-uuid', 'Sub Group 2');
    const subGroup3 = new KdbxGroup('sub3-uuid', 'Sub Group 3');

    rootGroup.addGroup(subGroup1);
    subGroup1.addGroup(subGroup2);
    subGroup2.addGroup(subGroup3);

    const visitedGroups: string[] = [];
    rootGroup.traverseGroups(group => {
      visitedGroups.push(group.uuid);
    });

    expect(visitedGroups).toEqual([
      ROOT_UUID,
      'sub1-uuid',
      'sub2-uuid',
      'sub3-uuid'
    ]);
  });

  it('should traverse entries', () => {
    const subGroup1 = new KdbxGroup('sub1-uuid', 'Sub Group 1');
    const subGroup2 = new KdbxGroup('sub2-uuid', 'Sub Group 2');
    const entry1 = new KdbxEntry('entry1-uuid', ROOT_UUID);
    const entry2 = new KdbxEntry('entry2-uuid', 'sub1-uuid');
    const entry3 = new KdbxEntry('entry3-uuid', 'sub2-uuid');

    rootGroup.addGroup(subGroup1);
    subGroup1.addGroup(subGroup2);
    rootGroup.addEntry(entry1);
    subGroup1.addEntry(entry2);
    subGroup2.addEntry(entry3);

    const visitedEntries: string[] = [];
    rootGroup.traverseEntries(entry => {
      visitedEntries.push(entry.uuid);
    });

    expect(visitedEntries).toEqual([
      'entry1-uuid',
      'entry2-uuid',
      'entry3-uuid'
    ]);
  });

  it('should update access time', () => {
    const initialAccessTime = rootGroup.lastAccessTime;

    // 等待一小段时间以确保时间戳不同
    setTimeout(() => {
      rootGroup.touch();
      expect(rootGroup.lastAccessTime.getTime()).toBeGreaterThan(initialAccessTime.getTime());
    }, 10);
  });

  it('should check expiry status', () => {
    // 默认不过期
    expect(rootGroup.isExpired()).toBe(false);

    // 设置过期时间为过去
    const pastDate = new Date();
    pastDate.setDate(pastDate.getDate() - 1); // 昨天
    rootGroup.expires = true;
    rootGroup.expiryTime = pastDate;
    expect(rootGroup.isExpired()).toBe(true);

    // 设置过期时间为未来
    const futureDate = new Date();
    futureDate.setDate(futureDate.getDate() + 1); // 明天
    rootGroup.expiryTime = futureDate;
    expect(rootGroup.isExpired()).toBe(false);

    // 禁用过期
    rootGroup.expires = false;
    expect(rootGroup.isExpired()).toBe(false);
  });

  it('should handle deep group hierarchies', () => {
    // 创建一个深层的组层次结构
    const groups: KdbxGroup[] = [];
    let currentGroup = rootGroup;

    // 创建10层深的结构
    for (let i = 0; i < 10; i++) {
      const newGroup = new KdbxGroup(`group${i}-uuid`, `Group ${i}`);
      groups.push(newGroup);
      currentGroup.addGroup(newGroup);
      currentGroup = newGroup;
    }

    // 验证层次结构
    currentGroup = rootGroup;
    for (let i = 0; i < 10; i++) {
      expect(currentGroup.groups.length).toBe(1);
      currentGroup = currentGroup.groups[0];
      expect(currentGroup.uuid).toBe(`group${i}-uuid`);
      expect(currentGroup.name).toBe(`Group ${i}`);
      expect(currentGroup.parentGroup).toBe(i === 0 ? ROOT_UUID : `group${i-1}-uuid`);
    }

    // 验证查找功能在深层结构中工作
    expect(rootGroup.findGroup('group9-uuid')).toBe(groups[9]);

    // 验证遍历功能在深层结构中工作
    const visitedGroups: string[] = [];
    rootGroup.traverseGroups(group => {
      visitedGroups.push(group.uuid);
    });

    expect(visitedGroups.length).toBe(11); // root + 10 groups
    expect(visitedGroups[0]).toBe(ROOT_UUID);
    for (let i = 0; i < 10; i++) {
      expect(visitedGroups[i + 1]).toBe(`group${i}-uuid`);
    }
  });

  it('should handle concurrent modifications', () => {
    const subGroup1 = new KdbxGroup('sub1-uuid', 'Sub Group 1');
    const subGroup2 = new KdbxGroup('sub2-uuid', 'Sub Group 2');
    const entry1 = new KdbxEntry('entry1-uuid', ROOT_UUID);
    const entry2 = new KdbxEntry('entry2-uuid', ROOT_UUID);

    // 同时添加组和条目
    rootGroup.addGroup(subGroup1);
    rootGroup.addEntry(entry1);
    expect(rootGroup.groups.length).toBe(1);
    expect(rootGroup.entries.length).toBe(1);

    // 同时删除和添加
    rootGroup.removeGroup('sub1-uuid');
    rootGroup.addGroup(subGroup2);
    rootGroup.removeEntry('entry1-uuid');
    rootGroup.addEntry(entry2);
    expect(rootGroup.groups.length).toBe(1);
    expect(rootGroup.groups[0].uuid).toBe('sub2-uuid');
    expect(rootGroup.entries.length).toBe(1);
    expect(rootGroup.entries[0].uuid).toBe('entry2-uuid');
  });
});
