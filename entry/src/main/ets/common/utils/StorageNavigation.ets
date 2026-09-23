import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageConfig, StorageType } from '../../storage';
import { LocationInfo, LocationParam } from '../../services/beans/LocationParam';
import { NavigationManager } from './NavigationManager';
import { PageConstants } from '../constants/PageConstants';

const DOMAIN = 0x0000;
const TAG = 'StorageNavigation';

/**
 * OAuth2 登录页导航参数
 * 各云存储配置页跳转授权页时统一使用该结构
 */
export interface OAuth2LoginParam {
  /**
   * 授权地址
   */
  authUrl: string;
  /**
   * OAuth2 配置
   */
  oauth2Config: Object;
  /**
   * 授权页面标题
   */
  pageTitle: ResourceStr;
}

/**
 * 云存储页面导航工具类
 * 集中维护「存储类型 → 页面名称 / 页面标题」的映射，
 * 避免每个存储页面重复编写跳转参数与标题资源。
 */
export class StorageNavigation {
  /**
   * 跳转到指定存储类型的文件列表页
   * @param storageType 存储类型
   * @param filePath 初始路径
   * @param storageConfig 存储配置
   */
  static pushFileList(storageType: StorageType, filePath: string, storageConfig: StorageConfig): void {
    const pageName: string = StorageNavigation.getFileListPageName(storageType);
    if (pageName === '') {
      hilog.error(DOMAIN, TAG, 'Unsupported file list storage type: %{public}s', storageType);
      return;
    }
    const info: LocationInfo = LocationParam.toLocationInfo(storageType, filePath, storageConfig);
    NavigationManager.getInstance().navigateTo(pageName, info);
  }

  /**
   * 跳转到 OAuth2 授权登录页
   * @param authUrl 授权地址
   * @param oauth2Config OAuth2 配置
   * @param pageTitle 授权页面标题
   */
  static pushOAuth2Login(authUrl: string, oauth2Config: Object, pageTitle: ResourceStr): void {
    const param: OAuth2LoginParam = {
      authUrl: authUrl,
      oauth2Config: oauth2Config,
      pageTitle: pageTitle
    };
    NavigationManager.getInstance().navigateTo(PageConstants.PAGE_OAUTH2_LOGIN, param);
  }

  /**
   * 返回上一页
   */
  static pop(): void {
    NavigationManager.getInstance().pop();
  }

  /**
   * 存储类型 → 文件列表页面名称
   * @param storageType 存储类型
   * @return 页面名称，不支持的类型返回空字符串
   */
  static getFileListPageName(storageType: StorageType): string {
    switch (storageType) {
      case StorageType.WEBDAV:
        return PageConstants.PAGE_WEBDAV_FILE_LIST;
      case StorageType.ONEDRIVE:
        return PageConstants.PAGE_ONEDRIVE_FILE_LIST;
      case StorageType.FTP:
        return PageConstants.PAGE_FTP_FILE_LIST;
      case StorageType.S3:
        return PageConstants.PAGE_S3_FILE_LIST;
      case StorageType.PCLOUD:
        return PageConstants.PAGE_PCLOUD_FILE_LIST;
      case StorageType.HUAWEI_DRIVE:
        return PageConstants.PAGE_HUAWEI_DRIVE_FILE_LIST;
      default:
        return '';
    }
  }

  /**
   * 存储类型 → 页面标题资源
   * 配置页与文件列表页共用同一套标题
   * @param storageType 存储类型
   * @return 标题资源，不支持的类型返回空字符串
   */
  static getStorageTitle(storageType: StorageType): ResourceStr {
    switch (storageType) {
      case StorageType.WEBDAV:
        return $r('app.string.webdav_button_title');
      case StorageType.ONEDRIVE:
        return $r('app.string.onedrive_login_button');
      case StorageType.FTP:
        return $r('app.string.ftp_button_title');
      case StorageType.S3:
        return $r('app.string.s3_button_title');
      case StorageType.PCLOUD:
        return $r('app.string.pcloud_login_button');
      case StorageType.HUAWEI_DRIVE:
        return $r('app.string.huawei_drive_select_file');
      default:
        return '';
    }
  }
}
