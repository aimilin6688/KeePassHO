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
    const fileName = KdbxExportService.createFileName(FileUtils.getFileName(writeOptions.filePath), exportType);
    if (kdbx) {
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
  public static createFileName(fileName: string, exportType: ExportType, appendDate: boolean = true): string {
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