import { ByteUtils, KdbxCredentials } from 'kdbxweb';
import DateUtils from '../../common/utils/DateUtils';
import FileUtils from '../../common/utils/FIleUtils';
import { ExportType, FileContent, SaveKdbxParam } from '../TypeDefined';
import { KdbxCsvService } from './KdbxCsvService';

export class KdbxExportService {
  /**
   * 创建导出文件
   * @param exportType 导出类型
   */
  public static getFileContent(param: SaveKdbxParam): Promise<FileContent> {
    const kdbx = param.kdbx;
    const exportType = param.exportType;
    const location = param.locationInfo;
    if (kdbx) {
      if (ExportType.KDBX === exportType) {
        return kdbx.save().then(result => {
          return new FileContent(location.filePath, result);
        });
      }
      if (ExportType.XML === exportType) {
        return kdbx.saveXml(true, false).then(result => {
          return new FileContent(location.filePath, ByteUtils.stringToBuffer(result));
        });
      }
      if (ExportType.CSV === exportType) {
        return KdbxCsvService.export(kdbx).then(result => {
          return new FileContent(location.filePath, result);
        })
      }
    }
    if (ExportType.CREATE_KEY === exportType) {
      return KdbxCredentials.createRandomKeyFile().then(result => {
        return new FileContent(location.filePath, ByteUtils.bytesToBuffer(result));
      });
    }
    return Promise.reject();
  }

  /**
   * 创建文件名
   * @param fileName
   * @param exportType
   */
  public static createFileName(fileName: string, exportType: ExportType, appendDate: boolean | undefined = true): string {
    const nowTime = DateUtils.getCurrentDate();
    fileName = fileName || nowTime;
    if (ExportType.KDBX === exportType) {
      fileName = FileUtils.replaceExt(fileName, ".kdbx");
    } else if (ExportType.XML === exportType) {
      fileName = FileUtils.replaceExt(fileName, ".xml");
    } else if (ExportType.CSV === exportType) {
      fileName = FileUtils.replaceExt(fileName, ".csv");
    }
    if (appendDate && fileName !== nowTime) {
      fileName = FileUtils.fileNameAppendDate(fileName);
    }
    return fileName;
  }
}