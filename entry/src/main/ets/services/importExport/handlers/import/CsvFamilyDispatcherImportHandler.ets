import { KdbxGroup } from 'kdbxweb';
import { CsvParser } from '../../csvimport/CsvParser';
import { CsvEncoding, CsvEncodingUtils } from '../../csvimport/CsvEncodingUtils';
import { FileContentInfo } from '../../../../storage';
import { IImportHandler } from '../IImportHandler';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { ResourceManager } from '../../../../common/utils';
import { SettingsService } from '../../../SettingsService';
import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { BitwardenCsvImportHandler } from './BitwardenCsvImportHandler';
import { ProtonPassCsvImportHandler } from './ProtonPassCsvImportHandler';
import { KeeperCsvImportHandler } from './KeeperCsvImportHandler';
import { EnpassCsvImportHandler } from './EnpassCsvImportHandler';
import { GenericCsvImportHandler } from './GenericCsvImportHandler';
import { PresetCsvImportHandler } from './PresetCsvImportHandler';
import { FormatSignatureLibrary } from '../../sniffing/FormatSignatureLibrary';
import { ImportWizardBridge } from '../../wizard/ImportWizardBridge';
import { ColumnMappingProfile } from '../../csvimport/CsvMappingModels';
import { FormatInfo } from '../../common/FormatInfo';
import { ImportSessionInfo } from '../../common/ImportSessionInfo';

/** 嗅探分发置信度阈值 */
const SNIFF_DISPATCH_THRESHOLD = 70;
/** 嗅探采样数据行数 */
const SAMPLE_ROW_COUNT = 5;

/**
 * CSV 导入格式族调度器
 * 占据 '.csv' / 'CSV' 路由键，按表头嗅探将导入分发到
 * Bitwarden / Proton Pass / Keeper / Enpass（特殊行处理逻辑，独立 handler 类）/
 * 签名库纯数据格式（LastPass / Dashlane / 1Password / Firefox / Chrome / Norton / True Key…）处理器；
 * 全部未命中（未知来源）时弹列映射向导（无 UI 上下文回落通用建议映射直导）
 */
export class CsvFamilyDispatcherImportHandler implements IImportHandler {
  readonly supportedExtensions: string[] = ['.csv'];
  readonly formatId = 'CSV';
  readonly formatName = 'CSV';

  /** 格式族：特殊行处理逻辑类在前（两两冲突由特征列/嗅探前置条件消歧），签名库纯数据格式追加在后 */
  private readonly family: BaseCsvImportHandler[];
  private readonly fallbackHandler: GenericCsvImportHandler;

  constructor() {
    this.family = [
      new BitwardenCsvImportHandler(),
      new ProtonPassCsvImportHandler(),
      new KeeperCsvImportHandler(),
      new EnpassCsvImportHandler()
    ];
    // 签名库纯数据格式（数据驱动，新增格式 = 签名库追加一条数据行）
    for (const signature of FormatSignatureLibrary.getAllSignatures()) {
      this.family.push(new PresetCsvImportHandler(signature));
    }
    this.fallbackHandler = new GenericCsvImportHandler();
  }

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  /**
   * 格式族内全部子格式（12 已知来源 + 通用兜底）
   * 导入格式清单（ImportFormatCatalog）与防漂移护栏测试的单一数据源
   */
  getSubFormats(): FormatInfo[] {
    const formats: FormatInfo[] = [];
    for (const handler of this.family) {
      formats.push({
        formatId: handler.formatId,
        formatName: handler.formatName,
        extensions: [...handler.supportedExtensions]
      });
    }
    formats.push({
      formatId: this.fallbackHandler.formatId,
      formatName: this.fallbackHandler.formatName,
      extensions: [...this.fallbackHandler.supportedExtensions]
    });
    return formats;
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
    const bytes = new Uint8Array(fileContent.content);
    const detectedEncoding = CsvEncodingUtils.detect(bytes);
    const content = CsvEncodingUtils.decode(bytes, detectedEncoding);
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
      // 精准匹配未命中（多一列/少一列）→ 一律弹列映射向导人工确认，不静默按建议映射直导
      const preview = ImportWizardBridge.buildPreview(
        parseResult.rows, detectedFormatName, fileContent.content, detectedEncoding
      );
      const profile: ColumnMappingProfile | null =
        await ImportWizardBridge.getInstance().requestColumnMapping(preview);
      if (profile !== null) {
        // 用户在向导切换过编码时，须按该编码重新解码解析（与向导呈现的表头保持一致）
        const profileRows = this.resolveProfileRows(fileContent, profile, detectedEncoding, parseResult.rows);
        // 向导确认导入按通用 CSV 档案执行，上报兜底格式（成功提示用）
        ImportSessionInfo.getInstance().reportDetectedFormat(
          this.fallbackHandler.formatId, this.fallbackHandler.formatName
        );
        return this.fallbackHandler.importWithProfile(profileRows, profile);
      }
      // profile === null：无 UI 上下文可呈现向导（自动化/后台），回落通用建议映射直导
    }

    const finalTarget = target !== null ? target : this.fallbackHandler;
    // 上报最终执行导入的格式（成功提示文案用；forceWizard 已知格式也按 finalTarget 上报）
    ImportSessionInfo.getInstance().reportDetectedFormat(finalTarget.formatId, finalTarget.formatName);
    return finalTarget.importRows(parseResult.rows);
  }

  /**
   * 解析档案对应的导入行：编码与自动检测一致（或未指定）时复用已解析行，
   * 用户指定了不同编码时重新解码解析
   */
  private resolveProfileRows(
    fileContent: FileContentInfo,
    profile: ColumnMappingProfile,
    detectedEncoding: string,
    defaultRows: string[][]
  ): string[][] {
    if (profile.encoding === '' || profile.encoding === detectedEncoding) {
      return defaultRows;
    }
    const redecoded = CsvEncodingUtils.decode(new Uint8Array(fileContent.content), profile.encoding);
    const reparsed = new CsvParser().parse(redecoded);
    if (reparsed.rows.length === 0) {
      throw new ImportError(
        ImportExportErrorCode.FILE_EMPTY,
        ResourceManager.getString($r('app.string.import_export_file_empty'))
      );
    }
    return reparsed.rows;
  }
}
