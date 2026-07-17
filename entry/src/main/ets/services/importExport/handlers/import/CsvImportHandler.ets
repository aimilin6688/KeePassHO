import { KdbxGroup, KdbxEntry, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { FileService } from '../../../FileService';
import { ResourceManager } from '../../../../common/utils';
import hilog from '@ohos.hilog';

const TAG = 'CsvImportHandler';
const DOMAIN = 0xFF00;

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
 * 解析条目结果
 */
interface ParseEntryResult {
  entry: KdbxEntry;
  parentGroup: KdbxGroup;
}

/**
 * CSV 导入处理器
 */
export class CsvImportHandler implements IImportHandler {
  readonly supportedExtensions = ['.csv'];
  readonly formatName = 'CSV';
  readonly formatId = 'CSV';

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    const content = ByteUtils.bytesToString(fileContent.content);
    const lines = content.split('\n');

    if (lines.length === 0 || (lines.length === 1 && lines[0].trim() === '')) {
      throw new ImportError(ImportExportErrorCode.FILE_EMPTY, ResourceManager.getString($r('app.string.import_export_file_empty')));
    }

    const headerMap = this.parseHeader(lines[0]);
    const rootGroup = new KdbxGroup();
    const groupCache = new Map<string, KdbxGroup>();

    // 获取字段保护设置
    const fieldProtection = this.createFieldProtection();

    for (let i = 1; i < lines.length; i++) {
      if (!lines[i].trim()) continue;

      const line = this.parseCsvLine(lines[i]);
      const result = this.parseEntry(line, headerMap, rootGroup, groupCache, fieldProtection);
      // 将条目添加到其所属的分组
      result.parentGroup.entries.push(result.entry);
    }

    return rootGroup;
  }

  private parseHeader(headerLine: string): Map<string, number> {
    const headers = headerLine.split(',');
    const map = new Map<string, number>();

    for (let i = 0; i < headers.length; i++) {
      const header = headers[i].trim();
      map.set(header, i);
    }

    // 验证必须的标题
    const requiredHeaders = [CsvTitle.Title];
    for (const required of requiredHeaders) {
      if (!map.has(required)) {
        hilog.error(DOMAIN, TAG, 'Missing required column: %{public}s', required);
        throw new ImportError(
          ImportExportErrorCode.INVALID_CSV_HEADER,
          ResourceManager.getString($r('app.string.import_export_missing_required_column'), required)
        );
      }
    }

    return map;
  }

  private parseCsvLine(line: string): string[] {
    const result: string[] = [];
    let current = '';
    let inQuotes = false;

    for (let i = 0; i < line.length; i++) {
      const char = line[i];

      if (char === '"') {
        if (inQuotes && line[i + 1] === '"') {
          current += '"';
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char === ',' && !inQuotes) {
        result.push(current);
        current = '';
      } else {
        current += char;
      }
    }
    result.push(current);

    return result;
  }

  private createFieldProtection(): Map<string, boolean> {
    const db = FileService.getDatabase();
    const protection = db?.meta?.memoryProtection;

    return new Map<string, boolean>([
      [CsvTitle.Title, protection?.title || false],
      [CsvTitle.Username, protection?.userName || false],
      [CsvTitle.Password, protection?.password || true],
      [CsvTitle.URL, protection?.url || false],
      [CsvTitle.Notes, protection?.notes || false],
      [CsvTitle.TOTP, true]
    ]);
  }

  private parseEntry(
    fields: string[],
    headerMap: Map<string, number>,
    rootGroup: KdbxGroup,
    groupCache: Map<string, KdbxGroup>,
    fieldProtection: Map<string, boolean>
  ): ParseEntryResult {
    // 获取或创建分组
    const groupIndex = headerMap.get(CsvTitle.Group);
    let parentGroup = rootGroup;

    if (groupIndex !== undefined && fields[groupIndex]) {
      parentGroup = this.getOrCreateGroup(rootGroup, fields[groupIndex], groupCache);
    }

    const db = FileService.getDatabase();
    const entry = KdbxEntry.create(db.meta, parentGroup);

    // 设置各字段
    this.setField(entry, headerMap, fields, CsvTitle.Title, false);
    this.setField(entry, headerMap, fields, CsvTitle.Username, fieldProtection.get(CsvTitle.Username));
    this.setField(entry, headerMap, fields, CsvTitle.Password, true);
    this.setField(entry, headerMap, fields, CsvTitle.URL, fieldProtection.get(CsvTitle.URL));
    this.setField(entry, headerMap, fields, CsvTitle.Notes, fieldProtection.get(CsvTitle.Notes));
    this.setField(entry, headerMap, fields, CsvTitle.TOTP, true);

    // 设置图标
    const iconIndex = headerMap.get(CsvTitle.Icon);
    if (iconIndex !== undefined && fields[iconIndex]) {
      const icon = parseInt(fields[iconIndex]);
      if (!isNaN(icon)) {
        entry.icon = icon;
      }
    }

    const result: ParseEntryResult = { entry: entry, parentGroup: parentGroup };
    return result;
  }

  private getOrCreateGroup(
    rootGroup: KdbxGroup,
    groupPath: string,
    cache: Map<string, KdbxGroup>
  ): KdbxGroup {
    if (!groupPath || groupPath === '') {
      return rootGroup;
    }

    if (cache.has(groupPath)) {
      return cache.get(groupPath)!;
    }

    let currentGroup = rootGroup;
    const parts = groupPath.split('/');

    for (const part of parts) {
      if (!part) continue;

      let found = currentGroup.groups.find(g => g.name === part);

      if (!found) {
        found = KdbxGroup.create(part, currentGroup);
        currentGroup.groups.push(found);
      }

      currentGroup = found;
    }

    cache.set(groupPath, currentGroup);
    return currentGroup;
  }

  private setField(
    entry: KdbxEntry,
    headerMap: Map<string, number>,
    fields: string[],
    fieldName: string,
    isProtected: boolean = false
  ): void {
    const idx = headerMap.get(fieldName);
    if (idx !== undefined && idx < fields.length && fields[idx]) {
      entry.setField(fieldName, fields[idx], isProtected);
    }
  }
}
