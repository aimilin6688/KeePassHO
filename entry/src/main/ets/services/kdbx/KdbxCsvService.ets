import { ByteUtils, Kdbx, KdbxEntry, KdbxGroup } from 'kdbxweb';
import util from '@ohos.util';
import KdbxUtils from '../../common/utils/KdbxUtils';
import { FileContentInfo } from './interfaces';
import { ErrorCodes, KeePassHoError } from '../error/KeepassHoError';
import { FileService } from '../FileService';

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
   * 导入csv文件
   * @param csvFile
   * @returns
   */
  public static async import(csvFile: FileContentInfo): Promise<KdbxGroup> {
    return new Promise<KdbxGroup>(async (resolve, reject) => {
      try {
        return resolve(KdbxCsvService.parseLines(csvFile.content));
      } catch (e) {
        return reject(e);
      }
    });
  }

  /**
   * 解析CSV行
   * @param csvContent
   * @returns
   */
  private static parseLines(csvContent: ArrayBuffer): KdbxGroup {
    // 获取CSV行
    const csvLines: string[] = ByteUtils.bytesToString(csvContent).split("\n");
    if (csvLines.length === 0) {
      throw new KeePassHoError(ErrorCodes.FILE_EMPTY);
    }
    const rootGroup = new KdbxGroup();
    let currentGroup: KdbxGroup = rootGroup;
    let groupIndex: number | undefined = undefined;

    const heads = KdbxCsvService.checkHeader(csvLines[0]);
    const fieldProtection = KdbxCsvService.createFieldProtection();
    for (let i = 1; i < csvLines.length; i++) {
      const line = csvLines[i].split(',');
      // 包含分组信息
      currentGroup = rootGroup;
      groupIndex = heads.get(CsvTitle.Group);
      if (groupIndex != undefined) {
        currentGroup = KdbxCsvService.getGroupByPath(rootGroup, line[groupIndex]);
      }
      let entry = KdbxCsvService.parseEntry(heads, line, currentGroup, fieldProtection);
      entry.parentGroup = currentGroup;
      currentGroup.entries.push(entry);
    }
    return rootGroup;
  }

  /**
   * 设值字段保护
   * @returns
   */
  private static createFieldProtection(): Map<string, boolean> {
    const fieldProtection = FileService.getDatabase().meta.memoryProtection;
    return new Map<string, boolean>([
      [CsvTitle.Title, fieldProtection.title || false],
      [CsvTitle.Username, fieldProtection.userName || false],
      [CsvTitle.Password, fieldProtection.password || false],
      [CsvTitle.URL, fieldProtection.url || false],
      [CsvTitle.Notes, fieldProtection.notes || false],
      [CsvTitle.TOTP, false],
      [CsvTitle.Icon, false],
      [CsvTitle.Last_Modified, false],
      [CsvTitle.Created, false]
    ]);
  }

  /**
   * 解析CSV行
   * @param heads
   * @param line
   * @returns
   */
  private static parseEntry(heads: Map<string, number>, line: string[], parentGroup: KdbxGroup, fieldProtection: Map<string, boolean>): KdbxEntry {
    const entry = KdbxEntry.create(FileService.getDatabase().meta, parentGroup);
    for (let item of heads) {
      const fieldName = item[0];
      const fieldValue = line[item[1]];
      if (!fieldValue || fieldValue.trim() === '') {
        continue;
      }
      if (fieldName === CsvTitle.Group) {
        continue;
      }
      if (fieldName === CsvTitle.Icon) {
        entry.icon = parseInt(fieldValue);
        continue;
      }
      if (fieldName === CsvTitle.Created) {
        entry.times.creationTime = new Date(fieldValue);
        continue;
      }
      if (fieldName === CsvTitle.Last_Modified) {
        entry.times.lastModTime = new Date(fieldValue);
        continue;
      }
      entry.setField(fieldName, fieldValue, fieldProtection.get(fieldName));
    }
    return entry;
  }

  /**
   * 获取分组
   * @param rootGroup 根分组
   * @param groupPath 分组路径
   * @returns 结果
   */
  private static getGroupByPath(rootGroup: KdbxGroup, groupPath: string): KdbxGroup {
    if (!groupPath || groupPath === '') {
      return rootGroup;
    }
    let currentGroup: KdbxGroup = rootGroup;
    const groups = groupPath.split("/");
    for (let groupName of groups) {
      if (!groupName) {
        continue;
      }
      let find = false;
      for (let child of currentGroup.groups) {
        if (child.name === groupName) {
          currentGroup = child;
          find = true;
          break;
        }
      }
      // 未查到创建新分组
      if (false === find) {
        const subGroup = KdbxGroup.create(groupName, currentGroup);
        currentGroup.groups.push(subGroup);
        currentGroup = subGroup;
      }
    }
    return currentGroup;
  }

  /**
   * 检查CSV标题行
   * @param csvHeader
   * @returns
   */
  private static checkHeader(csvHeader: string): Map<string, number> {
    const result = new Map<string, number>();
    const headerFields = csvHeader.split(',');
    const fields = Object.values(CsvTitle) as string[];
    for (let i = 0; i < headerFields.length; i++) {
      const field = headerFields[i].trim();
      if (!fields.includes(field)) {
        throw new KeePassHoError(ErrorCodes.INVALID_CSV_HEADER, `Invalid CSV header ${field}`);
      }
      result.set(field, i);
    }
    return result;
  }

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
      const groupPath = KdbxUtils.getGroupPath(entry.parentGroup);
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