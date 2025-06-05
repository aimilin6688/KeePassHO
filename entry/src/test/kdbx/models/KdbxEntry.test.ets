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
import { KdbxEntry } from '../../../main/ets/kdbx/models/KdbxEntry';

describe('KdbxEntry', () => {
  const TEST_UUID = 'test-uuid-1234';
  const TEST_GROUP_UUID = 'test-group-uuid-5678';
  let entry: KdbxEntry;

  beforeAll(() => {
    // 测试套件开始前的设置
  });

  beforeEach(() => {
    // 每个测试用例开始前的设置
    entry = new KdbxEntry(TEST_UUID, TEST_GROUP_UUID);
  });

  afterEach(() => {
    // 每个测试用例结束后的清理
  });

  afterAll(() => {
    // 测试套件结束后的清理
  });

  it('should initialize with correct default values', () => {
    expect(entry.uuid).toBe(TEST_UUID);
    expect(entry.parentGroup).toBe(TEST_GROUP_UUID);
    expect(entry.icon).toEqual({ id: 0 });
    expect(entry.expires).toBe(false);
    expect(entry.usageCount).toBe(0);
    expect(entry.favorite).toBe(false);
    expect(entry.tags).toEqual([]);
    expect(entry.attachments).toEqual([]);
    expect(entry.customData).toEqual([]);
    expect(entry.history).toEqual([]);

    // 验证默认字段
    expect(entry.fields.length).toBe(5);
    expect(entry.getField('Title')).toBe('');
    expect(entry.getField('UserName')).toBe('');
    expect(entry.getField('Password')).toBe('');
    expect(entry.getField('URL')).toBe('');
    expect(entry.getField('Notes')).toBe('');

    // 验证字段保护状态
    const passwordField = entry.fields.find(f => f.name === 'Password');
    expect(passwordField?.protected).toBe(true);

    const titleField = entry.fields.find(f => f.name === 'Title');
    expect(titleField?.protected).toBe(false);
  });

  it('should get and set standard fields correctly', () => {
    entry.title = 'Test Title';
    entry.username = 'testuser';
    entry.password = 'testpassword';
    entry.url = 'https://example.com';
    entry.notes = 'Test notes';

    expect(entry.title).toBe('Test Title');
    expect(entry.username).toBe('testuser');
    expect(entry.password).toBe('testpassword');
    expect(entry.url).toBe('https://example.com');
    expect(entry.notes).toBe('Test notes');

    // 验证通过getField方法
    expect(entry.getField('Title')).toBe('Test Title');
    expect(entry.getField('UserName')).toBe('testuser');
    expect(entry.getField('Password')).toBe('testpassword');
    expect(entry.getField('URL')).toBe('https://example.com');
    expect(entry.getField('Notes')).toBe('Test notes');
  });

  it('should set and get custom fields', () => {
    entry.setField('CustomField1', 'CustomValue1');
    entry.setField('CustomField2', 'CustomValue2', true); // 受保护字段

    expect(entry.getField('CustomField1')).toBe('CustomValue1');
    expect(entry.getField('CustomField2')).toBe('CustomValue2');

    // 验证字段数量
    expect(entry.fields.length).toBe(7); // 5个默认字段 + 2个自定义字段

    // 验证保护状态
    const customField1 = entry.fields.find(f => f.name === 'CustomField1');
    expect(customField1?.protected).toBe(false);

    const customField2 = entry.fields.find(f => f.name === 'CustomField2');
    expect(customField2?.protected).toBe(true);
  });

  it('should update existing fields', () => {
    entry.title = 'Initial Title';
    expect(entry.title).toBe('Initial Title');

    entry.setField('Title', 'Updated Title');
    expect(entry.title).toBe('Updated Title');
    expect(entry.fields.length).toBe(5); // 字段数量不变
  });

  it('should delete fields', () => {
    entry.setField('CustomField', 'Value');
    expect(entry.fields.length).toBe(6);

    entry.deleteField('CustomField');
    expect(entry.fields.length).toBe(5);
    expect(entry.getField('CustomField')).toBeUndefined();

    // 删除不存在的字段不应有影响
    entry.deleteField('NonExistentField');
    expect(entry.fields.length).toBe(5);
  });

  it('should handle attachments', () => {
    const testData1 = new Uint8Array([1, 2, 3, 4]);
    const testData2 = new Uint8Array([5, 6, 7, 8]);

    entry.addAttachment('attachment1.txt', testData1);
    entry.addAttachment('attachment2.bin', testData2);

    expect(entry.attachments.length).toBe(2);
    expect(entry.attachments[0].name).toBe('attachment1.txt');
    expect(entry.attachments[0].data).toBe(testData1);
    expect(entry.attachments[0].size).toBe(4);

    entry.deleteAttachment('attachment1.txt');
    expect(entry.attachments.length).toBe(1);
    expect(entry.attachments[0].name).toBe('attachment2.bin');

    // 删除不存在的附件不应有影响
    entry.deleteAttachment('nonexistent.txt');
    expect(entry.attachments.length).toBe(1);
  });

  it('should handle tags', () => {
    entry.addTag('work');
    entry.addTag('important');

    expect(entry.tags.length).toBe(2);
    expect(entry.tags).toContain('work');
    expect(entry.tags).toContain('important');

    // 添加重复标签不应有影响
    entry.addTag('work');
    expect(entry.tags.length).toBe(2);

    entry.removeTag('work');
    expect(entry.tags.length).toBe(1);
    expect(entry.tags).toContain('important');

    // 删除不存在的标签不应有影响
    entry.removeTag('nonexistent');
    expect(entry.tags.length).toBe(1);
  });

  it('should update usage count and access time', () => {
    const initialAccessTime = entry.lastAccessTime;
    const initialUsageCount = entry.usageCount;

    // 等待一小段时间以确保时间戳不同
    setTimeout(() => {
      entry.touch();

      expect(entry.usageCount).toBe(initialUsageCount + 1);
      expect(entry.lastAccessTime.getTime()).toBeGreaterThan(initialAccessTime.getTime());
    }, 10);
  });

  it('should create history entries', () => {
    entry.title = 'Original Title';
    entry.username = 'originaluser';

    entry.createHistoryEntry();
    expect(entry.history.length).toBe(1);
    expect(entry.history[0].title).toBe('Original Title');
    expect(entry.history[0].username).toBe('originaluser');

    // 修改当前条目
    entry.title = 'Updated Title';
    entry.username = 'updateduser';

    // 创建另一个历史条目
    entry.createHistoryEntry();
    expect(entry.history.length).toBe(2);
    expect(entry.history[1].title).toBe('Updated Title');
    expect(entry.history[1].username).toBe('updateduser');

    // 历史条目不应包含历史
    expect(entry.history[0].history.length).toBe(0);
    expect(entry.history[1].history.length).toBe(0);
  });

  it('should check expiry status', () => {
    // 默认不过期
    expect(entry.isExpired()).toBe(false);

    // 设置过期时间为过去
    const pastDate = new Date();
    pastDate.setDate(pastDate.getDate() - 1); // 昨天
    entry.expires = true;
    entry.expiryTime = pastDate;
    expect(entry.isExpired()).toBe(true);

    // 设置过期时间为未来
    const futureDate = new Date();
    futureDate.setDate(futureDate.getDate() + 1); // 明天
    entry.expiryTime = futureDate;
    expect(entry.isExpired()).toBe(false);
  });

  it('should clone entries correctly', () => {
    entry.title = 'Test Title';
    entry.username = 'testuser';
    entry.password = 'testpassword';
    entry.addTag('work');
    entry.setField('CustomField', 'CustomValue');
    entry.addAttachment('test.txt', new Uint8Array([1, 2, 3]));

    const cloned = entry.clone();

    expect(cloned.uuid).toBe(entry.uuid);
    expect(cloned.title).toBe(entry.title);
    expect(cloned.username).toBe(entry.username);
    expect(cloned.password).toBe(entry.password);
    expect(cloned.tags).toEqual(entry.tags);
    expect(cloned.fields.length).toBe(entry.fields.length);
    expect(cloned.attachments.length).toBe(entry.attachments.length);

    // 修改原始条目不应影响克隆
    entry.title = 'Modified Title';
    expect(cloned.title).toBe('Test Title');
  });

  it('should compare entries correctly', () => {
    entry.title = 'Test Title';
    entry.username = 'testuser';

    const identical = entry.clone();
    expect(entry.equals(identical)).toBe(true);

    // 修改字段值
    const modified = entry.clone();
    modified.title = 'Different Title';
    expect(entry.equals(modified)).toBe(false);

    // 添加新字段
    const withExtraField = entry.clone();
    withExtraField.setField('ExtraField', 'Value');
    expect(entry.equals(withExtraField)).toBe(false);
  });

  it('should validate entries', () => {
    // 空条目应该无效
    const result1 = entry.validate();
    expect(result1.valid).toBe(false);
    expect(result1.errors.length).toBeGreaterThan(0);

    // 设置标题但无用户名和密码
    entry.title = 'Test Title';
    const result2 = entry.validate();
    expect(result2.valid).toBe(false);
    expect(result2.errors.length).toBeGreaterThan(0);

    // 设置标题和用户名
    entry.username = 'testuser';
    const result3 = entry.validate();
    expect(result3.valid).toBe(true);
    expect(result3.errors.length).toBe(0);

    // 或者设置标题和密码
    entry.username = '';
    entry.password = 'testpassword';
    const result4 = entry.validate();
    expect(result4.valid).toBe(true);
    expect(result4.errors.length).toBe(0);
  });

  it('should generate summary information', () => {
    entry.title = 'Test Entry';
    entry.username = 'testuser';
    entry.password = 'password';
    entry.url = 'https://example.com';
    entry.notes = 'Some notes';
    entry.addAttachment('file.txt', new Uint8Array([1, 2, 3]));

    const summary = entry.getSummary();

    expect(summary.title).toBe('Test Entry');
    expect(summary.username).toBe('testuser');
    expect(summary.hasPassword).toBe(true);
    expect(summary.hasUrl).toBe(true);
    expect(summary.hasNotes).toBe(true);
    expect(summary.attachmentCount).toBe(1);
  });

  it('should generate passwords', () => {
    const password1 = entry.generatePassword({ length: 16 });
    expect(password1.length).toBe(16);
    expect(entry.password).toBe(password1);

    const password2 = entry.generatePassword({
      length: 12,
      useUpperCase: true,
      useLowerCase: true,
      useDigits: true,
      useSpecial: false
    });
    expect(password2.length).toBe(12);
    expect(password2).not.toContain('!');
    expect(password2).not.toContain('@');
    expect(entry.password).toBe(password2);
  });

  it('should check password strength', () => {
    // 空密码
    entry.password = '';
    const result1 = entry.checkPasswordStrength();
    expect(result1.score).toBe(0);
    expect(result1.suggestions.length).toBeGreaterThan(0);

    // 弱密码
    entry.password = 'password';
    const result2 = entry.checkPasswordStrength();
    expect(result2.score).toBeLessThan(50);
    expect(result2.suggestions.length).toBeGreaterThan(0);

    // 强密码
    entry.password = 'P@ssw0rd!2023Complex';
    const result3 = entry.checkPasswordStrength();
    expect(result3.score).toBeGreaterThan(70);
  });

  it('should search fields', () => {
    entry.title = 'My Bank Account';
    entry.username = 'john.doe@example.com';
    entry.password = 'secret123';
    entry.url = 'https://bank.example.com';
    entry.notes = 'This is my main bank account';
    entry.setField('CustomField', 'Custom Value');

    // 基本搜索
    const results1 = entry.searchFields('bank');
    expect(results1.length).toBe(2); // 标题和备注中包含"bank"

    // 区分大小写搜索
    const results2 = entry.searchFields('Bank', { caseSensitive: true });
    expect(results2.length).toBe(1); // 只有标题中包含"Bank"

    // 搜索受保护字段
    const results3 = entry.searchFields('secret', { includeProtected: true });
    expect(results3.length).toBe(1); // 密码中包含"secret"

    const results4 = entry.searchFields('secret', { includeProtected: false });
    expect(results4.length).toBe(0); // 不搜索受保护字段

    // 指定字段搜索
    const results5 = entry.searchFields('example', { fieldNames: ['URL'] });
    expect(results5.length).toBe(1); // 只在URL中搜索

    const results6 = entry.searchFields('example', { fieldNames: ['Title', 'Notes'] });
    expect(results6.length).toBe(0); // 标题和备注中不包含"example"
  });

  it('should export to different formats', () => {
    entry.title = 'Test Entry';
    entry.username = 'testuser';
    entry.password = 'testpassword';
    entry.url = 'https://example.com';
    entry.notes = 'Test notes';
    entry.addTag('work');
    entry.addTag('important');

    // JSON导出
    const json = entry.export('json');
    expect(json).toContain('"title":"Test Entry"');
    expect(json).toContain('"username":"testuser"');
    expect(json).toContain('"url":"https://example.com"');
    expect(json).toContain('"notes":"Test notes"');
    expect(json).toContain('"tags":["work","important"]');

    // CSV导出
    const csv = entry.export('csv');
    expect(csv).toBe('"Test Entry","testuser","https://example.com","Test notes","work;important"');

    // XML导出
    const xml = entry.export('xml');
    expect(xml).toContain('<title>Test Entry</title>');
    expect(xml).toContain('<username>testuser</username>');
    expect(xml).toContain('<url>https://example.com</url>');
    expect(xml).toContain('<notes>Test notes</notes>');
    expect(xml).toContain('<tags>work;important</tags>');

    // 无效格式
    expect(() => {
      // @ts-ignore: 测试无效格式
      entry.export('invalid');
    }).toThrow();
  });
});
