import { Kdbx, KdbxEntry, KdbxGroup, ByteUtils } from 'kdbxweb';
import { IExportHandler } from '../../interfaces/IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { KdbxUtils } from '../../../../common/utils';
import util from '@ohos.util';

/**
 * CSV 标题枚举
 */
enum CsvTitle {
  Group = "Group",
  Title = "Title",
  Username = "UserName",
  Password = "Password",
  URL = "URL",
  Notes = "Notes",
  TOTP = "TOTP",
  Icon = "Icon",
  Last_Modified = "Last Modified",
  Created = "Created"
}

/**
 * CSV 导出处理器
 */
export class CsvExportHandler implements IExportHandler {
  readonly supportedExtensions = ['.csv'];
  readonly formatName = 'CSV';
  readonly formatId = 'CSV';
  readonly defaultFileName = 'export.csv';

  canHandle(formatId: string): boolean {
    return this.formatId === formatId;
  }

  async export(database: Kdbx): Promise<ArrayBuffer> {
    try {
      const rootGroup = database.getDefaultGroup();
      const entries = rootGroup.allEntries();

      if (entries.length === 0) {
        throw new ExportError(ImportExportErrorCode.DATABASE_EMPTY, '数据库为空，没有可导出的条目');
      }

      let csvContent = '';

      // 添加标题行
      const titles = Object.values(CsvTitle).join(',');
      csvContent += titles + '\n';

      // 遍历所有条目
      for (const entry of entries) {
        const groupPath = KdbxUtils.getGroupPath(entry.parentGroup);
        const row = this.createCsvRow(entry, groupPath);
        csvContent += row + '\n';
      }

      // 转换为 ArrayBuffer
      const encoder = new util.TextEncoder();
      return encoder.encodeInto(csvContent).buffer;
    } catch (error) {
      if (error instanceof ExportError) {
        throw error;
      }
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        `CSV 导出失败: ${error instanceof Error ? error.message : '未知错误'}`
      );
    }
  }

  private createCsvRow(entry: KdbxEntry, groupPath: string): string {
    const title = this.getFieldValue(entry, 'Title');
    const username = this.getFieldValue(entry, 'UserName');
    const password = this.getFieldValue(entry, 'Password');
    const url = this.getFieldValue(entry, 'URL');
    const notes = this.getFieldValue(entry, 'Notes');
    const totp = this.getTotpFieldValue(entry);
    const icon = entry.icon !== undefined ? entry.icon.toString() : '0';
    const lastModified = entry.times.lastModTime?.toISOString() || '';
    const created = entry.times.creationTime?.toISOString() || '';

    const row = [
      this.escapeCsvField(groupPath),
      this.escapeCsvField(title),
      this.escapeCsvField(username),
      this.escapeCsvField(password),
      this.escapeCsvField(url),
      this.escapeCsvField(notes),
      this.escapeCsvField(totp),
      this.escapeCsvField(icon),
      this.escapeCsvField(lastModified),
      this.escapeCsvField(created)
    ];

    return row.join(',');
  }

  private getFieldValue(entry: KdbxEntry, fieldName: string): string {
    const field = entry.fields.get(fieldName);
    if (!field) {
      return '';
    }

    if (typeof field === 'string') {
      return field;
    } else {
      // ProtectedValue 类型
      return field.getText();
    }
  }

  private getTotpFieldValue(entry: KdbxEntry): string {
    for (const field of entry.fields) {
      const value = KdbxUtils.getValueString(field[1]);
      if (KdbxUtils.isTotpUrl(value)) {
        return value;
      }
    }
    return '';
  }

  private escapeCsvField(field: string): string {
    if (!field) {
      return '';
    }

    // 如果字段包含逗号、双引号或换行符，需要用双引号包围
    if (field.includes(',') || field.includes('"') || field.includes('\n')) {
      return '"' + field.replace(/"/g, '""') + '"';
    }

    return field;
  }
}
