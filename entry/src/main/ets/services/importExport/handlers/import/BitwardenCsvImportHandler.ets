import { KdbxEntry } from 'kdbxweb';
import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { IImportHandler } from '../IImportHandler';
import { KdbxUtils } from '../../../../common/utils';

const BITWARDEN_PROFILE: CsvFormatProfile = new CsvFormatProfile(
  'BITWARDEN_CSV',
  'Bitwarden CSV',
  ['type', 'name', 'login_uri', 'login_username', 'login_password'],
  {
    'folder': CsvTargetField.GROUP,
    'name': CsvTargetField.TITLE,
    'notes': CsvTargetField.NOTES,
    'login_uri': CsvTargetField.URL,
    'login_username': CsvTargetField.USERNAME,
    'login_password': CsvTargetField.PASSWORD,
    'login_totp': CsvTargetField.TOTP
  }
);

/**
 * Bitwarden CSV 导入处理器
 * 导出格式：folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
 * favorite=1 时打上 FAVORITE_TAG 标签；
 * fields 列按「name: value; name2: value2」拆分为自定义字段；
 * type 2/3/4（笔记/卡/身份）的 login_* 列为空，按标题+备注+自定义字段导入
 */
export class BitwardenCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName = 'Bitwarden CSV';

  constructor() {
    super('BITWARDEN_CSV');
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    if (BaseCsvImportHandler.hasAllHeaders(headerRow, BITWARDEN_PROFILE.requiredHeaders)) {
      return BaseCsvImportHandler.SNIFF_CONFIDENCE;
    }
    return 0;
  }

  protected applyRowExtensions(entry: KdbxEntry, headerRow: string[], row: string[]): void {
    const favoriteIndex = BaseCsvImportHandler.findHeaderIndex(headerRow, 'favorite');
    if (favoriteIndex >= 0 && favoriteIndex < row.length && row[favoriteIndex].trim() === '1') {
      entry.tags.push(KdbxUtils.FAVORITE_TAG);
    }
    const fieldsIndex = BaseCsvImportHandler.findHeaderIndex(headerRow, 'fields');
    if (fieldsIndex >= 0 && fieldsIndex < row.length && row[fieldsIndex].trim() !== '') {
      BitwardenCsvImportHandler.applyCustomFields(entry, row[fieldsIndex]);
    }
  }

  /**
   * 解析「name: value; name2: value2」形式的自定义字段串
   */
  private static applyCustomFields(entry: KdbxEntry, fieldsValue: string): void {
    const parts = fieldsValue.split(';');
    for (const part of parts) {
      const trimmed = part.trim();
      if (trimmed === '') {
        continue;
      }
      const colonIndex = trimmed.indexOf(':');
      if (colonIndex <= 0) {
        continue;
      }
      const fieldName = trimmed.substring(0, colonIndex).trim();
      const fieldValue = trimmed.substring(colonIndex + 1).trim();
      if (fieldName === '') {
        continue;
      }
      entry.setField(fieldName, fieldValue, false);
    }
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    return CsvColumnMappingEngine.buildMappingFromProfile(BITWARDEN_PROFILE, headerRow);
  }
}
