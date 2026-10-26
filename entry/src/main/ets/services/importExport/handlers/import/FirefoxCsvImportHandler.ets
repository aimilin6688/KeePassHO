import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { IImportHandler } from '../IImportHandler';

const FIREFOX_PROFILE: CsvFormatProfile = new CsvFormatProfile(
  'FIREFOX_CSV',
  'Firefox CSV',
  ['url', 'username', 'password'],
  {
    'url': CsvTargetField.URL,
    'username': CsvTargetField.USERNAME,
    'password': CsvTargetField.PASSWORD,
    'httprealm': CsvTargetField.NOTES,
    'timecreated': CsvTargetField.CREATED,
    'timepasswordchanged': CsvTargetField.LAST_MODIFIED
  }
);

/** Firefox 特征列：命中其一才认领，避免误判普通 url,username,password 表头 */
const FIREFOX_DISTINGUISHERS: string[] = ['httprealm', 'formactionorigin', 'guid', 'timepasswordchanged'];

/**
 * Firefox about:logins CSV 导入处理器
 * 导出格式：url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged
 * httpRealm → Notes；timeCreated → 创建时间；timePasswordChanged → 修改/访问时间
 */
export class FirefoxCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName = 'Firefox CSV';

  constructor() {
    super('FIREFOX_CSV');
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    if (!BaseCsvImportHandler.hasAllHeaders(headerRow, FIREFOX_PROFILE.requiredHeaders)) {
      return 0;
    }
    if (BaseCsvImportHandler.hasAnyHeader(headerRow, FIREFOX_DISTINGUISHERS)) {
      return BaseCsvImportHandler.SNIFF_CONFIDENCE;
    }
    return 0;
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    return CsvColumnMappingEngine.buildMappingFromProfile(FIREFOX_PROFILE, headerRow);
  }
}
