import { LocationInfo, LocationInterface, LocationMode, LocationParam } from '../beans/LocationParam';
import { ExportType } from '../TypeDefined';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KdbxFileManager } from './KdbxFileManager';
import { ByteUtils, Kdbx, KdbxCredentials, KdbxGroup } from 'kdbxweb';
import { FileService } from '../FileService';
import { KdbxUtils, CommonUtils, FilenameUtils } from '../../common/utils';
import { ErrorCodes, KeePassHoError } from '../error/KeepassHoError';
import { KdbxCsvService } from './KdbxCsvService';
import { ToastSaveDatabaseCallback } from '../../workers/callback/ToastSaveDatabaseCallback';
import { LoadingDialog } from '../../components/loading/LoadingDialogUtils';

const DOMAIN = 0x0000;
const TAG = 'KdbxImportService';

export class KdbxImportService {
  private static readonly EXPORT_TYPES = ['.kdbx', '.xml', '.csv'];

  /**
   * 导入数据库文件
   * @param inputType
   */
  public static importDatabase(inputType?: ExportType) {
    LocationParam.of({
      mode: LocationMode.SELECT,
      fileSuffix: KdbxImportService.createFileSuffix(inputType),
      onLocation: (locationInfo: LocationInfo) => {
        try {
          KdbxImportService.handlerImport(locationInfo);
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'Import database error:' + e.message);
          CommonUtils.showToast(e.message);
        }
      }
    } as LocationInterface);
    CommonUtils.pushUrl({ url: 'pages/open/SelectLocation' });
  }

  /**
   * 处理导入
   * @param locationInfo 位置信息
   */
  private static async handlerImport(locationInfo: LocationInfo) {
    const exists = await KdbxFileManager.of(locationInfo).exists(locationInfo.filePath);
    // 文件不存在
    if (!exists) {
      CommonUtils.showToast($r("app.string.file_not_exists"));
      return;
    }
    const fileExt = FilenameUtils.getFileExt(locationInfo.filePath);
    // 检查格式
    if (!KdbxImportService.isSupportType(fileExt)) {
      CommonUtils.showToast($r("app.string.import_not_support_type"));
      return;
    }
    // 转换为导入数据库
    const newGroup: KdbxGroup = await KdbxImportService.toKdbxGroup(locationInfo, fileExt);
    const rootGroup = FileService.getDatabase().getDefaultGroup();
    // 添加分组信息
    if (newGroup.groups && newGroup.groups.length > 0) {
      for (let index = 0; index < newGroup.groups.length; index++) {
        const addGroup = newGroup.groups[index];
        addGroup.parentGroup = rootGroup;
        rootGroup.groups.push(addGroup);
      }
    }
    // 添加条目信息
    if (newGroup.entries && newGroup.entries.length > 0) {
      for (let index = 0; index < newGroup.entries.length; index++) {
        const addEntry = newGroup.entries[index];
        addEntry.parentGroup = rootGroup;
        rootGroup.entries.push(addEntry);
      }
    }
    hilog.debug(DOMAIN, TAG, 'Import database group:%{public}d, entry:%{public}d', newGroup.groups.length, newGroup.entries.length);
    KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
      onSuccess: () => {
        CommonUtils.back({ url: "pages/setting/SettingDatabase" });
      }
    }));
  }

  /**
   * 解析文件为数据库文件
   */
  private static toKdbxGroup(locationInfo: LocationInfo, fileExt: string): KdbxGroup | PromiseLike<KdbxGroup> {
    return KdbxFileManager.of(locationInfo).read(locationInfo.filePath).then(result => {
      // xml格式
      if (fileExt.toUpperCase() === ExportType.XML) {
        return Kdbx.loadXml(ByteUtils.bytesToString(result.content), new KdbxCredentials(null)).then(result => {
          return result.getDefaultGroup();
        }).catch((error: Error) => {
          if (error instanceof KeePassHoError) {
            throw error;
          }
          throw new KeePassHoError(ErrorCodes.FILE_IMPORT_ERROR, error.message);
        });
      }

      // csv格式
      if (fileExt.toUpperCase() === ExportType.CSV) {
        return KdbxCsvService.import(result).catch((error: Error) => {
          if (error instanceof KeePassHoError) {
            throw error;
          }
          throw new KeePassHoError(ErrorCodes.FILE_IMPORT_ERROR, error.message);
        });
      }
      return new KdbxGroup();
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to import: %{public}s', error.message);
      CommonUtils.showToast(error.message);
      if (error instanceof KeePassHoError) {
        throw error;
      }
      throw new KeePassHoError(ErrorCodes.FILE_IMPORT_ERROR, error.message);
    });
  }

  /**
   * 导入文件的后缀格式
   * @param locationInfo 文件位置信息
   */
  private static isSupportType(filenameExt: string): boolean {
    if (!filenameExt) {
      return false;
    }
    filenameExt = filenameExt.startsWith(".") ? filenameExt : "." + filenameExt;
    return KdbxImportService.EXPORT_TYPES.indexOf(filenameExt) !== -1;
  }

  /**
   * 创建文件后缀
   * @param inputType
   */
  private static createFileSuffix(inputType?: ExportType) {
    if (inputType === ExportType.KDBX) {
      return ['.kdbx'];
    }
    if (inputType === ExportType.XML) {
      return ['.xml'];
    }
    if (inputType === ExportType.CSV) {
      return ['.csv'];
    }
    return KdbxImportService.EXPORT_TYPES;
  }
}