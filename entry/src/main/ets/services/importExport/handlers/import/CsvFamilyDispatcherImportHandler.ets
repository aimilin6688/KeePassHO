import { KdbxGroup, ByteUtils } from 'kdbxweb';
import { CsvParser } from '../../csvimport/CsvParser';
import { FileContentInfo } from '../../../../storage';
import { IImportHandler } from '../IImportHandler';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { ResourceManager } from '../../../../common/utils';
import { BaseCsvImportHandler } from './BaseCsvImportHandler';
import { LastPassCsvImportHandler } from './LastPassCsvImportHandler';
import { BitwardenCsvImportHandler } from './BitwardenCsvImportHandler';
import { ProtonPassCsvImportHandler } from './ProtonPassCsvImportHandler';
import { DashlaneCsvImportHandler } from './DashlaneCsvImportHandler';
import { OnePasswordCsvImportHandler } from './OnePasswordCsvImportHandler';
import { FirefoxCsvImportHandler } from './FirefoxCsvImportHandler';
import { ChromeCsvImportHandler } from './ChromeCsvImportHandler';
import { GenericCsvImportHandler } from './GenericCsvImportHandler';

/** 嗅探分发置信度阈值 */
const SNIFF_DISPATCH_THRESHOLD = 70;
/** 嗅探采样数据行数 */
const SAMPLE_ROW_COUNT = 5;

/**
 * CSV 导入格式族调度器
 * 占据 '.csv' / 'CSV' 路由键，按表头嗅探将导入分发到
 * LastPass / Bitwarden / Proton Pass / Dashlane / 1Password / Firefox / Chrome / 通用 CSV 处理器
 */
export class CsvFamilyDispatcherImportHandler implements IImportHandler {
  readonly supportedExtensions: string[] = ['.csv'];
  readonly formatId = 'CSV';
  readonly formatName = 'CSV';

  /** 格式族（按特异性从高到低排序，两两冲突已由特征列/排除列消歧） */
  private readonly family: BaseCsvImportHandler[];
  private readonly fallbackHandler: GenericCsvImportHandler;

  constructor() {
    this.family = [
      new LastPassCsvImportHandler(),
      new BitwardenCsvImportHandler(),
      new ProtonPassCsvImportHandler(),
      new DashlaneCsvImportHandler(),
      new OnePasswordCsvImportHandler(),
      new FirefoxCsvImportHandler(),
      new ChromeCsvImportHandler()
    ];
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

    let target: BaseCsvImportHandler = this.fallbackHandler;
    for (const handler of this.family) {
      if (handler.sniff(headerRow, sampleRows) >= SNIFF_DISPATCH_THRESHOLD) {
        target = handler;
        break;
      }
    }
    return target.importRows(parseResult.rows);
  }
}
