import { Kdbx } from 'kdbxweb';
import { IExportHandler } from '../IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { ResourceManager } from '../../../../common/utils';
import hilog from '@ohos.hilog';

const TAG = 'KdbxExportHandler';
const DOMAIN = 0xFF00;

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
      const errorMsg = error instanceof Error ? error.message : ResourceManager.getString($r('app.string.import_export_unknown_error'));
      hilog.error(DOMAIN, TAG, 'KDBX export failed: %{public}s', errorMsg);
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        ResourceManager.getString($r('app.string.import_export_export_failed'))
      );
    }
  }
}
