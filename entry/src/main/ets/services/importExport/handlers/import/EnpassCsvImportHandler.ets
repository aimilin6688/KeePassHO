import { KdbxEntry } from 'kdbxweb';
import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { IImportHandler } from '../IImportHandler';

const ENPASS_PROFILE: CsvFormatProfile = new CsvFormatProfile(
  'ENPASS_CSV',
  'Enpass CSV',
  ['title', 'category', 'login', 'password'],
  {
    'title': CsvTargetField.TITLE,
    'category': CsvTargetField.GROUP,
    'login': CsvTargetField.USERNAME,
    'password': CsvTargetField.PASSWORD,
    'url': CsvTargetField.URL,
    'note': CsvTargetField.NOTES,
    'otp secret': CsvTargetField.TOTP,
    'totp secret': CsvTargetField.TOTP
  }
);

/**
 * Enpass CSV 导入处理器（报告 §三/§六 规格）
 * Enpass 6 导出约 40 个固定列，按列名（而非位置）映射：
 * Title→Title、Category→Group、Login→UserName、Password（受保护）、
 * URL、Note、OTP Secret/TOTP Secret→TOTP；
 * 首两列 "Title","Category" 为文档化嗅探特征；
 * 其余非映射列（Email/Phone/Card No/CC Cvv 等）按原表头名转自定义字段，
 * 含 password/cvv/ssn/secret 的列名受保护；
 * 字面 "Group" 列是普通自定义字段（分组由 Category 承载，避免双 Group 歧义）
 */
export class EnpassCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName = 'Enpass CSV';

  /** 已由 Profile 主流程消费的列（归一化表头名），行级钩子跳过 */
  private static readonly CONSUMED_HEADERS: string[] =
    ['title', 'category', 'login', 'password', 'url', 'note', 'otp secret', 'totp secret'];

  constructor() {
    super('ENPASS_CSV');
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    if (headerRow.length >= 2
      && headerRow[0].trim().toLowerCase() === 'title'
      && headerRow[1].trim().toLowerCase() === 'category'
      && BaseCsvImportHandler.hasAllHeaders(headerRow, ENPASS_PROFILE.requiredHeaders)) {
      return BaseCsvImportHandler.SNIFF_CONFIDENCE;
    }
    return 0;
  }

  protected applyRowExtensions(entry: KdbxEntry, headerRow: string[], row: string[]): void {
    for (let i = 0; i < headerRow.length; i++) {
      if (i >= row.length) {
        break;
      }
      const normalized = headerRow[i].trim().toLowerCase();
      if (EnpassCsvImportHandler.CONSUMED_HEADERS.indexOf(normalized) >= 0) {
        continue;
      }
      const value = row[i];
      if (value.trim() === '') {
        continue;
      }
      entry.setField(headerRow[i], value, EnpassCsvImportHandler.isSensitiveColumn(normalized));
    }
  }

  /**
   * 敏感列判定：列名含 password/cvv/ssn/secret 时自定义字段受保护
   */
  private static isSensitiveColumn(normalizedName: string): boolean {
    return normalizedName.includes('password')
      || normalizedName.includes('cvv')
      || normalizedName.includes('ssn')
      || normalizedName.includes('secret');
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    return CsvColumnMappingEngine.buildMappingFromProfile(ENPASS_PROFILE, headerRow);
  }
}
