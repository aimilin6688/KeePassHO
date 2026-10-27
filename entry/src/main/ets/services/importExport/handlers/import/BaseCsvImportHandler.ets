import { KdbxGroup, KdbxEntry, ByteUtils } from 'kdbxweb';
import { url } from '@kit.ArkTS';
import hilog from '@ohos.hilog';
import { ISniffableImport } from '../../csvimport/ISniffableImport';
import { CsvParser } from '../../csvimport/CsvParser';
import { CsvColumnMapping } from '../../csvimport/CsvColumnMappingEngine';
import { ColumnMappingItem } from '../../csvimport/CsvMappingModels';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { FileService } from '../../../FileService';
import { ResourceManager } from '../../../../common/utils';

const TAG = 'BaseCsvImportHandler';
const DOMAIN = 0xFF00;

/**
 * 字段保护配置（来自数据库 memoryProtection 设置）
 */
interface CsvFieldProtection {
  title: boolean;
  username: boolean;
  url: boolean;
  notes: boolean;
}

/**
 * CSV 导入处理器基类
 * 实现通用导入流程：解析 → 构建列映射 → 分组解析 → 条目字段填充 → 标题兜底
 * 具体格式子类提供 formatId/formatName、嗅探逻辑与列映射构建策略
 */
export abstract class BaseCsvImportHandler implements ISniffableImport {
  /** 秒级时间戳上限（KeePassXC 语义：≤ INT32_MAX 视为秒） */
  protected static readonly INT32_MAX: number = 2147483647;
  /** 微秒级时间戳下限（Firefox 导出时间列为微秒） */
  protected static readonly MICROSECOND_THRESHOLD: number = 100000000000000;
  /** 嗅探置信度阈值 */
  protected static readonly SNIFF_CONFIDENCE: number = 90;

  readonly supportedExtensions: string[] = ['.csv'];
  readonly formatId: string;
  /** 格式显示名（IImportHandler.formatName） */
  abstract readonly formatName: string;

  protected constructor(formatId: string) {
    this.formatId = formatId;
  }

  abstract sniff(headerRow: string[], sampleRows: string[][]): number;

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    const content = ByteUtils.bytesToString(fileContent.content);
    return this.importText(content);
  }

  /**
   * 解析 CSV 文本并导入
   */
  protected importText(content: string): KdbxGroup {
    const parseResult = new CsvParser().parse(content);
    return this.importRows(parseResult.rows);
  }

  /**
   * 按已解析的行数据导入（表头行为第一行）
   * 供格式族调度器在嗅探分发后复用解析结果
   */
  importRows(rows: string[][]): KdbxGroup {
    if (rows.length === 0) {
      throw new ImportError(
        ImportExportErrorCode.FILE_EMPTY,
        ResourceManager.getString($r('app.string.import_export_file_empty'))
      );
    }

    const mapping = this.buildColumnMapping(rows[0]);
    return this.importRowsWithMapping(rows, mapping, [], '');
  }

  /**
   * 按显式列映射 + 自定义字段映射导入（列映射向导确认后的路径）
   * @param rows 已解析行（表头为第一行）
   * @param mapping 标准目标字段列映射
   * @param customItems 自定义字段映射项（源列 → 自定义字段名，空值跳过）
   * @param importTargetGroupName 导入目标分组名（空 = 根分组；非空时所有条目收入该分组）
   */
  importRowsWithMapping(
    rows: string[][],
    mapping: CsvColumnMapping[],
    customItems: ColumnMappingItem[],
    importTargetGroupName: string
  ): KdbxGroup {
    if (rows.length === 0) {
      throw new ImportError(
        ImportExportErrorCode.FILE_EMPTY,
        ResourceManager.getString($r('app.string.import_export_file_empty'))
      );
    }

    const db = FileService.getDatabase();
    if (!db) {
      hilog.error(DOMAIN, TAG, 'database is not loaded');
      throw new ImportError(ImportExportErrorCode.PARSE_ERROR, 'database is not loaded');
    }

    const protection = this.getFieldProtection();
    const rootGroup = new KdbxGroup();
    const groupCache = new Map<string, KdbxGroup>();
    let containerGroup = rootGroup;
    if (importTargetGroupName.trim() !== '') {
      containerGroup = KdbxGroup.create(importTargetGroupName.trim(), rootGroup);
      rootGroup.groups.push(containerGroup);
    }
    let entryCounter = 0;

    for (let i = 1; i < rows.length; i++) {
      const row = rows[i];
      const parentGroup = this.resolveTargetGroup(containerGroup, mapping, row, groupCache);
      const entry = KdbxEntry.create(db.meta, parentGroup);

      let titleValue = '';
      let urlValue = '';
      let usernameValue = '';
      for (const item of mapping) {
        if (item.target === CsvTargetField.GROUP) {
          continue;
        }
        if (item.columnIndex >= row.length) {
          continue;
        }
        const value = row[item.columnIndex];
        if (item.target === CsvTargetField.TITLE) {
          titleValue = value;
        } else if (item.target === CsvTargetField.URL) {
          urlValue = value;
        } else if (item.target === CsvTargetField.USERNAME) {
          usernameValue = value;
        }
        this.applyTarget(entry, item.target, value, protection);
      }

      for (const customItem of customItems) {
        if (customItem.sourceColumnIndex >= row.length) {
          continue;
        }
        const customValue = row[customItem.sourceColumnIndex];
        if (customValue === '') {
          continue;
        }
        const fieldName = customItem.customFieldName.trim() !== ''
          ? customItem.customFieldName.trim()
          : customItem.sourceColumnName;
        entry.setField(fieldName, customValue, false);
      }

      this.applyRowExtensions(entry, rows[0], row);

      if (titleValue.trim() === '') {
        const fallbackTitle = this.resolveFallbackTitle(urlValue, usernameValue, entryCounter + 1);
        entry.setField('Title', fallbackTitle, protection.title);
      }

      entryCounter++;
      parentGroup.entries.push(entry);
    }

    return rootGroup;
  }

  /**
   * 构建列映射策略（由具体格式子类实现）
   */
  protected abstract buildColumnMapping(headerRow: string[]): CsvColumnMapping[];

  /**
   * 行级扩展钩子：列映射主流程之后的按行自定义处理（默认空实现）
   * 供需要列间条件逻辑的格式使用（如 Bitwarden favorite/fields、Proton email 兜底）
   */
  protected applyRowExtensions(entry: KdbxEntry, headerRow: string[], row: string[]): void {
  }

  /**
   * 分组路径归一化钩子（默认原样返回，LastPass 覆写以支持 '\' 分隔）
   */
  protected normalizeGroupPath(groupPath: string): string {
    return groupPath;
  }

  /**
   * 标题兜底链：URL 域名 → 用户名 → 本地化「条目 N」
   */
  protected resolveFallbackTitle(urlValue: string, usernameValue: string, index: number): string {
    const hostname = BaseCsvImportHandler.extractHostname(urlValue);
    if (hostname !== '') {
      return hostname;
    }
    if (usernameValue.trim() !== '') {
      return usernameValue;
    }
    const localized = ResourceManager.getString($r('app.string.import_export_fallback_entry_title'), index);
    if (localized !== '') {
      return localized;
    }
    return `条目 ${index}`;
  }

  /**
   * 解析时间戳字符串（KeePassXC 语义）：
   * 纯数字 ≤ INT32_MAX 视为秒；> 1e14 视为微秒；其余视为毫秒；非数字走 Date.parse
   */
  static parseTimestamp(value: string): Date | undefined {
    const trimmed = value.trim();
    if (trimmed === '') {
      return undefined;
    }
    if (/^\d+$/.test(trimmed)) {
      const numeric = parseInt(trimmed);
      if (numeric <= 0) {
        return undefined;
      }
      if (numeric <= BaseCsvImportHandler.INT32_MAX) {
        return new Date(numeric * 1000);
      }
      if (numeric > BaseCsvImportHandler.MICROSECOND_THRESHOLD) {
        return new Date(Math.floor(numeric / 1000));
      }
      return new Date(numeric);
    }
    const parsed = Date.parse(trimmed);
    if (isNaN(parsed)) {
      return undefined;
    }
    return new Date(parsed);
  }

  /**
   * 解析标签串：[,;\t] 分隔（KeePassXC Entry TagDelimiterRegex），去重排序
   */
  static parseTags(value: string): string[] {
    const result: string[] = [];
    const seen = new Set<string>();
    const parts = value.split(/[,;\t]/);
    for (const part of parts) {
      const tag = part.trim();
      if (tag === '' || seen.has(tag)) {
        continue;
      }
      seen.add(tag);
      result.push(tag);
    }
    result.sort();
    return result;
  }

  /**
   * 提取 URL 域名（解析失败返回空串）
   */
  static extractHostname(urlValue: string): string {
    const trimmed = urlValue.trim();
    if (trimmed === '') {
      return '';
    }
    try {
      const parsed = url.URL.parseURL(trimmed);
      return parsed.host;
    } catch (e) {
      return '';
    }
  }

  /**
   * 判断表头是否包含全部必需列（大小写/空白不敏感）
   */
  protected static hasAllHeaders(headerRow: string[], required: string[]): boolean {
    const normalized = BaseCsvImportHandler.normalizeHeaders(headerRow);
    for (const item of required) {
      if (normalized.indexOf(item) < 0) {
        return false;
      }
    }
    return true;
  }

  /**
   * 判断表头是否包含任一候选列（大小写/空白不敏感）
   */
  protected static hasAnyHeader(headerRow: string[], candidates: string[]): boolean {
    const normalized = BaseCsvImportHandler.normalizeHeaders(headerRow);
    for (const item of candidates) {
      if (normalized.indexOf(item) >= 0) {
        return true;
      }
    }
    return false;
  }

  /**
   * 查找表头列索引（大小写/空白不敏感），未找到返回 -1
   */
  protected static findHeaderIndex(headerRow: string[], name: string): number {
    const target = name.trim().toLowerCase();
    for (let i = 0; i < headerRow.length; i++) {
      if (headerRow[i].trim().toLowerCase() === target) {
        return i;
      }
    }
    return -1;
  }

  private static normalizeHeaders(headerRow: string[]): string[] {
    const normalized: string[] = [];
    for (const header of headerRow) {
      normalized.push(header.trim().toLowerCase());
    }
    return normalized;
  }

  private getFieldProtection(): CsvFieldProtection {
    const db = FileService.getDatabase();
    const protection = db?.meta?.memoryProtection;
    const result: CsvFieldProtection = {
      title: protection?.title ?? false,
      username: protection?.userName ?? false,
      url: protection?.url ?? false,
      notes: protection?.notes ?? false
    };
    return result;
  }

  private resolveTargetGroup(
    rootGroup: KdbxGroup,
    mapping: CsvColumnMapping[],
    row: string[],
    cache: Map<string, KdbxGroup>
  ): KdbxGroup {
    for (const item of mapping) {
      if (item.target !== CsvTargetField.GROUP) {
        continue;
      }
      if (item.columnIndex >= row.length) {
        continue;
      }
      const groupPath = this.normalizeGroupPath(row[item.columnIndex].trim());
      if (groupPath === '') {
        break;
      }
      return BaseCsvImportHandler.getOrCreateGroup(rootGroup, groupPath, cache);
    }
    return rootGroup;
  }

  private static getOrCreateGroup(
    rootGroup: KdbxGroup,
    groupPath: string,
    cache: Map<string, KdbxGroup>
  ): KdbxGroup {
    const cached = cache.get(groupPath);
    if (cached !== undefined) {
      return cached;
    }

    let current = rootGroup;
    const parts = groupPath.split('/');
    for (const part of parts) {
      if (part === '') {
        continue;
      }
      let found: KdbxGroup | undefined = undefined;
      for (const child of current.groups) {
        if (child.name === part) {
          found = child;
          break;
        }
      }
      if (found === undefined) {
        found = KdbxGroup.create(part, current);
        current.groups.push(found);
      }
      current = found;
    }

    cache.set(groupPath, current);
    return current;
  }

  private applyTarget(
    entry: KdbxEntry,
    target: CsvTargetField,
    value: string,
    protection: CsvFieldProtection
  ): void {
    switch (target) {
      case CsvTargetField.TITLE:
        entry.setField('Title', value, protection.title);
        break;
      case CsvTargetField.USERNAME:
        entry.setField('UserName', value, protection.username);
        break;
      case CsvTargetField.PASSWORD:
        entry.setField('Password', value, true);
        break;
      case CsvTargetField.URL:
        entry.setField('URL', value, protection.url);
        break;
      case CsvTargetField.NOTES:
        entry.setField('Notes', value, protection.notes);
        break;
      case CsvTargetField.TOTP:
        BaseCsvImportHandler.applyTotp(entry, value);
        break;
      case CsvTargetField.TAGS:
        entry.tags = BaseCsvImportHandler.parseTags(value);
        break;
      case CsvTargetField.EXPIRY_TIME: {
        const expiryTime = BaseCsvImportHandler.parseTimestamp(value);
        if (expiryTime !== undefined) {
          entry.times.expires = true;
          entry.times.expiryTime = expiryTime;
        }
        break;
      }
      case CsvTargetField.ICON: {
        const icon = parseInt(value);
        if (!isNaN(icon)) {
          entry.icon = icon;
        }
        break;
      }
      case CsvTargetField.LAST_MODIFIED: {
        const time = BaseCsvImportHandler.parseTimestamp(value);
        if (time !== undefined) {
          entry.times.lastModTime = time;
          entry.times.lastAccessTime = time;
        }
        break;
      }
      case CsvTargetField.CREATED: {
        const time = BaseCsvImportHandler.parseTimestamp(value);
        if (time !== undefined) {
          entry.times.creationTime = time;
        }
        break;
      }
      case CsvTargetField.GROUP:
      default:
        break;
    }
  }

  /**
   * TOTP 存储：otpauth:// URI 原样存入 otp 字段；裸密钥转 key= 格式（KeeOtpParser 兼容）
   */
  private static applyTotp(entry: KdbxEntry, value: string): void {
    const trimmed = value.trim();
    if (trimmed === '') {
      return;
    }
    if (trimmed.startsWith('otpauth://')) {
      entry.setField('otp', trimmed, true);
    } else {
      entry.setField('otp', `key=${trimmed}`, true);
    }
  }
}
