import { ByteUtils, KdbxCredentials } from 'kdbxweb';
import DateUtils from '../../common/utils/DateUtils';
import { FilenameUtils } from '../../common/utils/FilenameUtils';
import { ExportType, FileContent, SaveKdbxParam } from '../TypeDefined';
import { KdbxCsvService } from './KdbxCsvService';
import { LocationInfo, LocationInterface, LocationMode, LocationParam } from '../beans/LocationParam';
import { FileService } from '../FileService';
import { DataService } from '../DataService';
import { CommonUtils } from '../../common/utils/CommonUtils';

export class KdbxExportService {
  /**
   * 导出数据库
   * @param router
   * @param exportType
   */
  public static exportDatabase(exportType: ExportType) {
    LocationParam.of({
      mode: LocationMode.SAVE,
      fileName: KdbxExportService.createFileName(FileService.getDbFileParam().fileName, exportType, true),
      onLocation: (locationInfo: LocationInfo) => {
        DataService.saveKdbx({ kdbx: FileService.getDatabase(), exportType: exportType, locationInfo: locationInfo }).then(() => {
          CommonUtils.showToast({ message: $r("app.string.save_success") });
          CommonUtils.back({ url: "pages/SettingDatabase" });
        })
      }
    } as LocationInterface);
    CommonUtils.pushUrl({ url: 'pages/open/SelectLocation' });
  }


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
      fileName = FilenameUtils.replaceExt(fileName, ".kdbx");
    } else if (ExportType.XML === exportType) {
      fileName = FilenameUtils.replaceExt(fileName, ".xml");
    } else if (ExportType.CSV === exportType) {
      fileName = FilenameUtils.replaceExt(fileName, ".csv");
    }
    if (appendDate && fileName !== nowTime) {
      fileName = FilenameUtils.fileNameAppendDate(fileName);
    }
    return fileName;
  }
}