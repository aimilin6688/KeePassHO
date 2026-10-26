import { CsvTargetField } from './CsvImportModels';
import { ColumnNameMapper } from './ColumnNameMapper';
import { ImportError, ImportExportErrorCode } from '../common/ImportExportError';
import { ResourceManager } from '../../../common/utils';

/**
 * CSV 列映射：目标字段 + 源列索引
 */
export interface CsvColumnMapping {
  target: CsvTargetField;
  columnIndex: number;
}

/**
 * CSV 格式档案：格式标识 + 必需表头 + 表头到目标字段的映射
 */
export class CsvFormatProfile {
  readonly formatId: string;
  readonly formatName: string;
  readonly requiredHeaders: string[];
  readonly headerMap: Record<string, CsvTargetField>;

  constructor(
    formatId: string,
    formatName: string,
    requiredHeaders: string[],
    headerMap: Record<string, CsvTargetField>
  ) {
    this.formatId = formatId;
    this.formatName = formatName;
    this.requiredHeaders = requiredHeaders;
    this.headerMap = headerMap;
  }
}

/**
 * CSV 列映射引擎
 * 1. 按格式 Profile 精确匹配表头构建列映射，缺失必需列抛 INVALID_CSV_HEADER
 * 2. 通用 CSV 通过 ColumnNameMapper 建议映射，同目标字段不重复（保留首个列）
 */
export class CsvColumnMappingEngine {
  /**
   * 按格式档案构建列映射
   * @param profile 格式档案
   * @param headers 表头行
   * @returns 列映射（按表头顺序）
   * @throws ImportError 缺失必需列时抛出（INVALID_CSV_HEADER）
   */
  static buildMappingFromProfile(profile: CsvFormatProfile, headers: string[]): CsvColumnMapping[] {
    const normalized: string[] = [];
    for (const header of headers) {
      normalized.push(header.trim().toLowerCase());
    }

    for (const required of profile.requiredHeaders) {
      if (normalized.indexOf(required) < 0) {
        throw new ImportError(
          ImportExportErrorCode.INVALID_CSV_HEADER,
          ResourceManager.getString($r('app.string.import_export_missing_required_column'), required)
        );
      }
    }

    const mapping: CsvColumnMapping[] = [];
    for (let i = 0; i < normalized.length; i++) {
      const target = profile.headerMap[normalized[i]];
      if (target !== undefined) {
        const item: CsvColumnMapping = {
          target: target,
          columnIndex: i
        };
        mapping.push(item);
      }
    }
    return mapping;
  }

  /**
   * 通过列名同义词字典构建建议映射（通用 CSV）
   * @param headers 表头行
   * @returns 列映射；同一目标字段只保留首个命中的列
   */
  static buildSuggestedMapping(headers: string[]): CsvColumnMapping[] {
    const mapping: CsvColumnMapping[] = [];
    const usedTargets = new Set<CsvTargetField>();
    for (let i = 0; i < headers.length; i++) {
      const target = ColumnNameMapper.mapToTargetField(headers[i]);
      if (target === undefined) {
        continue;
      }
      if (usedTargets.has(target)) {
        continue;
      }
      usedTargets.add(target);
      const item: CsvColumnMapping = {
        target: target,
        columnIndex: i
      };
      mapping.push(item);
    }
    return mapping;
  }
}
