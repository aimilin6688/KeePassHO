import { CommonUtils } from '../../common/utils/CommonUtils';
import { LocationInfo, LocationInterface, LocationMode, LocationParam } from '../beans/LocationParam';
import { ExportType } from '../TypeDefined';

export class KdbxImportService {
  /**
   * 导入数据库文件
   * @param inputType
   */
  public static importDatabase(inputType?: ExportType) {
    LocationParam.of({
      mode: LocationMode.SELECT,
      fileSuffix: KdbxImportService.createFileSuffix(inputType),
      onLocation: (locationInfo: LocationInfo) => {

      }
    } as LocationInterface);
    CommonUtils.pushUrl({ url: 'pages/open/SelectLocation' });
  }

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
    return ['.kdbx', '.xml', '.csv'];
  }
}