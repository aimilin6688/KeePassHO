import { KdbxGroup, Kdbx, KdbxCredentials, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../../interfaces/IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';

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
      throw new ImportError(ImportExportErrorCode.FILE_EMPTY, '文件为空');
    }

    try {
      const kdbx = await Kdbx.loadXml(content, new KdbxCredentials(null));
      return kdbx.getDefaultGroup();
    } catch (error) {
      if (error instanceof ImportError) {
        throw error;
      }
      throw new ImportError(
        ImportExportErrorCode.INVALID_FILE_FORMAT,
        `XML 解析失败: ${error instanceof Error ? error.message : '未知错误'}`
      );
    }
  }
}
