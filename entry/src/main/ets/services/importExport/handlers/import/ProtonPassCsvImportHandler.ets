import { KdbxEntry } from 'kdbxweb';
import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { CsvColumnMapping, CsvColumnMappingEngine, CsvFormatProfile } from '../../csvimport/CsvColumnMappingEngine';
import { CsvTargetField } from '../../csvimport/CsvImportModels';
import { IImportHandler } from '../IImportHandler';
import { KdbxUtils } from '../../../../common/utils';

const PROTONPASS_PROFILE: CsvFormatProfile = new CsvFormatProfile(
  'PROTONPASS_CSV',
  'Proton Pass CSV',
  ['name', 'url', 'username', 'password'],
  {
    'name': CsvTargetField.TITLE,
    'url': CsvTargetField.URL,
    'username': CsvTargetField.USERNAME,
    'password': CsvTargetField.PASSWORD,
    'totp': CsvTargetField.TOTP,
    'note': CsvTargetField.NOTES,
    'vault': CsvTargetField.GROUP
  }
);

/** Proton Pass CSV 已知列全集 */
const PROTON_KNOWN_HEADERS: string[] = ['name', 'url', 'username', 'password', 'note', 'totp', 'email', 'vault'];

/**
 * Proton Pass CSV 导入处理器
 * 导出格式：name,url,username,password,note,totp,email,vault
 * 嗅探特征列：email/totp/vault 任一（Chrome CSV 无这些列，避免误认领）；
 * email 兜底：UserName 为空时 email 作 UserName，否则存为自定义字段 Email
 * （对齐 KeePassXC ProtonPassReader JSON 语义）
 */
export class ProtonPassCsvImportHandler extends BaseCsvImportHandler implements IImportHandler {
  readonly formatName = 'Proton Pass CSV';

  constructor() {
    super('PROTONPASS_CSV');
  }

  sniff(headerRow: string[], sampleRows: string[][]): number {
    // 精确表头集合匹配（多一列/少一列均不认领）+ 特征列（与 Chrome 最小集区分）
    if (BaseCsvImportHandler.matchesHeadersClaimable(headerRow, PROTONPASS_PROFILE.requiredHeaders, PROTON_KNOWN_HEADERS)
      && BaseCsvImportHandler.hasAnyHeader(headerRow, ['email', 'totp', 'vault'])) {
      return BaseCsvImportHandler.SNIFF_CONFIDENCE;
    }
    return 0;
  }

  protected applyRowExtensions(entry: KdbxEntry, headerRow: string[], row: string[]): void {
    const emailIndex = BaseCsvImportHandler.findHeaderIndex(headerRow, 'email');
    if (emailIndex < 0 || emailIndex >= row.length) {
      return;
    }
    const email = row[emailIndex].trim();
    if (email === '') {
      return;
    }
    const username = KdbxUtils.getFieldValueString(entry.fields, 'UserName');
    if (username === '') {
      entry.setField('UserName', email, false);
    } else {
      entry.setField('Email', email, false);
    }
  }

  protected buildColumnMapping(headerRow: string[]): CsvColumnMapping[] {
    return CsvColumnMappingEngine.buildMappingFromProfile(PROTONPASS_PROFILE, headerRow);
  }
}
