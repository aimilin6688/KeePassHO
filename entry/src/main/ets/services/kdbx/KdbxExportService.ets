import { ByteUtils, KdbxCredentials } from 'kdbxweb';
import FileUtils from '../../common/utils/FIleUtils';
import { FileService } from '../FileService';
import { DbFileParam, ExportFileParam, ExportType } from '../TypeDefined';
import { KdbxCsvService } from './KdbxCsvService';

export class KdbxExportService {
  /**
   * 创建导出文件
   * @param exportType 导出类型
   */
  public static createExportFile(exportType: ExportType): Promise<ExportFileParam> {
    const dbFile: DbFileParam = FileService.getDbFileParam();
    const kdbx = dbFile.database;
    const fileName = KdbxExportService.createFileName(dbFile.fileName, exportType);
    if (ExportType.KDBX === exportType) {
      return kdbx.save().then(result => {
        return new ExportFileParam(fileName, result);
      });
    }
    if (ExportType.XML === exportType) {
      return kdbx.saveXml(true, false).then(result => {
        return new ExportFileParam(fileName, ByteUtils.stringToBuffer(result));
      });
    }
    if (ExportType.CSV === exportType) {
      return KdbxCsvService.export(kdbx).then(result => {
        return new ExportFileParam(fileName, result);
      })
    }
    if (ExportType.CREATE_KEY === exportType) {
      return KdbxCredentials.createRandomKeyFile().then(result => {
        return new ExportFileParam(fileName, ByteUtils.bytesToBuffer(result));
      });
    }
    return Promise.reject();
  }

  /**
   * 创建文件名
   * @param fileName
   * @param exportType
   */
  public static createFileName(fileName: string, exportType: ExportType): string {
    fileName = fileName || "database";
    if (ExportType.KDBX === exportType) {
      fileName = FileUtils.replaceExt(fileName, ".kdbx");
    } else if (ExportType.XML === exportType) {
      fileName = FileUtils.replaceExt(fileName, ".xml");
    } else if (ExportType.CSV === exportType) {
      fileName = FileUtils.replaceExt(fileName, ".csv");
    }
    return FileUtils.fileNameAppendDate(fileName);
  }
}