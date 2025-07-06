import { Kdbx, KdbxEntryField, KdbxGroup, ProtectedValue } from 'kdbxweb';

export default class KdbxUtils {
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
}