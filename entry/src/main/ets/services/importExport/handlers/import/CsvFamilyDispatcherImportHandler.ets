import { KdbxGroup, ByteUtils } from 'kdbxweb';
import { CsvParser } from '../../csvimport/CsvParser';
import { FileContentInfo } from '../../../../storage';
import { IImportHandler } from '../IImportHandler';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { ResourceManager } from '../../../../common/utils';
import { SettingsService } from '../../../SettingsService';
import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { LastPassCsvImportHandler } from './LastPassCsvImportHandler';
import { BitwardenCsvImportHandler } from './BitwardenCsvImportHandler';
import { ProtonPassCsvImportHandler } from './ProtonPassCsvImportHandler';
import { DashlaneCsvImportHandler } from './DashlaneCsvImportHandler';
import { OnePasswordCsvImportHandler } from './OnePasswordCsvImportHandler';
import { KeeperCsvImportHandler } from './KeeperCsvImportHandler';
import { EnpassCsvImportHandler } from './EnpassCsvImportHandler';
import { FirefoxCsvImportHandler } from './FirefoxCsvImportHandler';
import { ChromeCsvImportHandler } from './ChromeCsvImportHandler';
import { GenericCsvImportHandler } from './GenericCsvImportHandler';
import { PresetCsvImportHandler } from './PresetCsvImportHandler';
import { FormatSignatureLibrary } from '../../sniffing/FormatSignatureLibrary';
import { ImportWizardBridge } from '../../wizard/ImportWizardBridge';
import { ColumnMappingProfile, CsvMappingPreview, WizardTargetField } from '../../csvimport/CsvMappingModels';

/** 嗅探分发置信度阈值 */
const SNIFF_DISPATCH_THRESHOLD = 70;
/** 嗅探采样数据行数 */
const SAMPLE_ROW_COUNT = 5;

/**
 * CSV 导入格式族调度器
 * 占据 '.csv' / 'CSV' 路由键，按表头嗅探将导入分发到
 * LastPass / Bitwarden / Proton Pass / Dashlane / 1Password / Keeper / Enpass / Firefox / Chrome /
 * 签名库长尾格式（Norton Identity Safe / True Key…）处理器；
 * 全部未命中（未知来源）时弹列映射向导（无 UI 上下文回落通用建议映射直导）
 */
export class CsvFamilyDispatcherImportHandler implements IImportHandler {
  readonly supportedExtensions: string[] = ['.csv'];
  readonly formatId = 'CSV';
  readonly formatName = 'CSV';

  /** 格式族（按特异性从高到低排序，两两冲突已由特征列/排除列消歧；签名库长尾格式追加在尾部队列） */
  private readonly family: BaseCsvImportHandler[];
  private readonly fallbackHandler: GenericCsvImportHandler;

  constructor() {
    this.family = [
      new LastPassCsvImportHandler(),
      new BitwardenCsvImportHandler(),
      new ProtonPassCsvImportHandler(),
      new DashlaneCsvImportHandler(),
      new OnePasswordCsvImportHandler(),
      new KeeperCsvImportHandler(),
      new EnpassCsvImportHandler(),
      new FirefoxCsvImportHandler(),
      new ChromeCsvImportHandler()
    ];
    // 签名库长尾格式（数据驱动，新增格式 = 签名库追加一条数据行）
    for (const signature of FormatSignatureLibrary.getAllSignatures()) {
      this.family.push(new PresetCsvImportHandler(signature));
    }
    this.fallbackHandler = new GenericCsvImportHandler();
  }

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  /**
   * 根据表头嗅探具体格式标识
   * @param headerRow 表头行
   * @param sampleRows 采样数据行
   * @returns 具体格式 formatId（无法识别时返回 'GENERIC_CSV'）
   */
  detectFormatId(headerRow: string[], sampleRows: string[][]): string {
    for (const handler of this.family) {
      if (handler.sniff(headerRow, sampleRows) >= SNIFF_DISPATCH_THRESHOLD) {
        return handler.formatId;
      }
    }
    return this.fallbackHandler.formatId;
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    const content = ByteUtils.bytesToString(fileContent.content);
    const parseResult = new CsvParser().parse(content);
    if (parseResult.rows.length === 0) {
      throw new ImportError(
        ImportExportErrorCode.FILE_EMPTY,
        ResourceManager.getString($r('app.string.import_export_file_empty'))
      );
    }

    const headerRow = parseResult.rows[0];
    const sampleRows = parseResult.rows.slice(1, 1 + SAMPLE_ROW_COUNT);

    let target: BaseCsvImportHandler | null = null;
    let detectedFormatName = '';
    for (const handler of this.family) {
      if (handler.sniff(headerRow, sampleRows) >= SNIFF_DISPATCH_THRESHOLD) {
        target = handler;
        detectedFormatName = handler.formatName;
        break;
      }
    }

    // 未知来源默认弹列映射向导；已知格式经设置开关可强制预览确认（§4.4）
    const forceWizard = SettingsService.getSync(
      SettingsService.KEY_IMPORT_FORCE_CSV_WIZARD,
      SettingsService.KEY_IMPORT_FORCE_CSV_WIZARD_DEFAULT
    );
    if (target === null || forceWizard) {
      const preview = ImportWizardBridge.buildPreview(parseResult.rows, detectedFormatName);
      // 未知来源但建议映射可识别（如标准 KeePass 风格表头 Group/Title/UserName/Password/URL/Notes）
      // → 不打扰用户弹向导，按建议映射直接导入；仅无可识别列时才需要向导人工映射
      const skipWizard = target === null && !forceWizard && this.hasMappedSuggestion(preview);
      if (!skipWizard) {
        const profile: ColumnMappingProfile | null =
          await ImportWizardBridge.getInstance().requestColumnMapping(preview);
        if (profile !== null) {
          return this.fallbackHandler.importWithProfile(parseResult.rows, profile);
        }
        // profile === null：无 UI 上下文可呈现向导（自动化/后台），回落直导
      }
    }

    const finalTarget = target !== null ? target : this.fallbackHandler;
    return finalTarget.importRows(parseResult.rows);
  }

  /**
   * 预览的建议映射中是否存在非 SKIP 列
   */
  private hasMappedSuggestion(preview: CsvMappingPreview): boolean {
    for (const item of preview.suggestedItems) {
      if (item.targetField !== WizardTargetField.SKIP) {
        return true;
      }
    }
    return false;
  }
}
