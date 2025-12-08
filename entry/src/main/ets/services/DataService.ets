import { SaveKdbxParam } from './TypeDefined';
import { Router } from '@kit.ArkUI';
import { RecentFilesService } from './RecentFilesService';
import { KdbxExportService } from './kdbx/KdbxExportService';
import { KdbxFileManager } from './kdbx/KdbxFileManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ErrorCodes, KeePassHoError } from './error/KeepassHoError';
import { LocationInfo, LocationMode, LocationParam } from './beans/LocationParam';
import { DateUtils, CommonUtils } from '../common/utils';
import { ByteUtils, KdbxCredentials } from 'kdbxweb';
import { LoadingDialog } from '../components/loading/LoadingDialogUtils';
import { SettingsService } from './SettingsService';

const DOMAIN = 0x0000;
const TAG = 'DataService';

/**
 * 数据服务
 */
export class DataService {
  /**
   * 保存数据库
   */
  public static saveKdbx(param: SaveKdbxParam): Promise<void> {
    return KdbxExportService.getFileContent(param).then(result => {
      LoadingDialog.showLoading($r("app.string.handling"));
      const location = param.locationInfo;
      return new KdbxFileManager(location.storageType, location.storageConfig).write(location.filePath, result.content);
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to save kdbx file: %{public}s, error: %{public}s', param.locationInfo.filePath, error.message);
      LoadingDialog.hideLoading();
      LoadingDialog.showError(error.message);
    });
  }

  /**
   * 保存密钥
   */
  public static saveKey(onSuccess: (locationInfo: LocationInfo) => void, onError?: (error: Error) => void) {
    LocationParam.of({
      mode: LocationMode.SAVE,
      fileName: `key_${DateUtils.getCurrentDate()}.key`,
      onLocation: (locationInfo: LocationInfo) => {
        KdbxCredentials.createRandomKeyFile().then(keyContent => {
          KdbxFileManager.of(locationInfo).write(locationInfo.filePath, ByteUtils.bytesToBuffer(keyContent)).then(async () => {
            onSuccess(locationInfo);
          }).catch((error: Error) => {
            hilog.error(DOMAIN, TAG, `Failed to create new key file: ${error.message}`, error.stack);
            CommonUtils.showToast($r('app.string.save_failed_message', error.message));
            onError && onError(error);
          });
        })
      }
    });
  }

  /**
   * 选择数据库
   */
  public static selectKdbx(router: Router) {
    const fileSuffix: Array<string> = [];
    if (SettingsService.getSync(SettingsService.KEY_APP_LIMIT_DB_EXT, SettingsService.KEY_APP_LIMIT_DB_EXT_DEFAULT)) {
      fileSuffix.push('kdbx');
    }
    LocationParam.of({
      mode: LocationMode.SELECT,
      fileSuffix: fileSuffix,
      onLocation: (locationInfo: LocationInfo) => {
        DataService.toPasswordPage(router, locationInfo);
      }
    });
  }

  /**
   * 跳转到数据库打开页面
   * @param router
   * @param param
   */
  public static toPasswordPage(router: Router, locationInfo: LocationInfo): void {
    // 添加到最近打开的文件列表
    RecentFilesService.addRecentFile({
      filePath: locationInfo.filePath,
      fileName: locationInfo.fileName,
      storageType: locationInfo.storageType,
      storageConfig: locationInfo.storageConfig
    }).then(() => {
      // 导航到密码输入页面
      router.pushUrl({
        url: 'pages/Password',
        params: {
          filePath: locationInfo.filePath
        }
      });
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to read data file: %{public}s, error: %{public}s', locationInfo.filePath, error.message);
      if (error instanceof KeePassHoError) {
        // 本地文件创建之后没有读权限
        if (error.code === ErrorCodes.FILE_NOT_PERMISSION) {
          router.pushUrl({ url: "pages/Index", params: { "notRedirect": true } });
        }
      } else {
        CommonUtils.showToast($r('app.string.open_failed', error.message));
      }
    });
  }
}