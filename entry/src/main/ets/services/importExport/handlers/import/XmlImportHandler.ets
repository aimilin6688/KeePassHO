import { KdbxGroup, Kdbx, KdbxCredentials, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { ResourceManager } from '../../../../common/utils';
import hilog from '@ohos.hilog';

const TAG = 'XmlImportHandler';
const DOMAIN = 0xFF00;

/**
 * XML 导入处理器
 */
export class XmlImportHandler implements IImportHandler {
  readonly supportedExtensions = ['.xml'];
  readonly formatName = 'XML';
  readonly formatId = 'XML';

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    const content = ByteUtils.bytesToString(fileContent.content);

    if (!content || content.trim().length === 0) {
      throw new ImportError(ImportExportErrorCode.FILE_EMPTY, ResourceManager.getString($r('app.string.import_export_file_empty')));
    }

    try {
      const kdbx = await Kdbx.loadXml(content, new KdbxCredentials(null));
      return kdbx.getDefaultGroup();
    } catch (error) {
      if (error instanceof ImportError) {
        throw error;
      }
      const errorMsg = error instanceof Error ? error.message : ResourceManager.getString($r('app.string.import_export_unknown_error'));
      hilog.error(DOMAIN, TAG, 'XML parse failed: %{public}s', errorMsg);
      throw new ImportError(
        ImportExportErrorCode.INVALID_FILE_FORMAT,
        ResourceManager.getString($r('app.string.import_export_parse_failed'))
      );
    }
  }
}
