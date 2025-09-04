import { CommonUtils } from '../../common/utils/CommonUtils';
import { LocationInfo, LocationInterface, LocationMode, LocationParam } from '../beans/LocationParam';
import { ExportType } from '../TypeDefined';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KdbxFileManager } from './KdbxFileManager';
import { FilenameUtils } from '../../common/utils/FilenameUtils';
import { ByteUtils, Kdbx, KdbxCredentials } from 'kdbxweb';
import { FileService } from '../FileService';
import KdbxUtils from '../../common/utils/KdbxUtils';
import { ErrorCodes, KeePassHoError } from '../error/KeepassHoError';

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
          CommonUtils.showToast({ message: e.message });
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
      CommonUtils.showToast({ message: $r("app.string.file_not_exists") });
      return;
    }
    const fileExt = FilenameUtils.getFileExt(locationInfo.filePath);
    // 检查格式
    if (!KdbxImportService.isSupportType(fileExt)) {
      CommonUtils.showToast({ message: $r("app.string.import_not_support_type") });
      return;
    }
    // 转换为导入数据库
    const importKdbx: Kdbx = await KdbxImportService.toKdbx(locationInfo, fileExt);
    // 合并数据库
    const srcKdbx: Kdbx = FileService.getDatabase();
    srcKdbx.merge(importKdbx);
    KdbxUtils.saveDatabase({
      onSuccess: () => {
        CommonUtils.showToast({ message: $r("app.string.import_success") });
        CommonUtils.back({ url: "pages/SettingDatabase" });
      },
      onError: (message) => {
        CommonUtils.showToast(message);
      },
    });
  }

  /**
   * 解析文件为数据库文件
   */
  private static toKdbx(locationInfo: LocationInfo, fileExt: string): Kdbx | PromiseLike<Kdbx> {
    if (fileExt.toUpperCase() === ExportType.XML) {
      return KdbxFileManager.of(locationInfo).read(locationInfo.filePath).then(result => {
        return Kdbx.loadXml(ByteUtils.bytesToString(result.content), new KdbxCredentials(null));
      }).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Failed to parse XML file: %{public}s', error.message);
        throw new KeePassHoError(ErrorCodes.FILE_IMPORT_ERROR, error.message);
      });
    }
    if (fileExt.toUpperCase() === ExportType.CSV) {
    }
    hilog.error(DOMAIN, TAG, 'Unsupported file type: %{public}s', fileExt);
    throw new KeePassHoError(ErrorCodes.FILE_TYPE_NOT_SUPPORT);
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