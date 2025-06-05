import { KdbxUtils } from '../utils/KdbxUtils';
import {
  BinaryAttachment,
  CustomData,
  Field,
  GeneratePasswordOptions,
  Icon,
  KdbxEntrySummary,
  PasswordStrength,
  SearchFieldOptions,
  TimeStamp,
  UUID,
  ValidateResult
} from './KdbxTypes';

/**
 * 数据库条目
 */
export class KdbxEntry {
  /**
   * 条目UUID
   */
  uuid: UUID;
  /**
   * 图标
   */
  icon: Icon;
  /**
   * 创建时间
   */
  creationTime: TimeStamp;
  /**
   * 最后修改时间
   */
  lastModifiedTime: TimeStamp;
  /**
   * 最后访问时间
   */
  lastAccessTime: TimeStamp;
  /**
   * 过期时间
   */
  expiryTime?: TimeStamp;
  /**
   * 是否过期
   */
  expires: boolean = false;
  /**
   * 使用次数
   */
  usageCount: number = 0;
  /**
   * 所属组UUID
   */
  parentGroup: UUID;
  /**
   * 标签列表
   */
  tags: string[] = [];
  /**
   * 字段列表
   */
  fields: Field[] = [];
  /**
   * 附件列表
   */
  attachments: BinaryAttachment[] = [];
  /**
   * 自定义数据
   */
  customData: CustomData[] = [];
  /**
   * 历史记录
   */
  history: KdbxEntry[] = [];
  /**
   * 前一个版本的UUID
   */
  previousVersionUUID?: UUID;
  /**
   * 是否收藏
   */
  favorite: boolean = false;

  /**
   * 构造函数
   * @param uuid 条目UUID
   * @param parentGroup 所属组UUID
   */
  constructor(uuid: UUID, parentGroup: UUID) {
    this.uuid = uuid;
    this.parentGroup = parentGroup;
    this.creationTime = new Date();
    this.lastModifiedTime = new Date();
    this.lastAccessTime = new Date();
    this.icon = { id: 0 };

    // 初始化标准字段
    this.fields = [
      { name: 'Title', value: '', protected: false },
      { name: 'UserName', value: '', protected: false },
      { name: 'Password', value: '', protected: true },
      { name: 'URL', value: '', protected: false },
      { name: 'Notes', value: '', protected: false }
    ];
  }

  /**
   * 获取字段值
   * @param name 字段名
   * @returns 字段值
   */
  getField(name: string): string | undefined {
    const field = this.fields.find(f => f.name === name);
    if (!field) {
      return undefined;
    }
    return typeof field.value === 'string' ? field.value : undefined;
  }

  /**
   * 设置字段值
   * @param name 字段名
   * @param value 字段值
   * @param protect 是否保护
   */
  setField(name: string, value: string, protect: boolean = false): void {
    const index = this.fields.findIndex(f => f.name === name);
    const field: Field = {
      name,
      value,
      protected: protect
    };

    if (index >= 0) {
      this.fields[index] = field;
    } else {
      this.fields.push(field);
    }
    this.lastModifiedTime = new Date();
  }

  /**
   * 删除字段
   * @param name 字段名
   */
  deleteField(name: string): void {
    const index = this.fields.findIndex(f => f.name === name);
    if (index >= 0) {
      this.fields.splice(index, 1);
      this.lastModifiedTime = new Date();
    }
  }

  /**
   * 添加附件
   * @param name 附件名
   * @param data 附件数据
   */
  addAttachment(name: string, data: Uint8Array): void {
    this.attachments.push({
      name,
      data,
      size: data.length
    });
    this.lastModifiedTime = new Date();
  }

  /**
   * 删除附件
   * @param name 附件名
   */
  deleteAttachment(name: string): void {
    const index = this.attachments.findIndex(a => a.name === name);
    if (index >= 0) {
      this.attachments.splice(index, 1);
      this.lastModifiedTime = new Date();
    }
  }

  /**
   * 添加标签
   * @param tag 标签
   */
  addTag(tag: string): void {
    if (!this.tags.includes(tag)) {
      this.tags.push(tag);
      this.lastModifiedTime = new Date();
    }
  }

  /**
   * 删除标签
   * @param tag 标签
   */
  removeTag(tag: string): void {
    const index = this.tags.indexOf(tag);
    if (index >= 0) {
      this.tags.splice(index, 1);
      this.lastModifiedTime = new Date();
    }
  }

  /**
   * 更新访问时间
   */
  touch(): void {
    this.lastAccessTime = new Date();
    this.usageCount++;
  }

  /**
   * 创建历史版本
   */
  createHistoryEntry(): void {
    // 创建当前条目的副本
    const historyEntry = this.cloneTo(new KdbxEntry(this.uuid, this.parentGroup));
    historyEntry.history = []; // 历史记录不需要包含历史
    this.history.push(historyEntry);
  }

  /**
   * 检查是否过期
   * @returns 是否过期
   */
  isExpired(): boolean {
    return this.expires && this.expiryTime !== undefined && this.expiryTime <= new Date();
  }

  // 标准字段访问方法

  get title(): string {
    return this.getField('Title') || '';
  }

  set title(value: string) {
    this.setField('Title', value);
  }

  get username(): string {
    return this.getField('UserName') || '';
  }

  set username(value: string) {
    this.setField('UserName', value);
  }

  get password(): string {
    return this.getField('Password') || '';
  }

  set password(value: string) {
    this.setField('Password', value, true); // 密码默认受保护
  }

  get url(): string {
    return this.getField('URL') || '';
  }

  set url(value: string) {
    this.setField('URL', value);
  }

  get notes(): string {
    return this.getField('Notes') || '';
  }

  set notes(value: string) {
    this.setField('Notes', value);
  }

  /**
   * 克隆条目
   * @param entry
   * @returns
   */
  private cloneTo(entry: KdbxEntry): KdbxEntry {
    entry.uuid = this.uuid;
    entry.creationTime = this.creationTime;
    entry.lastModifiedTime = this.lastModifiedTime;
    entry.lastAccessTime = this.lastAccessTime;
    entry.expiryTime = this.expiryTime;
    entry.expires = this.expires;
    entry.usageCount = this.usageCount;
    entry.parentGroup = this.parentGroup;
    entry.previousVersionUUID = this.previousVersionUUID;
    entry.icon = this.icon;

    entry.favorite = this.favorite;
    entry.tags = [...this.tags];
    entry.fields = [...this.fields];
    entry.attachments = [...this.attachments];
    entry.customData = [...this.customData];
    entry.history = this.history.map(e => e.clone());

    return entry;
  }

  /**
   * 创建条目的副本
   * @returns 新条目副本
   */
  clone(): KdbxEntry {
    return this.cloneTo(new KdbxEntry(this.uuid, this.parentGroup));
  }

  /**
   * 比较两个条目是否相同
   * @param other 另一个条目
   * @returns 是否相同
   */
  equals(other: KdbxEntry): boolean {
    if (this.uuid !== other.uuid) {
      return false;
    }
    if (this.fields.length !== other.fields.length) {
      return false;
    }
    if (this.attachments.length !== other.attachments.length) {
      return false;
    }

    // 比较字段
    for (const field of this.fields) {
      const otherField = other.fields.find(f => f.name === field.name);
      if (!otherField || otherField.value !== field.value) {
        return false;
      }
    }

    // 比较附件
    for (const attachment of this.attachments) {
      const otherAttachment = other.attachments.find(a => a.name === attachment.name);
      if (!otherAttachment || otherAttachment.data.length !== attachment.data.length) {
        return false;
      }
    }

    return true;
  }

  /**
   * 验证条目完整性
   * @returns 验证结果
   */
  validate(): ValidateResult {
    const errors: string[] = [];

    if (!this.title) {
      errors.push('标题不能为空');
    }

    if (!this.username && !this.password) {
      errors.push('用户名和密码不能同时为空');
    }

    return {
      valid: errors.length === 0,
      errors
    };
  }

  /**
   * 获取条目摘要信息
   * @returns 摘要信息
   */
  getSummary(): KdbxEntrySummary {
    return {
      title: this.title,
      username: this.username,
      hasPassword: !!this.password,
      hasUrl: !!this.url,
      hasNotes: !!this.notes,
      attachmentCount: this.attachments.length
    };
  }

  /**
   * 生成随机密码
   * @param options 密码生成选项
   * @returns 生成的密码
   */
  generatePassword(options?: GeneratePasswordOptions): string {
    if (!options) {
      options = {};
    }
    const length = options.length || 16,
      useUpperCase = options.useUpperCase || true,
      useLowerCase = options.useLowerCase || true,
      useDigits = options.useDigits || true,
      useSpecial = options.useSpecial || true,
      excludeLookAlike = options.excludeLookAlike || false;

    let chars = '';
    if (useLowerCase) {
      chars += 'abcdefghijklmnopqrstuvwxyz';
    }
    if (useUpperCase) {
      chars += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    }
    if (useDigits) {
      chars += '0123456789';
    }
    if (useSpecial) {
      chars += '!@#$%^&*()_+-=[]{}|;:,.<>?';
    }
    if (excludeLookAlike) {
      chars = chars.replace(/[Il1O0]/g, '');
    }

    let password = '';
    const randomValues = new Uint32Array(length);
    KdbxUtils.fillRandom(randomValues);

    for (let i = 0; i < length; i++) {
      password += chars[randomValues[i] % chars.length];
    }

    this.password = password;
    return password;
  }

  /**
   * 检查密码强度
   * @returns 密码强度评分（0-100）和建议
   */
  checkPasswordStrength(): PasswordStrength {
    const password = this.password;
    const suggestions: string[] = [];
    let score = 0;

    if (!password) {
      return { score: 0, suggestions: ['请设置密码'] };
    }

    // 基础长度得分
    score += Math.min(password.length * 4, 40);

    // 字符类型多样性得分
    if (/[A-Z]/.test(password)) {
      score += 10;
    }
    if (/[a-z]/.test(password)) {
      score += 10;
    }
    if (/[0-9]/.test(password)) {
      score += 10;
    }
    if (/[^A-Za-z0-9]/.test(password)) {
      score += 10;
    }

    // 复杂性得分
    const uniqueChars = new Set(password).size;
    score += Math.min(uniqueChars * 2, 20);

    // 生成建议
    if (password.length < 12) {
      suggestions.push('建议密码长度至少12位');
    }
    if (!/[A-Z]/.test(password)) {
      suggestions.push('建议包含大写字母');
    }
    if (!/[a-z]/.test(password)) {
      suggestions.push('建议包含小写字母');
    }
    if (!/[0-9]/.test(password)) {
      suggestions.push('建议包含数字');
    }
    if (!/[^A-Za-z0-9]/.test(password)) {
      suggestions.push('建议包含特殊字符');
    }

    return {
      score: Math.min(score, 100),
      suggestions
    };
  }

  /**
   * 搜索字段
   * @param query 搜索关键词
   * @param options 搜索选项
   * @returns 匹配的字段列表
   */
  searchFields(query: string, options?: SearchFieldOptions): Field[] {
    if (!query) {
      return [];
    }

    const caseSensitive = options?.caseSensitive || false,
      includeProtected = options?.includeProtected || false,
      fieldNames = options?.fieldNames || undefined;

    const searchQuery = caseSensitive ? query : query.toLowerCase();

    return this.fields.filter(field => {
      // 如果指定了字段名，只搜索指定字段
      if (fieldNames && !fieldNames.includes(field.name)) {
        return false;
      }

      // 如果字段受保护且不包含受保护字段，跳过
      if (field.protected && !includeProtected) {
        return false;
      }

      const value = typeof field.value === 'string' ? field.value : '';
      const searchValue = caseSensitive ? value : value.toLowerCase();

      return searchValue.includes(searchQuery);
    });
  }

  /**
   * 导出条目数据
   * @param format 导出格式
   * @returns 导出的数据
   */
  export(format: 'json' | 'csv' | 'xml' = 'json'): string {
    switch (format) {
      case 'json':
        return JSON.stringify({
          title: this.title,
          username: this.username,
          url: this.url,
          notes: this.notes,
          tags: this.tags,
          customFields: this.fields.filter(f =>
          !['Title', 'UserName', 'Password', 'URL', 'Notes'].includes(f.name)
          ),
          creationTime: this.creationTime,
          lastModifiedTime: this.lastModifiedTime
        }, null, 2);

      case 'csv':
        return `"${this.title}","${this.username}","${this.url}","${this.notes}","${this.tags.join(';')}"`;

      case 'xml':
        return `<?xml version="1.0" encoding="UTF-8"?>
<entry>
  <title>${this.title}</title>
  <username>${this.username}</username>
  <url>${this.url}</url>
  <notes>${this.notes}</notes>
  <tags>${this.tags.join(';')}</tags>
  <created>${this.creationTime.toISOString()}</created>
  <modified>${this.lastModifiedTime.toISOString()}</modified>
</entry>`;

      default:
        throw new Error(`Unsupported export format: ${format}`);
    }
  }
}
