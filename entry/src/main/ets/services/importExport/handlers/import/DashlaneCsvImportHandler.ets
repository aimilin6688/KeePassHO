import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { IImportHandler } from '../IImportHandler';

const DASHLANE_PROFILE: CsvFormatProfile = new CsvFormatProfile(
  'DASHLANE_CSV',
  'Dashlane CSV',
  ['title', 'url', 'username', 'password'],
  {
    'title': CsvTargetField.TITLE,
    'url': CsvTargetField.URL,
    'username': CsvTargetField.USERNAME,
    'password': CsvTargetField.PASSWORD,
    'note': CsvTargetField.NOTES,
    'category': CsvTargetField.GROUP,
    'otpsecret': CsvTargetField.TOTP,
    'lastmodified': CsvTargetField.LAST_MODIFIED
  }
);

/**
 * Dashlane 6+ CSV 导入处理器
 * 导出格式：title,url,username,password,note,category,otpSecret,lastModified
 * 嗅探排除 KeePass 风格导出（group/notes 列）：此类导出同样含 lastModified，
 * 若不排除会误认领并丢失 Group/Notes 映射
 */
export class DashlaneCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName = 'Dashlane CSV';

  constructor() {
    super('DASHLANE_CSV');
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    if (BaseCsvImportHandler.hasAllHeaders(headerRow, DASHLANE_PROFILE.requiredHeaders)
      && BaseCsvImportHandler.hasAnyHeader(headerRow, ['category', 'otpsecret', 'lastmodified'])
      && !BaseCsvImportHandler.hasAnyHeader(headerRow, ['group', 'notes'])) {
      return BaseCsvImportHandler.SNIFF_CONFIDENCE;
    }
    return 0;
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    return CsvColumnMappingEngine.buildMappingFromProfile(DASHLANE_PROFILE, headerRow);
  }
}
