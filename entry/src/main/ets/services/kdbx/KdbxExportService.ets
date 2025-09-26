import { ByteUtils, KdbxCredentials } from 'kdbxweb';
import DateUtils from '../../common/utils/DateUtils';
import { FilenameUtils } from '../../common/utils/FilenameUtils';
import { ExportType, FileContent, SaveKdbxParam } from '../TypeDefined';
import { KdbxCsvService } from './KdbxCsvService';
import { LocationInfo, LocationInterface, LocationMode, LocationParam } from '../beans/LocationParam';
import { FileService } from '../FileService';
import { CommonUtils } from '../../common/utils/CommonUtils';
import { KdbxFileManager } from './KdbxFileManager';
import { DataService } from '../DataService';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageType } from './interfaces';
import { LoadingDialog } from '../../components/loading/LoadingDialogUtils';

const DOMAIN = 0x0000;
const TAG = 'KdbxExportService';

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
      onLocation: async (locationInfo: LocationInfo) => {
        try {
          await KdbxExportService.handlerExport(locationInfo, exportType);
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'Export database error:' + e.message);
          LoadingDialog.showError(e.message);
        }
      }
    } as LocationInterface);
    CommonUtils.pushUrl({ url: 'pages/open/SelectLocation' });
  }

  /**
   * 处理导出
   * @param locationInfo
   */
  private static async handlerExport(locationInfo: LocationInfo, exportType: ExportType) {
    try {
      let existsError: Error | undefined;
      // 弹出导出进度提示信息
      LoadingDialog.showLoading($r("app.string.export_saving"));
      const existsFile = locationInfo.storageType !== StorageType.LOCAL && await KdbxFileManager.of(locationInfo).exists(locationInfo.filePath)
        .catch((error: Error) => {
          hilog.error(DOMAIN, TAG, 'Exists file stateType:%{public}s filePath:%{public}s error:%{public}s', locationInfo.storageType, locationInfo.filePath,
            error.message);
          existsError = error;
          LoadingDialog.hideLoading();
          LoadingDialog.showError(error.message);
        });
      if (existsError) {
        return;
      }
      if (existsFile) {
        CommonUtils.showDialog(CommonUtils.getExistsFileDialog()).then(async result => {
          if (result.index === 1) {
            await KdbxExportService.doExport(locationInfo, exportType);
          } else {
            CommonUtils.back({ url: "pages/setting/SettingDatabase" });
          }
        });
      } else {
        await KdbxExportService.doExport(locationInfo, exportType);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Export database error:' + error.message);
      LoadingDialog.hideLoading();
      LoadingDialog.showError(error.message);
    }
  }

  /**
   * 执行数据库导出
   * @param locationInfo
   * @param exportType
   */
  private static async doExport(locationInfo: LocationInfo, exportType: ExportType) {
    LoadingDialog.showLoading($r("app.string.handling"));
    return await DataService.saveKdbx({ kdbx: FileService.getDatabase(), exportType: exportType, locationInfo: locationInfo }).then(() => {
      LoadingDialog.hideLoading();
      LoadingDialog.showSuccess($r("app.string.export_success"));
      CommonUtils.back({ url: "pages/setting/SettingDatabase" });
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'Export database error:' + e.message);
      LoadingDialog.hideLoading();
      LoadingDialog.showError(e.message);
    });
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