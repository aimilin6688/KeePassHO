import { KdbxGroup } from 'kdbxweb';
import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine } from '../../csvimport/CsvColumnMappingEngine';
import {
  ColumnMappingItem,
  ColumnMappingProfile
} from '../../csvimport/CsvMappingModels';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { IImportHandler } from '../IImportHandler';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { ResourceManager } from '../../../../common/utils';

/**
 * 通用 CSV 导入处理器（嗅探兜底）
 * 通过 ColumnNameMapper 同义词字典对表头自动建议列映射；
 * 无任何可识别列时抛 INVALID_CSV_HEADER；
 * 支持列映射向导确认后的档案导入（importWithProfile）
 */
export class GenericCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName = 'Generic CSV';

  constructor() {
    super('GENERIC_CSV');
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    return 0;
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    const mapping = CsvColumnMappingEngine.buildSuggestedMapping(headerRow);
    if (mapping.length === 0) {
      throw new ImportError(
        ImportExportErrorCode.INVALID_CSV_HEADER,
        ResourceManager.getString($r('app.string.import_export_invalid_format'))
      );
    }
    return mapping;
  }

  /**
   * 按向导确认后的映射档案导入
   * @param rows 已解析行（表头为第一行）
   * @param profile 向导确认的列映射档案
   * @throws ImportError 全部列均为 SKIP 时抛出（INVALID_CSV_HEADER）
   */
  importWithProfile(rows: string[][], profile: ColumnMappingProfile): KdbxGroup {
    const mapping: CsvColumnMapping[] = [];
    const customItems: ColumnMappingItem[] = [];
    for (const item of profile.items) {
      if (item.targetField === CsvTargetField.CUSTOM) {
        customItems.push(item);
        continue;
      }
      if (item.targetField === CsvTargetField.SKIP) {
        continue;
      }
      mapping.push({ target: item.targetField, columnIndex: item.sourceColumnIndex });
    }
    if (mapping.length === 0 && customItems.length === 0) {
      throw new ImportError(
        ImportExportErrorCode.INVALID_CSV_HEADER,
        ResourceManager.getString($r('app.string.import_wizard_no_mapped_column'))
      );
    }
    return this.importRowsWithMapping(rows, mapping, customItems, profile.importTargetGroupName);
  }
}
