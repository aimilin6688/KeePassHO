import { Kdbx, KdbxEntry, KdbxEntryField, ProtectedValue } from 'kdbxweb';

export default class KdbxUtils {
  public static readonly FIELD_USERNAME = 'UserName';
  public static readonly FIELD_PASSWORD = 'Password';
  public static readonly FIELD_URL = 'URL';
  public static readonly FIELD_NOTES = 'Notes';
  public static readonly FIELD_TITLE = 'Title';


  /**
   * 获取字段值
   * @param fields 字段
   * @param key 字段key
   */
  public static getFieldValueString(fields: Map<string, KdbxEntryField>, key: string): string {
    if (!fields || !fields.has(key)) {
      return '';
    }
    let value = fields.get(key);
    if (!value) {
      return '';
    }
    if (value instanceof String) {
      return value as string;
    }

    if (value instanceof ProtectedValue) {
      return value.getText();
    }

    return value.toString();
  }

  /**
   * 获取条目
   * @param kdbx 数据库
   * @param groupId 组id
   * @param entryId 条目id
   */
  public static getEntry(kdbx: Kdbx, groupId: string, entryId: string): KdbxEntry | null {
    const group = kdbx.getGroup(groupId);
    if (!group) {
      return null;
    }
    for (const entry of group.entries) {
      if (entry.uuid.id === entryId) {
        return entry;
      }
    }
    return null;
  }
}