import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileStorage, StorageConfig, StorageType } from '../../storage';
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
 * 「存储类型 → 连接配置页面名称 / 页面标题」等信息统一从各存储实现注册的
 * PageConfig（经 FileStorageFactory 查询）中获取；
 * 文件列表页所有云存储共用同一个 FileList 页面。
 * 新增存储类型只需编写自己的 PageConfig 并在工厂注册，无需修改本类。
 */
export class StorageNavigation {
  /**
   * 跳转到指定存储类型的文件列表页
   * 所有云存储共用同一个 FileList 页面（路由名 FileListPage）
   * @param storageType 存储类型
   * @param filePath 初始路径
   * @param storageConfig 存储配置
   */
  static pushFileList(storageType: StorageType, filePath: string, storageConfig: StorageConfig): void {
    // 本地存储走 LocalFilePage（系统文件选择器），不经过文件列表页
    if (storageType === StorageType.LOCAL || !FileStorage.hasStorage(storageType)) {
      hilog.error(DOMAIN, TAG, 'Unsupported file list storage type: %{public}s', storageType);
      return;
    }
    const info: LocationInfo = LocationParam.toLocationInfo(storageType, filePath, storageConfig);
    NavigationManager.getInstance().navigateTo(PageConstants.PAGE_FILE_LIST, info);
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
   * 存储类型 → 连接配置页面名称
   * 取 PageConfig.pageUrl 的最后一段作为路由表中的页面名称
   * @param storageType 存储类型
   * @return 页面名称，未注册的存储类型返回空字符串
   */
  static getConfigPageName(storageType: StorageType): string {
    const pageUrl: string = FileStorage.getPageConfig(storageType)?.pageUrl || '';
    return pageUrl.split('/').pop() || '';
  }

  /**
   * 存储类型 → 页面标题资源
   * 配置页与文件列表页共用同一套标题
   * @param storageType 存储类型
   * @return 标题资源，未注册的存储类型返回空字符串
   */
  static getStorageTitle(storageType: StorageType): ResourceStr {
    return FileStorage.getPageConfig(storageType)?.title || '';
  }
}
