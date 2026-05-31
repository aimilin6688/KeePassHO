import { Kdbx, KdbxCredentials, ByteUtils } from 'kdbxweb';
import { IExportHandler } from '../IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';

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
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        `密钥文件生成失败: ${error instanceof Error ? error.message : '未知错误'}`
      );
    }
  }
}
