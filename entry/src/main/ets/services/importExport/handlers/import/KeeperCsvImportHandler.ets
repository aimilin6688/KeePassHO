import { KdbxEntry } from 'kdbxweb';
import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { IImportHandler } from '../IImportHandler';

const KEEPER_PROFILE: CsvFormatProfile = new CsvFormatProfile(
  'KEEPER_CSV',
  'Keeper CSV',
  ['record_type', 'folder', 'title'],
  {
    'folder': CsvTargetField.GROUP,
    'title': CsvTargetField.TITLE,
    'note': CsvTargetField.NOTES,
    'login_url': CsvTargetField.URL,
    'login_username': CsvTargetField.USERNAME,
    'login_password': CsvTargetField.PASSWORD,
    'login_totp': CsvTargetField.TOTP
  }
);

/** Keeper CSV 已知列全集 */
const KEEPER_KNOWN_HEADERS: string[] = [
  'record_type', 'folder', 'title', 'note',
  'login_url', 'login_username', 'login_password', 'login_totp'
];

/**
 * Keeper CSV 导入处理器（报告 §三/§六 规格）
 * 首列 record_type（login/card/address/bankAccount/...）为文档化特征：
 * - login 行：folder→Group、title→Title、note→Notes、login_url→URL、
 *   login_username→UserName、login_password→Password（受保护）、login_totp→TOTP
 * - 非 login 行：record_type 之后列按行类型偏移（login_* 列位置承载类型专属数据），
 *   列值按原表头名转入自定义字段（无损），清空标准字段，并附 Record Type 标记
 */
export class KeeperCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName = 'Keeper CSV';

  constructor() {
    super('KEEPER_CSV');
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    // 首列 record_type + 精确表头集合匹配（多一列/少一列均不认领）
    if (headerRow.length > 0 && headerRow[0].trim().toLowerCase() === 'record_type'
      && BaseCsvImportHandler.matchesHeadersClaimable(headerRow, KEEPER_PROFILE.requiredHeaders, KEEPER_KNOWN_HEADERS)) {
      return BaseCsvImportHandler.SNIFF_CONFIDENCE;
    }
    return 0;
  }

  protected applyRowExtensions(entry: KdbxEntry, headerRow: string[], row: string[]): void {
    const typeIndex = BaseCsvImportHandler.findHeaderIndex(headerRow, 'record_type');
    if (typeIndex < 0 || typeIndex >= row.length) {
      return;
    }
    const rawType = row[typeIndex].trim();
    const recordType = rawType.toLowerCase();
    if (recordType === '' || recordType === 'login') {
      return;
    }
    KeeperCsvImportHandler.moveShiftedColumn(entry, headerRow, row, 'login_url', 'URL', false);
    KeeperCsvImportHandler.moveShiftedColumn(entry, headerRow, row, 'login_username', 'UserName', false);
    KeeperCsvImportHandler.moveShiftedColumn(entry, headerRow, row, 'login_password', 'Password', true);
    // 偏移后该列承载任意类型数据（如持卡人姓名），非秘密，不加密存储
    KeeperCsvImportHandler.moveShiftedColumn(entry, headerRow, row, 'login_totp', 'otp', false);
    entry.setField('Record Type', rawType, false);
  }

  /**
   * 非 login 行的列偏移处理：列值非空时清空对应标准字段，
   * 并按原表头名转存为自定义字段（保留敏感列保护）
   */
  private static moveShiftedColumn(
    entry: KdbxEntry,
    headerRow: string[],
    row: string[],
    columnName: string,
    standardField: string,
    protect: boolean
  ): void {
    const index = BaseCsvImportHandler.findHeaderIndex(headerRow, columnName);
    if (index < 0 || index >= row.length) {
      return;
    }
    const value = row[index];
    if (value.trim() === '') {
      return;
    }
    entry.setField(standardField, '', protect);
    entry.setField(columnName, value, protect);
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    return CsvColumnMappingEngine.buildMappingFromProfile(KEEPER_PROFILE, headerRow);
  }
}
