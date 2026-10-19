import { SaveKdbxParam, ExportType, FileContent, RecentFile } from './TypeDefined';
import { RecentFilesService } from './RecentFilesService';
import { KdbxFileManager } from './kdbx/KdbxFileManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ErrorCodes, KeePassHoError } from './error/KeepassHoError';
import { LocationInfo, LocationMode, LocationParam } from './beans/LocationParam';
import { DateUtils, CommonUtils, NavigationManager, StorageNavigation } from '../common/utils';
import { ByteUtils, KdbxCredentials } from 'kdbxweb';
import { LoadingDialog } from '../components/loading/LoadingDialogUtils';
import { SettingsService } from './SettingsService';
import { CsvExportHandler } from './importExport/handlers/export/CsvExportHandler';
import { PageConstants } from '../common/constants/PageConstants';
import { Constants } from '../common/constants/Constants';
import { StorageType } from '../storage';

const DOMAIN = 0x0000;
const TAG = 'DataService';

// 定义参数接口
interface PasswordParam {
  filePath: string;
  // 'add' = 添加模式（切换面板「打开其他数据库」中继）：解锁后保留多库注册表
  openMode?: string;
  // 子库管理页「选择文件」中继：解锁成功后把该库登记为指定父库的子库（AutoOpen 条目）
  addChildParent?: string;
}

interface IndexParam {
  notRedirect: boolean;
}

// 重新编辑连接配置导航参数：配置页按 filePath 从最近记录解析原配置预填表单
interface ReEditParam {
  filePath: string;
}

/**
 * 数据服务
 */
export class DataService {
  /**
   * 保存数据库
   */
  public static saveKdbx(param: SaveKdbxParam): Promise<void> {
    return DataService.getFileContent(param).then(result => {
      LoadingDialog.showLoading($r("app.string.handling"));
      const location = param.locationInfo;
      return new KdbxFileManager(location.storageType, location.storageConfig).write(location.filePath, result.content);
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to save kdbx file: %{public}s, error: %{public}s', param.locationInfo.filePath, error.message);
      LoadingDialog.hideLoading();
      CommonUtils.showToast(error.message);
      throw error;
    });
  }

  /**
   * 创建导出文件内容
   * @param param 保存参数
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
        return kdbx.saveXml(true, true).then(result => {
          return new FileContent(location.filePath, ByteUtils.stringToBuffer(result));
        });
      }
      if (ExportType.CSV === exportType) {
        // 使用新的导出处理器
        const handler = new CsvExportHandler();
        return handler.export(kdbx).then(result => {
          return new FileContent(location.filePath, result);
        });
      }
    }
    if (ExportType.CREATE_KEY === exportType) {
      return KdbxCredentials.createRandomKeyFile().then(result => {
        return new FileContent(location.filePath, ByteUtils.bytesToBuffer(result));
      });
    }
    return Promise.reject(new Error('Unsupported export type'));
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
   * @param openMode 添加模式中继（'add'）：透传给解锁页，解锁后保留多库注册表
   * @param addChildParent 子库管理页中继（父库 IocKey）：解锁成功后把该库登记为指定父库的子库
   */
  public static selectKdbx(openMode?: string, addChildParent?: string) {
    const fileSuffix: Array<string> = [];
    if (SettingsService.getSync(SettingsService.KEY_APP_LIMIT_DB_EXT, SettingsService.KEY_APP_LIMIT_DB_EXT_DEFAULT)) {
      fileSuffix.push('kdbx');
    }
    LocationParam.of({
      mode: LocationMode.SELECT,
      fileSuffix: fileSuffix,
      onLocation: (locationInfo: LocationInfo) => {
        DataService.toPasswordPage(locationInfo, openMode, addChildParent);
      }
    });
  }

  /**
   * 配置解密失败后的 UI 引导入口：跳转到对应存储的连接配置页重新编辑连接信息。
   * 复用打开数据库的选择流程（选择模式 + kdbx 后缀）：用户重新填写配置并选中同一文件后，
   * toPasswordPage 会以新配置覆盖同路径的最近记录，即完成修复。
   * 传入 filePath 时作为导航参数带给配置页，页面按路径从最近记录解析原配置预填表单。
   * @param storageType 存储类型
   * @param filePath 文件路径（URL）
   */
  public static reEditStorageConfig(storageType: StorageType, filePath?: string): void {
    DataService.selectKdbx();
    const pageName: string = StorageNavigation.getConfigPageName(storageType);
    if (pageName === '') {
      hilog.warn(DOMAIN, TAG, 'No config page for storage type: %{public}s, fallback to SelectLocation', storageType);
      NavigationManager.getInstance().navigateTo(PageConstants.PAGE_SELECT_LOCATION);
      return;
    }
    const reEditParam: ReEditParam = { filePath: filePath ?? '' };
    NavigationManager.getInstance().navigateTo(pageName, reEditParam);
  }

  /**
   * 跳转到数据库打开页面
   * @param locationInfo 位置信息
   * @param openMode 添加模式中继（'add'）：解锁后保留多库注册表，仅追加新库
   * @param addChildParent 子库管理页中继（父库 IocKey）：解锁成功后把该库登记为指定父库的子库（AutoOpen 条目）
   */
  public static toPasswordPage(locationInfo: LocationInfo, openMode?: string, addChildParent?: string): void {
    // 添加到最近打开的文件列表
    const recentFile: RecentFile = {
      filePath: locationInfo.filePath,
      fileName: locationInfo.fileName,
      storageType: locationInfo.storageType,
      storageConfig: locationInfo.storageConfig
    };
    RecentFilesService.addRecentFile(recentFile).then(() => {
      // 同步刷新启动预加载快照（AppStorage）：否则本会话内 Password.openRecentFileOptimized
      // 仍会命中启动时的旧快照（含旧 storageConfig），重新编辑连接后的新配置无法生效
      AppStorage.setOrCreate(Constants.APP_STORAGE_PRELOAD_RECENT_FILE, recentFile);
      // 导航到密码输入页面
      const passwordParam: PasswordParam = {
        filePath: locationInfo.filePath,
        openMode: openMode,
        addChildParent: addChildParent
      };
      NavigationManager.getInstance().navigateTo(PageConstants.PAGE_PASSWORD, passwordParam);
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to read data file: %{public}s, error: %{public}s', locationInfo.filePath, error.message);
      if (error instanceof KeePassHoError) {
        // 本地文件创建之后没有读权限
        if (error.code === ErrorCodes.FILE_NOT_PERMISSION) {
          const indexParam: IndexParam = { notRedirect: true };
          NavigationManager.getInstance().navigateTo(PageConstants.PAGE_INDEX, indexParam);
        }
      } else {
        CommonUtils.showToast($r('app.string.open_failed', error.message));
      }
    });
  }
}
