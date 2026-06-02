import { Kdbx, ByteUtils } from 'kdbxweb';
import { IExportHandler } from '../IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { ResourceManager } from '../../../../common/utils';
import hilog from '@ohos.hilog';

const TAG = 'XmlExportHandler';
const DOMAIN = 0xFF00;

/**
 * XML 导出处理器
 */
export class XmlExportHandler implements IExportHandler {
  readonly supportedExtensions = ['.xml'];
  readonly formatName = 'XML';
  readonly formatId = 'XML';
  readonly defaultFileName = 'export.xml';

  canHandle(formatId: string): boolean {
    return this.formatId === formatId;
  }

  async export(database: Kdbx): Promise<ArrayBuffer> {
    try {
      const xmlContent = await database.saveXml(true, true);
      return ByteUtils.stringToBuffer(xmlContent);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : ResourceManager.getString($r('app.string.import_export_unknown_error'));
      hilog.error(DOMAIN, TAG, 'XML export failed: %{public}s', errorMsg);
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        ResourceManager.getString($r('app.string.import_export_export_failed'))
      );
    }
  }
}
