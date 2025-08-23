import { Kdbx, KdbxEntry, KdbxGroup } from 'kdbxweb';
import util from '@ohos.util';
import KdbxUtils from '../../common/utils/KdbxUtils';

export enum CsvTitle {
  Group = "Group",
  Title = "Title",
  Username = "Username",
  Password = "Password",
  URL = "URL",
  Notes = "Notes",
  TOTP = "TOTP",
  Icon = "Icon",
  Last_Modified = "Last Modified",
  Created = "Created"
}

export class KdbxCsvService {
  /**
   * 导出数据库到csv文件格式
   * @param database
   * @returns
   */
  public static async export(database: Kdbx): Promise<ArrayBuffer> {
    // CSV内容头部
    let csvContent = '';

    // 添加标题行
    const titles = Object.values(CsvTitle).join(',');
    csvContent += titles + '\n';

    // 遍历所有条目
    for (const entry of database.getDefaultGroup().allEntries()) {
      const groupPath = KdbxCsvService.getGroupPath(entry.parentGroup);
      const title = KdbxCsvService.getFieldValue(entry, 'Title');
      const username = KdbxCsvService.getFieldValue(entry, 'UserName');
      const password = KdbxCsvService.getFieldValue(entry, 'Password');
      const url = KdbxCsvService.getFieldValue(entry, 'URL');
      const notes = KdbxCsvService.getFieldValue(entry, 'Notes');
      const totp = KdbxCsvService.getTotpFieldValue(entry); // TOTP通常不直接存储在字段中
      const icon = entry.icon ? entry.icon.toString() : '0';
      const lastModified = entry.times.lastModTime?.toISOString() || '';
      const created = entry.times.creationTime?.toISOString() || '';

      // 转义并格式化CSV行
      const row = [
        KdbxCsvService.escapeCsvField(groupPath),
        KdbxCsvService.escapeCsvField(title),
        KdbxCsvService.escapeCsvField(username),
        KdbxCsvService.escapeCsvField(password),
        KdbxCsvService.escapeCsvField(url),
        KdbxCsvService.escapeCsvField(notes),
        KdbxCsvService.escapeCsvField(totp),
        KdbxCsvService.escapeCsvField(icon),
        KdbxCsvService.escapeCsvField(lastModified),
        KdbxCsvService.escapeCsvField(created)
      ].join(',');

      csvContent += row + '\n';
    }

    // 将字符串转换为ArrayBuffer
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(csvContent).buffer;
  }

  /**
   * 获取TOTP字段值
   * @param entry 实体
   * @returns 结果
   */
  private static getTotpFieldValue(entry: KdbxEntry) {
    for (let field of entry.fields) {
      const value = KdbxUtils.getValueString(field[1]);
      if (KdbxUtils.isTotpUrl(value)) {
        return value;
      }
    }
    return '';
  }

  /**
   * 获取分组路径
   * @param group 分组
   * @returns 分组路径字符串
   */
  private static getGroupPath(group: KdbxGroup | undefined): string {
    if (!group) {
      return '';
    }

    const path: string[] = [];
    let currentGroup: KdbxGroup | undefined = group;

    while (currentGroup && currentGroup.name) {
      path.unshift(currentGroup.name);
      currentGroup = currentGroup.parentGroup;
    }

    return path.join('/');
  }

  /**
   * 获取字段值
   * @param entry 条目
   * @param fieldName 字段名
   * @returns 字段值字符串
   */
  private static getFieldValue(entry: KdbxEntry, fieldName: string): string {
    const field = entry.fields.get(fieldName);
    if (!field) {
      return '';
    }

    if (typeof field === 'string') {
      return field;
    } else {
      // ProtectedValue类型
      return field.getText();
    }
  }

  /**
   * 转义CSV字段
   * @param field 字段值
   * @returns 转义后的字段值
   */
  private static escapeCsvField(field: string): string {
    // 如果字段包含逗号、双引号或换行符，则需要用双引号包围，并将内部双引号转义为两个双引号
    if (field.includes(',') || field.includes('"') || field.includes('\n')) {
      return '"' + field.replace(/"/g, '""') + '"';
    }
    return field;
  }
}