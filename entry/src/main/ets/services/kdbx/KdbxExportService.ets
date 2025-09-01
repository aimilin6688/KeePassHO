import { ByteUtils, KdbxCredentials } from 'kdbxweb';
import FileUtils from '../../common/utils/FIleUtils';
import { FileService } from '../FileService';
import { ExportDataParam, ExportFileParam, ExportType, WriteDataOptions } from '../TypeDefined';
import { KdbxCsvService } from './KdbxCsvService';

export class KdbxExportService {
  /**
   * 创建导出文件
   * @param exportType 导出类型
   */
  public static createExportFile(writeOptions: WriteDataOptions): Promise<ExportFileParam> {
    const param: ExportDataParam = FileService.getExportDataParam();
    const kdbx = param.database;
    const exportType = param.exportType;
    if (kdbx) {
      if (ExportType.KDBX === exportType) {
        return kdbx.save().then(result => {
          return new ExportFileParam(writeOptions.filePath, result);
        });
      }
      if (ExportType.XML === exportType) {
        return kdbx.saveXml(true, false).then(result => {
          return new ExportFileParam(writeOptions.filePath, ByteUtils.stringToBuffer(result));
        });
      }
      if (ExportType.CSV === exportType) {
        return KdbxCsvService.export(kdbx).then(result => {
          return new ExportFileParam(writeOptions.filePath, result);
        })
      }
    }
    if (ExportType.CREATE_KEY === exportType) {
      return KdbxCredentials.createRandomKeyFile().then(result => {
        return new ExportFileParam(writeOptions.filePath, ByteUtils.bytesToBuffer(result));
      });
    }
    return Promise.reject();
  }

  /**
   * 创建文件名
   * 1、优先使用导出设值的文件名
   * 2、使用数据库文件名
   */
  public static createFileName() {
    const exportParam = FileService.getExportDataParam();
    let fileName = exportParam.fileName;
    if (!fileName) {
      fileName = FileService.getDbFileParam().fileName;
    }
    if (exportParam?.exportType) {
      fileName = KdbxExportService.createExportFileName(fileName, exportParam?.exportType, exportParam?.fileNameAppendDate);
    }
    return fileName;
  }

  /**
   * 创建文件名
   * @param fileName
   * @param exportType
   */
  private static createExportFileName(fileName: string, exportType: ExportType, appendDate: boolean | undefined = true): string {
    fileName = fileName || "database";
    if (ExportType.KDBX === exportType) {
      fileName = FileUtils.replaceExt(fileName, ".kdbx");
    } else if (ExportType.XML === exportType) {
      fileName = FileUtils.replaceExt(fileName, ".xml");
    } else if (ExportType.CSV === exportType) {
      fileName = FileUtils.replaceExt(fileName, ".csv");
    }
    if (appendDate) {
      fileName = FileUtils.fileNameAppendDate(fileName);
    }
    return fileName;
  }
}