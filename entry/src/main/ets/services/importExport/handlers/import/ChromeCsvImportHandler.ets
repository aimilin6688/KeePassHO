import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { IImportHandler } from '../IImportHandler';

const CHROME_PROFILE: CsvFormatProfile = new CsvFormatProfile(
  'CHROME_CSV',
  'Chrome CSV',
  ['name', 'url', 'username', 'password'],
  {
    'name': CsvTargetField.TITLE,
    'url': CsvTargetField.URL,
    'username': CsvTargetField.USERNAME,
    'password': CsvTargetField.PASSWORD,
    'note': CsvTargetField.NOTES
  }
);

/**
 * Chrome/Edge/Brave/Opera/Vivaldi CSV 导入处理器
 * 导出格式：name,url,username,password[,note]
 */
export class ChromeCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName = 'Chrome CSV';

  constructor() {
    super('CHROME_CSV');
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    if (BaseCsvImportHandler.hasAllHeaders(headerRow, CHROME_PROFILE.requiredHeaders)) {
      return BaseCsvImportHandler.SNIFF_CONFIDENCE;
    }
    return 0;
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    return CsvColumnMappingEngine.buildMappingFromProfile(CHROME_PROFILE, headerRow);
  }
}
