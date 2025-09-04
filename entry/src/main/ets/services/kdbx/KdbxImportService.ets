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
      fileSuffix: ['.kdbx', '.xml', '.csv'],
      onLocation: (locationInfo: LocationInfo) => {
        
      }
    } as LocationInterface);
    CommonUtils.pushUrl({ url: 'pages/open/SelectLocation' });
  }
}