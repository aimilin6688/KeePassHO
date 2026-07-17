import { Kdbx, KdbxCredentials, ByteUtils } from 'kdbxweb';
import { IExportHandler } from '../IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { ResourceManager } from '../../../../common/utils';
import hilog from '@ohos.hilog';

const TAG = 'KeyFileExportHandler';
const DOMAIN = 0xFF00;

/**
 * 密钥文件导出处理器
 */
export class KeyFileExportHandler implements IExportHandler {
  readonly supportedExtensions = ['.key', '.keyx'];
  readonly formatName = 'Key File';
  readonly formatId = 'KEY_FILE';
  readonly defaultFileName = 'keyfile.key';

  canHandle(formatId: string): boolean {
    return this.formatId === formatId;
  }

  async export(database: Kdbx): Promise<ArrayBuffer> {
    try {
      const keyBytes = await KdbxCredentials.createRandomKeyFile();
      return ByteUtils.bytesToBuffer(keyBytes);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : ResourceManager.getString($r('app.string.import_export_unknown_error'));
      hilog.error(DOMAIN, TAG, 'Key file generation failed: %{public}s', errorMsg);
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        ResourceManager.getString($r('app.string.import_export_export_failed'))
      );
    }
  }
}
