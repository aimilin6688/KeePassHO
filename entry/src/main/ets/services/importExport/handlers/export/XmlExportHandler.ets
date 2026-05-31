import { Kdbx, ByteUtils } from 'kdbxweb';
import { IExportHandler } from '../IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';

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
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        `XML 导出失败: ${error instanceof Error ? error.message : '未知错误'}`
      );
    }
  }
}
