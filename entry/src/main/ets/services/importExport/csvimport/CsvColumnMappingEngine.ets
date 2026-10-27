import { CsvTargetField } from './CsvImportModels';
import { ColumnNameMapper, ColumnMatch } from './ColumnNameMapper';
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
 * 模糊匹配候选列（阶段②同目标冲突消歧：命中同义词最长者优先）
 */
interface FuzzyCandidate {
  columnIndex: number;
  match: ColumnMatch;
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
   * 通过列名同义词字典构建建议映射（通用 CSV / 列映射向导预填）
   * 两阶段：①精确同义词命中，同目标保留首列（KeePass 语义）
   *        ②模糊命中（包含/前缀，如「GROUP分组」「NAME名称」），同目标取命中同义词最长（最具体）的列
   * @param headers 表头行
   * @returns 列映射；同一目标字段只保留一列
   */
  static buildSuggestedMapping(headers: string[]): CsvColumnMapping[] {
    const mapping: CsvColumnMapping[] = [];
    const usedTargets = new Set<CsvTargetField>();
    const usedColumns = new Set<number>();

    // 阶段①：精确同义词（同目标保留首列，KeePass 语义）
    for (let i = 0; i < headers.length; i++) {
      const target = ColumnNameMapper.mapExact(headers[i]);
      if (target === undefined) {
        continue;
      }
      usedColumns.add(i);
      if (usedTargets.has(target)) {
        continue;
      }
      usedTargets.add(target);
      mapping.push({ target: target, columnIndex: i });
    }

    // 阶段②：模糊（包含/前缀），同目标取命中同义词最长者，平局取低列号
    const bestByTarget = new Map<CsvTargetField, FuzzyCandidate>();
    for (let i = 0; i < headers.length; i++) {
      if (usedColumns.has(i)) {
        continue;
      }
      const match = ColumnNameMapper.mapWithSpecificity(headers[i]);
      if (match === undefined || usedTargets.has(match.target)) {
        continue;
      }
      const existing = bestByTarget.get(match.target);
      if (existing === undefined || match.matchedLength > existing.match.matchedLength) {
        bestByTarget.set(match.target, { columnIndex: i, match: match });
      }
    }
    const winners: FuzzyCandidate[] = [];
    bestByTarget.forEach((candidate: FuzzyCandidate) => {
      winners.push(candidate);
    });
    winners.sort((a: FuzzyCandidate, b: FuzzyCandidate): number => a.columnIndex - b.columnIndex);
    for (const candidate of winners) {
      mapping.push({ target: candidate.match.target, columnIndex: candidate.columnIndex });
    }
    return mapping;
  }
}
