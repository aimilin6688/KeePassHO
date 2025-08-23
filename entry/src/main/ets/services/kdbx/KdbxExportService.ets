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
    if (ExportType.KDBX === exportType) {
      return kdbx.save().then(result => {
        const fileName = FileUtils.replaceExt(dbFile.fileName, ".kdbx");
        return new ExportFileParam(fileName, result);
      });
    }
    if (ExportType.XML === exportType) {
      return kdbx.saveXml(true, false).then(result => {
        const fileName = FileUtils.replaceExt(dbFile.fileName, ".xml");
        return new ExportFileParam(fileName, ByteUtils.stringToBuffer(result));
      });
    }
    if (ExportType.CSV === exportType) {
      return KdbxCsvService.export(kdbx).then(result => {
        const fileName = FileUtils.replaceExt(dbFile.fileName, ".csv");
        return new ExportFileParam(fileName, result);
      })
    }
    return Promise.reject();
  }
}