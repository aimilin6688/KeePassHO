import { KdbxEntry } from 'kdbxweb';
import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvFormatSignature, FormatSignatureLibrary } from '../../sniffing/FormatSignatureLibrary';
import { IImportHandler } from '../IImportHandler';
import { KdbxUtils } from '../../../../common/utils';

/**
 * 签名驱动的通用 CSV 导入处理器
 * 由 FormatSignatureLibrary 的签名数据构造（不为每个纯数据格式写独立 handler 类）：
 * - 列映射：签名的 headerMap 预设映射
 * - 行级扩展：favoriteHeaders（1/true → FAVORITE_TAG）、customHeaderMap（表头 → 自定义字段名）、
 *   附加列 → 自定义字段（字段名 = 原始表头，不归一化）
 * - 分组路径：slashGroupPath 签名将 '\' 归一化为 '/'（LastPass 语义）
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
    // 签名库统一评分：必需列 + 特征列 + 未知列须不可识别（v3 认领语义）
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

  protected normalizeGroupPath(groupPath: string): string {
    if (this.signature.slashGroupPath) {
      return groupPath.replace(/\\/g, '/');
    }
    return groupPath;
  }

  protected applyRowExtensions(entry: KdbxEntry, headerRow: string[], row: string[]): void {
    for (let i = 0; i < headerRow.length; i++) {
      if (i >= row.length) {
        break;
      }
      const value = row[i];
      if (value.trim() === '') {
        continue;
      }
      const normalized = headerRow[i].trim().toLowerCase();
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
        continue;
      }
      if (this.signature.ignoredHeaders.indexOf(normalized) >= 0) {
        continue;
      }
      // headerMap 键已由列映射主流程导入；knownHeaders 内的格式内部列（如 guid/fav）跳过
      if (this.signature.headerMap[normalized] !== undefined
        || this.signature.knownHeaders.indexOf(normalized) >= 0) {
        continue;
      }
      // 附加列（不在签名已知全集）→ 自定义字段，字段名 = 原始表头
      entry.setField(headerRow[i].trim(), value, false);
    }
  }
}
