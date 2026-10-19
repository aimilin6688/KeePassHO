import { hilog } from '@kit.PerformanceAnalysisKit';

import { AutoOpenItem } from './AutoOpenItem';
import { RecentFilesService } from '../RecentFilesService';
import { LocalFileStorageConfig } from '../../storage/local/LocalFileConfig';
import { ChildDbRebuildArgs, ChildTarget, PageConfig, StorageConfig, StorageType } from '../../storage';
import { FileStorageFactory } from '../../storage/FileStorageFactory';
import { ResourceManager } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'AutoOpenConfigRebuilder';

/**
 * 远端子库 storageConfig 重建结果（M6.3）
 */
export class ConfigRebuildResult {
  /** 重建的存储配置；失败为 undefined */
  public config: StorageConfig | undefined = undefined;
  /** 失败原因（本地化文案，随 OPEN_FAILED 事件提示）；成功为空串 */
  public failReason: string = '';
}

/**
 * 远端子库 storageConfig 重建器（M6.3 resolveChildTarget 的一环，注册表驱动）
 *
 * 按 PageConfig 声明分发，存储类型不逐一列举：
 * - LOCAL：LocalFileStorageConfig（M1-M5 既有语义不变，框架默认）；
 * - 声明了 childDbConfigRebuilder（凭据型：WEBDAV/FTP/S3...）：
 *   由条目 IocUserName/IocPassword + customStrings + ChildTarget 连接要素
 *   重建 Config（各存储 rebuilder 自行实现，构造函数收明文凭据内部 SM4 加密；
 *   字段与 KeeAutoExec.cs:409-414 同名，PC 端可读）；
 * - 仅声明 childDbSchemes（OAuth 型：ONEDRIVE/HUAWEI_DRIVE/...）：令牌不进 kdbx，
 *   按 storageType+filePath 从设备本地 RecentFiles 匹配克隆 storageConfig
 *   （未命中 = 等价 kp2a UserInteractionRequiredException 降级，提示先手动打开一次）。
 */
export class AutoOpenConfigRebuilder {
  /**
   * 重建子库存储配置
   * @param item AutoOpen 条目解析结果（含 Ioc 凭据与 customStrings 透传包）
   * @param target SchemeMapper 解析出的打开目标
   */
  public static async build(item: AutoOpenItem, target: ChildTarget): Promise<ConfigRebuildResult> {
    const result = new ConfigRebuildResult();
    if (target.storageType === StorageType.LOCAL) {
      result.config = new LocalFileStorageConfig();
      return result;
    }
    const pageConfig = AutoOpenConfigRebuilder.findPageConfig(target.storageType);
    const rebuilder = pageConfig?.childDbConfigRebuilder;
    if (rebuilder !== undefined) {
      const args = new ChildDbRebuildArgs();
      args.iocUserName = item.iocUserName;
      args.iocPassword = item.iocPassword;
      args.customStrings = item.customStrings;
      result.config = rebuilder(args, target);
    } else if (pageConfig !== undefined && pageConfig.childDbSchemes !== undefined) {
      result.config = await AutoOpenConfigRebuilder.cloneOAuthConfig(target);
    }
    if (result.config === undefined) {
      result.failReason = AutoOpenConfigRebuilder.describeFailure(target);
    }
    return result;
  }

  /**
   * 经 FileStorageFactory 注册表查找存储的页面配置（未注册返回 undefined）
   */
  private static findPageConfig(storageType: StorageType): PageConfig | undefined {
    const storage = FileStorageFactory.getInstance().getStorageMap().get(storageType);
    return storage === undefined ? undefined : storage.getPageConfig();
  }

  /**
   * OAuth 云盘：按 storageType+filePath 匹配设备本地 RecentFile，克隆其 storageConfig
   * （含 SM4 加密的 token；未命中返回 undefined → 提示先在本设备手动打开一次）
   */
  private static async cloneOAuthConfig(target: ChildTarget): Promise<StorageConfig | undefined> {
    const recentFiles = await RecentFilesService.getRecentFiles();
    for (const recent of recentFiles) {
      if (recent.storageType === target.storageType && recent.filePath === target.filePath
        && recent.storageConfig !== undefined && recent.storageConfig !== null) {
        hilog.info(DOMAIN, TAG, 'clone oauth config from recent file: %{public}s', recent.filePath);
        return recent.storageConfig;
      }
    }
    return undefined;
  }

  /**
   * 组装失败原因文案（配置重建失败必给用户可理解的提示）：
   * 仅声明 scheme 的 OAuth 型 → 未在本设备打开；其余（凭据型/未知存储）→ 凭据缺失
   */
  private static describeFailure(target: ChildTarget): string {
    const pageConfig = AutoOpenConfigRebuilder.findPageConfig(target.storageType);
    if (pageConfig !== undefined && pageConfig.childDbConfigRebuilder === undefined
      && pageConfig.childDbSchemes !== undefined) {
      return ResourceManager.getString($r('app.string.child_dbs_remote_not_opened_on_device'));
    }
    return ResourceManager.getString($r('app.string.child_dbs_ioc_credentials_missing'));
  }
}
