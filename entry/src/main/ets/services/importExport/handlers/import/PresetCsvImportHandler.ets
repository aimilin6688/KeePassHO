import { KdbxEntry } from 'kdbxweb';
import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvFormatSignature, FormatSignatureLibrary } from '../../sniffing/FormatSignatureLibrary';
import { IImportHandler } from '../IImportHandler';
import { KdbxUtils } from '../../../../common/utils';

/**
 * 签名驱动的通用 CSV 导入处理器
 * 由 FormatSignatureLibrary 的签名数据构造（不为每个长尾格式写独立 handler 类）：
 * - 列映射：签名的 headerMap 预设映射
 * - 行级扩展：customHeaderMap（表头 → 自定义字段名）+ favoriteHeaders（1/true → FAVORITE_TAG）
 */
export class PresetCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName: string;
  private readonly signature: CsvFormatSignature;

  constructor(signature: CsvFormatSignature) {
    super(signature.formatId);
    this.signature = signature;
    this.formatName = signature.formatName;
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    return FormatSignatureLibrary.scoreSignature(this.signature, headerRow);
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    const profile = new CsvFormatProfile(
      this.signature.formatId,
      this.signature.formatName,
      this.signature.requiredHeaders,
      this.signature.headerMap
    );
    return CsvColumnMappingEngine.buildMappingFromProfile(profile, headerRow);
  }

  protected applyRowExtensions(entry: KdbxEntry, headerRow: string[], row: string[]): void {
    for (let i = 0; i < headerRow.length; i++) {
      const normalized = headerRow[i].trim().toLowerCase();
      if (i >= row.length) {
        break;
      }
      const value = row[i];
      if (value.trim() === '') {
        continue;
      }
      if (this.signature.favoriteHeaders.indexOf(normalized) >= 0) {
        const normalizedValue = value.trim().toLowerCase();
        if (normalizedValue === '1' || normalizedValue === 'true') {
          entry.tags.push(KdbxUtils.FAVORITE_TAG);
        }
        continue;
      }
      const customFieldName = this.signature.customHeaderMap[normalized];
      if (customFieldName !== undefined) {
        entry.setField(customFieldName, value, false);
      }
    }
  }
}
