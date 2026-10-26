import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine } from '../../csvimport/CsvColumnMappingEngine';
import { IImportHandler } from '../IImportHandler';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { ResourceManager } from '../../../../common/utils';

/**
 * 通用 CSV 导入处理器（嗅探兜底）
 * 通过 ColumnNameMapper 同义词字典对表头自动建议列映射；
 * 无任何可识别列时抛 INVALID_CSV_HEADER
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
}
