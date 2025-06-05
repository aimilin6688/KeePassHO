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

export default function KdbxEntryUnitTest() {
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

    it('should initialize with correct default values', 0, () => {
      expect(entry.uuid).assertEqual(TEST_UUID);
      expect(entry.parentGroup).assertEqual(TEST_GROUP_UUID);
      expect(entry.icon).assertEqual({ id: 0 });
      expect(entry.expires).assertEqual(false);
      expect(entry.usageCount).assertEqual(0);
      expect(entry.favorite).assertEqual(false);
      expect(entry.tags).assertEqual([]);
      expect(entry.attachments).assertEqual([]);
      expect(entry.customData).assertEqual([]);
      expect(entry.history).assertEqual([]);

      // 验证默认字段
      expect(entry.fields.length).assertEqual(5);
      expect(entry.getField('Title')).assertEqual('');
      expect(entry.getField('UserName')).assertEqual('');
      expect(entry.getField('Password')).assertEqual('');
      expect(entry.getField('URL')).assertEqual('');
      expect(entry.getField('Notes')).assertEqual('');

      // 验证字段保护状态
      const passwordField = entry.fields.find(f => f.name === 'Password');
      expect(passwordField?.protected).assertEqual(true);

      const titleField = entry.fields.find(f => f.name === 'Title');
      expect(titleField?.protected).assertEqual(false);
    });

    it('should get and set standard fields correctly', 0, () => {
      entry.title = 'Test Title';
      entry.username = 'testuser';
      entry.password = 'testpassword';
      entry.url = 'https://example.com';
      entry.notes = 'Test notes';

      expect(entry.title).assertEqual('Test Title');
      expect(entry.username).assertEqual('testuser');
      expect(entry.password).assertEqual('testpassword');
      expect(entry.url).assertEqual('https://example.com');
      expect(entry.notes).assertEqual('Test notes');

      // 验证通过getField方法
      expect(entry.getField('Title')).assertEqual('Test Title');
      expect(entry.getField('UserName')).assertEqual('testuser');
      expect(entry.getField('Password')).assertEqual('testpassword');
      expect(entry.getField('URL')).assertEqual('https://example.com');
      expect(entry.getField('Notes')).assertEqual('Test notes');
    });

    it('should set and get custom fields', 0, () => {
      entry.setField('CustomField1', 'CustomValue1');
      entry.setField('CustomField2', 'CustomValue2', true); // 受保护字段

      expect(entry.getField('CustomField1')).assertEqual('CustomValue1');
      expect(entry.getField('CustomField2')).assertEqual('CustomValue2');

      // 验证字段数量
      expect(entry.fields.length).assertEqual(7); // 5个默认字段 + 2个自定义字段

      // 验证保护状态
      const customField1 = entry.fields.find(f => f.name === 'CustomField1');
      expect(customField1?.protected).assertEqual(false);

      const customField2 = entry.fields.find(f => f.name === 'CustomField2');
      expect(customField2?.protected).assertEqual(true);
    });

    it('should update existing fields', 0, () => {
      entry.title = 'Initial Title';
      expect(entry.title).assertEqual('Initial Title');

      entry.setField('Title', 'Updated Title');
      expect(entry.title).assertEqual('Updated Title');
      expect(entry.fields.length).assertEqual(5); // 字段数量不变
    });

    it('should delete fields', 0, () => {
      entry.setField('CustomField', 'Value');
      expect(entry.fields.length).assertEqual(6);

      entry.deleteField('CustomField');
      expect(entry.fields.length).assertEqual(5);
      expect(entry.getField('CustomField')).assertUndefined();

      // 删除不存在的字段不应有影响
      entry.deleteField('NonExistentField');
      expect(entry.fields.length).assertEqual(5);
    });

    it('should handle attachments', 0, () => {
      const testData1 = new Uint8Array([1, 2, 3, 4]);
      const testData2 = new Uint8Array([5, 6, 7, 8]);

      entry.addAttachment('attachment1.txt', testData1);
      entry.addAttachment('attachment2.bin', testData2);

      expect(entry.attachments.length).assertEqual(2);
      expect(entry.attachments[0].name).assertEqual('attachment1.txt');
      expect(entry.attachments[0].data).assertEqual(testData1);
      expect(entry.attachments[0].size).assertEqual(4);

      entry.deleteAttachment('attachment1.txt');
      expect(entry.attachments.length).assertEqual(1);
      expect(entry.attachments[0].name).assertEqual('attachment2.bin');

      // 删除不存在的附件不应有影响
      entry.deleteAttachment('nonexistent.txt');
      expect(entry.attachments.length).assertEqual(1);
    });

    it('should handle tags', 0, () => {
      entry.addTag('work');
      entry.addTag('important');

      expect(entry.tags.length).assertEqual(2);
      expect(entry.tags).assertContain('work');
      expect(entry.tags).assertContain('important');

      // 添加重复标签不应有影响
      entry.addTag('work');
      expect(entry.tags.length).assertEqual(2);

      entry.removeTag('work');
      expect(entry.tags.length).assertEqual(1);
      expect(entry.tags).assertContain('important');

      // 删除不存在的标签不应有影响
      entry.removeTag('nonexistent');
      expect(entry.tags.length).assertEqual(1);
    });

    it('should update usage count and access time', 0, () => {
      const initialAccessTime = entry.lastAccessTime;
      const initialUsageCount = entry.usageCount;

      // 等待一小段时间以确保时间戳不同
      setTimeout(() => {
        entry.touch();

        expect(entry.usageCount).assertEqual(initialUsageCount + 1);
        expect(entry.lastAccessTime.getTime()).assertLess(initialAccessTime.getTime());
      }, 10);
    });

    it('should create history entries', 0, () => {
      entry.title = 'Original Title';
      entry.username = 'originaluser';

      entry.createHistoryEntry();
      expect(entry.history.length).assertEqual(1);
      expect(entry.history[0].title).assertEqual('Original Title');
      expect(entry.history[0].username).assertEqual('originaluser');

      // 修改当前条目
      entry.title = 'Updated Title';
      entry.username = 'updateduser';

      // 创建另一个历史条目
      entry.createHistoryEntry();
      expect(entry.history.length).assertEqual(2);
      expect(entry.history[1].title).assertEqual('Updated Title');
      expect(entry.history[1].username).assertEqual('updateduser');

      // 历史条目不应包含历史
      expect(entry.history[0].history.length).assertEqual(0);
      expect(entry.history[1].history.length).assertEqual(0);
    });

    it('should check expiry status', 0, () => {
      // 默认不过期
      expect(entry.isExpired()).assertEqual(false);

      // 设置过期时间为过去
      const pastDate = new Date();
      pastDate.setDate(pastDate.getDate() - 1); // 昨天
      entry.expires = true;
      entry.expiryTime = pastDate;
      expect(entry.isExpired()).assertEqual(true);

      // 设置过期时间为未来
      const futureDate = new Date();
      futureDate.setDate(futureDate.getDate() + 1); // 明天
      entry.expiryTime = futureDate;
      expect(entry.isExpired()).assertEqual(false);
    });

    it('should clone entries correctly', 0, () => {
      entry.title = 'Test Title';
      entry.username = 'testuser';
      entry.password = 'testpassword';
      entry.addTag('work');
      entry.setField('CustomField', 'CustomValue');
      entry.addAttachment('test.txt', new Uint8Array([1, 2, 3]));

      const cloned = entry.clone();

      expect(cloned.uuid).assertEqual(entry.uuid);
      expect(cloned.title).assertEqual(entry.title);
      expect(cloned.username).assertEqual(entry.username);
      expect(cloned.password).assertEqual(entry.password);
      expect(cloned.tags).assertEqual(entry.tags);
      expect(cloned.fields.length).assertEqual(entry.fields.length);
      expect(cloned.attachments.length).assertEqual(entry.attachments.length);

      // 修改原始条目不应影响克隆
      entry.title = 'Modified Title';
      expect(cloned.title).assertEqual('Test Title');
    });

    it('should compare entries correctly', 0, () => {
      entry.title = 'Test Title';
      entry.username = 'testuser';

      const identical = entry.clone();
      expect(entry.equals(identical)).assertEqual(true);

      // 修改字段值
      const modified = entry.clone();
      modified.title = 'Different Title';
      expect(entry.equals(modified)).assertEqual(false);

      // 添加新字段
      const withExtraField = entry.clone();
      withExtraField.setField('ExtraField', 'Value');
      expect(entry.equals(withExtraField)).assertEqual(false);
    });

    it('should validate entries', 0, () => {
      // 空条目应该无效
      const result1 = entry.validate();
      expect(result1.valid).assertEqual(false);
      expect(result1.errors.length).assertLarger(0);

      // 设置标题但无用户名和密码
      entry.title = 'Test Title';
      const result2 = entry.validate();
      expect(result2.valid).assertEqual(false);
      expect(result2.errors.length).assertLarger(0);

      // 设置标题和用户名
      entry.username = 'testuser';
      const result3 = entry.validate();
      expect(result3.valid).assertEqual(true);
      expect(result3.errors.length).assertEqual(0);

      // 或者设置标题和密码
      entry.username = '';
      entry.password = 'testpassword';
      const result4 = entry.validate();
      expect(result4.valid).assertEqual(true);
      expect(result4.errors.length).assertEqual(0);
    });

    it('should generate summary information', 0, () => {
      entry.title = 'Test Entry';
      entry.username = 'testuser';
      entry.password = 'password';
      entry.url = 'https://example.com';
      entry.notes = 'Some notes';
      entry.addAttachment('file.txt', new Uint8Array([1, 2, 3]));

      const summary = entry.getSummary();

      expect(summary.title).assertEqual('Test Entry');
      expect(summary.username).assertEqual('testuser');
      expect(summary.hasPassword).assertEqual(true);
      expect(summary.hasUrl).assertEqual(true);
      expect(summary.hasNotes).assertEqual(true);
      expect(summary.attachmentCount).assertEqual(1);
    });

    it('should generate passwords', 0, () => {
      const password1 = entry.generatePassword({ length: 16 });
      expect(password1.length).assertEqual(16);
      expect(entry.password).assertEqual(password1);

      const password2 = entry.generatePassword({
        length: 12,
        useUpperCase: true,
        useLowerCase: true,
        useDigits: true,
        useSpecial: false
      });
      expect(password2.length).assertEqual(12);
      expect(password2).not().assertContain('!');
      expect(password2).not().assertContain('@');
      expect(entry.password).assertEqual(password2);
    });

    it('should check password strength', 0, () => {
      // 空密码
      entry.password = '';
      const result1 = entry.checkPasswordStrength();
      expect(result1.score).assertEqual(0);
      expect(result1.suggestions.length).assertLarger(0);

      // 弱密码
      entry.password = 'password';
      const result2 = entry.checkPasswordStrength();
      expect(result2.score).assertLess(50);
      expect(result2.suggestions.length).assertLarger(0);

      // 强密码
      entry.password = 'P@ssw0rd!2023Complex';
      const result3 = entry.checkPasswordStrength();
      expect(result3.score).assertLarger(70);
    });

    it('should search fields', 0, () => {
      entry.title = 'My Bank Account';
      entry.username = 'john.doe@example.com';
      entry.password = 'secret123';
      entry.url = 'https://bank.example.com';
      entry.notes = 'This is my main bank account';
      entry.setField('CustomField', 'Custom Value');

      // 基本搜索
      const results1 = entry.searchFields('bank');
      expect(results1.length).assertEqual(2); // 标题和备注中包含"bank"

      // 区分大小写搜索
      const results2 = entry.searchFields('Bank', { caseSensitive: true });
      expect(results2.length).assertEqual(1); // 只有标题中包含"Bank"

      // 搜索受保护字段
      const results3 = entry.searchFields('secret', { includeProtected: true });
      expect(results3.length).assertEqual(1); // 密码中包含"secret"

      const results4 = entry.searchFields('secret', { includeProtected: false });
      expect(results4.length).assertEqual(0); // 不搜索受保护字段

      // 指定字段搜索
      const results5 = entry.searchFields('example', { fieldNames: ['URL'] });
      expect(results5.length).assertEqual(1); // 只在URL中搜索

      const results6 = entry.searchFields('example', { fieldNames: ['Title', 'Notes'] });
      expect(results6.length).assertEqual(0); // 标题和备注中不包含"example"
    });

    it('should export to different formats', 0, () => {
      entry.title = 'Test Entry';
      entry.username = 'testuser';
      entry.password = 'testpassword';
      entry.url = 'https://example.com';
      entry.notes = 'Test notes';
      entry.addTag('work');
      entry.addTag('important');

      // JSON导出
      const json = entry.export('json');
      expect(json).assertContain('"title":"Test Entry"');
      expect(json).assertContain('"username":"testuser"');
      expect(json).assertContain('"url":"https://example.com"');
      expect(json).assertContain('"notes":"Test notes"');
      expect(json).assertContain('"tags":["work","important"]');

      // CSV导出
      const csv = entry.export('csv');
      expect(csv).assertEqual('"Test Entry","testuser","https://example.com","Test notes","work;important"');

      // XML导出
      const xml = entry.export('xml');
      expect(xml).assertContain('<title>Test Entry</title>');
      expect(xml).assertContain('<username>testuser</username>');
      expect(xml).assertContain('<url>https://example.com</url>');
      expect(xml).assertContain('<notes>Test notes</notes>');
      expect(xml).assertContain('<tags>work;important</tags>');
    });
  });
}

