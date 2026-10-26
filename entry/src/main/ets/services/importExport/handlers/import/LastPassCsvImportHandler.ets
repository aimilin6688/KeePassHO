import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { IImportHandler } from '../IImportHandler';

const LASTPASS_PROFILE: CsvFormatProfile = new CsvFormatProfile(
  'LASTPASS_CSV',
  'LastPass CSV',
  ['url', 'username', 'password', 'extra', 'name', 'grouping'],
  {
    'url': CsvTargetField.URL,
    'username': CsvTargetField.USERNAME,
    'password': CsvTargetField.PASSWORD,
    'extra': CsvTargetField.NOTES,
    'name': CsvTargetField.TITLE,
    'grouping': CsvTargetField.GROUP,
    'totp': CsvTargetField.TOTP
  }
);

/**
 * LastPass CSV 导入处理器
 * 导出格式：url,username,password,extra,name,grouping,fav[,totp]
 * grouping 支持 '\'（KeePass LastPassCsv2 语义）与 '/' 两种嵌套分隔符；
 * extra 多行内容导入 Notes；totp 列导入 otp 字段；fav 列忽略
 */
export class LastPassCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName = 'LastPass CSV';

  constructor() {
    super('LASTPASS_CSV');
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    if (BaseCsvImportHandler.hasAllHeaders(headerRow, LASTPASS_PROFILE.requiredHeaders)) {
      return BaseCsvImportHandler.SNIFF_CONFIDENCE;
    }
    return 0;
  }

  protected normalizeGroupPath(groupPath: string): string {
    return groupPath.replace(/\\/g, '/');
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    return CsvColumnMappingEngine.buildMappingFromProfile(LASTPASS_PROFILE, headerRow);
  }
}
