import { ByteUtils } from 'kdbxweb';
import FileUtils from '../../common/utils/FIleUtils';
import { ExportType } from '../../pages/SettingDatabase';
import { FileService } from '../FileService';
import { DbFileParam, ExportFileParam } from '../TypeDefined';
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
    return Promise.reject();
  }

  /**
   * 创建文件名
   * @param fileName
   * @param exportType
   */
  public static createFileName(fileName: string, exportType: ExportType): string {
    if (ExportType.KDBX === exportType) {
      return FileUtils.replaceExt(fileName, ".kdbx");
    }
    if (ExportType.XML === exportType) {
      return FileUtils.replaceExt(fileName, ".xml");
    }
    if (ExportType.CSV === exportType) {
      return FileUtils.replaceExt(fileName, ".csv");
    }
    return fileName;
  }
}