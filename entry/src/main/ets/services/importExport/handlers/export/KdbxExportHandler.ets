import { Kdbx } from 'kdbxweb';
import { IExportHandler } from '../../interfaces/IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';

/**
 * KDBX 导出处理器
 */
export class KdbxExportHandler implements IExportHandler {
  readonly supportedExtensions = ['.kdbx'];
  readonly formatName = 'KDBX';
  readonly formatId = 'KDBX';
  readonly defaultFileName = 'export.kdbx';

  canHandle(formatId: string): boolean {
    return this.formatId === formatId;
  }

  async export(database: Kdbx): Promise<ArrayBuffer> {
    try {
      return await database.save();
    } catch (error) {
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        `KDBX 导出失败: ${error instanceof Error ? error.message : '未知错误'}`
      );
    }
  }
}
