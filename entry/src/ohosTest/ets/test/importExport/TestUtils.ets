import { Kdbx, KdbxCredentials, KdbxGroup, KdbxEntry, ProtectedValue } from 'kdbxweb';
import { FileContentInfo, FileType, FileInfo, FileInfoImpl } from '../../../../main/ets/storage/IFileStorage';
import util from '@ohos.util';

/**
 * 测试工具类
 */
export class TestUtils {
  private static emptyFileInfo: FileInfo = new FileInfoImpl();

  /**
   * 创建测试数据库
   */
  static async createTestDatabase(dbName: string = 'Test Database'): Promise<Kdbx> {
    const credentials = new KdbxCredentials(null);
    return Kdbx.create(credentials, dbName);
  }

  /**
   * 创建测试条目
   * 使用 db.createEntry() 方法确保条目正确添加到数据库
   */
  static createTestEntry(
    db: Kdbx,
    group: KdbxGroup,
    title: string,
    username?: string,
    password?: string,
    url?: string,
    notes?: string
  ): KdbxEntry {
    // 使用 db.createEntry() 方法，这会正确处理条目与分组的关系
    const entry = db.createEntry(group);
    entry.fields.set('Title', title);
    if (username !== undefined) {
      entry.fields.set('UserName', username);
    }
    if (password !== undefined) {
      entry.fields.set('Password', ProtectedValue.fromString(password));
    }
    if (url !== undefined) {
      entry.fields.set('URL', url);
    }
    if (notes !== undefined) {
      entry.fields.set('Notes', notes);
    }
    return entry;
  }

  /**
   * 从字符串创建文件内容信息
   * @param content 文件内容字符串
   * @param fileName 文件名
   * @returns FileContentInfo 对象
   */
  static createFileContentInfoFromString(content: string, fileName: string): FileContentInfo {
    const encoder = util.TextEncoder.create('utf-8');
    const encoded: Uint8Array = encoder.encodeInto(content);
    // 确保 encoded 和 buffer 都有有效值
    const buffer: ArrayBuffer = encoded !== undefined && encoded !== null ? encoded.buffer as ArrayBuffer : new ArrayBuffer(0);

    // 使用 FileInfoImpl 创建 FileInfo 实例
    const fileInfo = new FileInfoImpl();
    fileInfo.name = fileName;
    fileInfo.size = buffer.byteLength;
    fileInfo.modifiedTime = Date.now();
    fileInfo.path = fileName;
    fileInfo.type = FileType.FILE;
    fileInfo.childrenCount = 0;

    return new FileContentInfo(fileInfo, buffer);
  }

  /**
   * 创建文件内容信息（兼容旧方法名）
   */
  static createFileContent(content: string, fileName: string = 'test.file'): FileContentInfo {
    return TestUtils.createFileContentInfoFromString(content, fileName);
  }

  /**
   * 解码 ArrayBuffer 为字符串
   */
  static decodeBuffer(buffer: ArrayBuffer): string {
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(new Uint8Array(buffer));
  }

  /**
   * 创建测试分组
   * 使用 db.createGroup() 方法确保分组正确添加到数据库
   */
  static createTestGroup(db: Kdbx, parent: KdbxGroup, name: string): KdbxGroup {
    return db.createGroup(parent, name);
  }

  /**
   * 收集分组下所有条目
   */
  static collectAllEntries(group: KdbxGroup): KdbxEntry[] {
    const entries: KdbxEntry[] = [];

    // 添加当前分组的条目
    for (const entry of group.entries) {
      entries.push(entry);
    }

    // 递归处理子分组
    for (const subGroup of group.groups) {
      const subEntries = TestUtils.collectAllEntries(subGroup);
      for (const entry of subEntries) {
        entries.push(entry);
      }
    }

    return entries;
  }

  /**
   * 根据标题查找条目
   */
  static findEntryByTitle(group: KdbxGroup, title: string): KdbxEntry | undefined {
    const entries = TestUtils.collectAllEntries(group);
    for (const entry of entries) {
      const entryTitle = entry.fields.get('Title');
      if (entryTitle === title) {
        return entry;
      }
    }
    return undefined;
  }

  /**
   * 获取条目的所有字段
   */
  static getEntryFields(entry: KdbxEntry): Map<string, string> {
    const fields = new Map<string, string>();
    entry.fields.forEach((value, key) => {
      if (typeof value === 'string') {
        fields.set(key, value);
      } else if (value && typeof value.getText === 'function') {
        fields.set(key, value.getText());
      }
    });
    return fields;
  }

  /**
   * 获取字段值字符串（处理 ProtectedValue）
   */
  static getFieldValue(entry: KdbxEntry, fieldName: string): string {
    const value = entry.fields.get(fieldName);
    if (!value) {
      return '';
    }
    if (typeof value === 'string') {
      return value;
    }
    // ProtectedValue 类型
    if (typeof value.getText === 'function') {
      return value.getText();
    }
    return '';
  }

  /**
   * 验证条目字段值
   */
  static verifyEntryField(entry: KdbxEntry, fieldName: string, expectedValue: string): boolean {
    const value = TestUtils.getFieldValue(entry, fieldName);
    return value === expectedValue;
  }

  /**
   * 打印条目信息（调试用）
   */
  static printEntry(entry: KdbxEntry): void {
    console.log(`Entry: ${entry.fields.get('Title')}`);
    entry.fields.forEach((value, key) => {
      if (key !== 'Title') {
        const strValue = typeof value === 'string' ? value : (value && typeof value.getText === 'function' ? value.getText() : String(value));
        console.log(`  ${key}: ${strValue}`);
      }
    });
  }

  /**
   * 统计分组及其子分组中的所有条目数量
   */
  static countAllEntries(group: KdbxGroup): number {
    let count = group.entries.length;
    for (const subGroup of group.groups) {
      count += TestUtils.countAllEntries(subGroup);
    }
    return count;
  }

  /**
   * 统计分组及其子分组中的所有分组数量
   */
  static countAllGroups(group: KdbxGroup): number {
    let count = group.groups.length;
    for (const subGroup of group.groups) {
      count += TestUtils.countAllGroups(subGroup);
    }
    return count;
  }

  /**
   * 验证两个条目的基本字段是否相等
   */
  static assertEntryEquals(actual: KdbxEntry, expected: KdbxEntry): void {
    const actualTitle = TestUtils.getFieldValue(actual, 'Title');
    const expectedTitle = TestUtils.getFieldValue(expected, 'Title');
    if (actualTitle !== expectedTitle) {
      throw new Error(`Title mismatch: expected "${expectedTitle}", got "${actualTitle}"`);
    }

    const actualUsername = TestUtils.getFieldValue(actual, 'UserName');
    const expectedUsername = TestUtils.getFieldValue(expected, 'UserName');
    if (actualUsername !== expectedUsername) {
      throw new Error(`UserName mismatch for "${expectedTitle}": expected "${expectedUsername}", got "${actualUsername}"`);
    }

    const actualPassword = TestUtils.getFieldValue(actual, 'Password');
    const expectedPassword = TestUtils.getFieldValue(expected, 'Password');
    if (actualPassword !== expectedPassword) {
      throw new Error(`Password mismatch for "${expectedTitle}": expected "${expectedPassword}", got "${actualPassword}"`);
    }
  }
}
