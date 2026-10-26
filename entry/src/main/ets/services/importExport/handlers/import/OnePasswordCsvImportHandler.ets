import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { IImportHandler } from '../IImportHandler';

const ONEPASSWORD_PROFILE: CsvFormatProfile = new CsvFormatProfile(
  'ONEPASSWORD_CSV',
  '1Password CSV',
  ['title', 'url', 'username', 'password'],
  {
    'title': CsvTargetField.TITLE,
    'url': CsvTargetField.URL,
    'username': CsvTargetField.USERNAME,
    'password': CsvTargetField.PASSWORD,
    'otpauth': CsvTargetField.TOTP,
    'notes': CsvTargetField.NOTES
  }
);

/**
 * 1Password 8 CSV 导入处理器
 * 导出格式：Title,Url,Username,Password,OTPAuth,Notes
 * OTPAuth 列为特征列（KeePass 风格导出无该列名，避免误认领）；
 * OTPAuth 可为 otpauth:// URI 或裸 secret；Notes 多行内容导入 Notes
 */
export class OnePasswordCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName = '1Password CSV';

  constructor() {
    super('ONEPASSWORD_CSV');
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    if (BaseCsvImportHandler.hasAllHeaders(headerRow, ONEPASSWORD_PROFILE.requiredHeaders)
      && BaseCsvImportHandler.hasAnyHeader(headerRow, ['otpauth'])) {
      return BaseCsvImportHandler.SNIFF_CONFIDENCE;
    }
    return 0;
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    return CsvColumnMappingEngine.buildMappingFromProfile(ONEPASSWORD_PROFILE, headerRow);
  }
}
