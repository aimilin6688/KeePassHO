import { hilog } from '@kit.PerformanceAnalysisKit';

import { AutoOpenItem } from './AutoOpenItem';
import { RecentFile } from '../TypeDefined';
import { RecentFilesService } from '../RecentFilesService';
import { LocalFileStorageConfig } from '../../storage/local/LocalFileConfig';
import { ChildDbRebuildArgs, ChildDbSupport, ChildTarget, PageConfig, StorageConfig, StorageType } from '../../storage';
import { FileStorageFactory } from '../../storage/FileStorageFactory';
import { ResourceManager } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'AutoOpenConfigRebuilder';

/**
 * 远端子库 storageConfig 解析结果（M6.3）
 */
export class ConfigRebuildResult {
  /** 解析出的存储配置；失败为 undefined */
  public config: StorageConfig | undefined = undefined;
  /** 失败原因（本地化文案，随 OPEN_FAILED 事件提示）；成功为空串 */
  public failReason: string = '';
}

/**
 * 远端子库 storageConfig 统一解析链（M6.3 / M6.9，注册表驱动）
 *
 * 链序（resolve 纯函数；build 为 IO 包装）：
 * ① LOCAL → LocalFileStorageConfig（框架默认）；
 * ② RecentFiles 命中（storageType+filePath）→ 直接复用上次成功打开保存的
 *   完整 storageConfig（证书校验/TLS/端口/超时/令牌全保真；打开成功由
 *   RecentFilesService.upsertChildConfigRecord 回写，见 AutoOpenCoordinator）；
 * ③ childDb.rebuildConfig（凭据型适配器声明）→ 条目 IocUserName/IocPassword
 *   + customStrings + ChildTarget 连接要素重建 Config（新设备首开兜底，
 *   kp2a 语义；字段与 KeeAutoExec.cs:409-414 同名，PC 端可读）；
 * ④ 仍失败 → 按声明给精确文案（凭据型：缺少连接凭据；其余：先手动打开一次）。
 *
 * 语义取舍（已知并接受，见设计文档 M6.9）：链②优先于链③——条目 Ioc 凭据
 * 修改后需重开一次子库生效，换取完整连接选项保真。
 */
export class AutoOpenConfigRebuilder {
  /**
   * 解析子库存储配置（IO 包装：查 childDb 端口 + 取设备本地 RecentFiles
   * 后委托 resolve 纯函数）
   * @param item AutoOpen 条目解析结果（含 Ioc 凭据与 customStrings 透传包）
   * @param target SchemeMapper 解析出的打开目标
   */
  public static async build(item: AutoOpenItem, target: ChildTarget): Promise<ConfigRebuildResult> {
    const childDb: ChildDbSupport | undefined = AutoOpenConfigRebuilder.findChildDb(target.storageType);
    // LOCAL 不触设备 IO（RecentFiles 读取），直接走纯链
    const recentFiles: RecentFile[] = target.storageType === StorageType.LOCAL
      ? [] : await RecentFilesService.getRecentFiles();
    return AutoOpenConfigRebuilder.resolve(item, target, recentFiles, childDb);
  }

  /**
   * 统一解析链（纯函数，可单测）
   * @param item AutoOpen 条目解析结果
   * @param target SchemeMapper 解析出的打开目标
   * @param recentFiles 设备本地最近文件列表（链②数据源）
   * @param childDb 目标存储的子库适配器（未注册/未声明为 undefined）
   */
  public static resolve(item: AutoOpenItem, target: ChildTarget, recentFiles: RecentFile[],
    childDb: ChildDbSupport | undefined): ConfigRebuildResult {
    const result = new ConfigRebuildResult();
    if (target.storageType === StorageType.LOCAL) {
      result.config = new LocalFileStorageConfig();
      return result;
    }
    // ② RecentFiles 命中：直接复用上次成功打开保存的完整配置
    const hit: StorageConfig | undefined = AutoOpenConfigRebuilder.findRecentConfig(target, recentFiles);
    if (hit !== undefined) {
      hilog.info(DOMAIN, TAG, 'reuse recent config for child: %{public}s', target.filePath);
      result.config = hit;
      return result;
    }
    // ③ 凭据型兜底：条目 Ioc 凭据 + customStrings + 连接要素重建
    const rebuild = childDb === undefined ? undefined : childDb.rebuildConfig;
    if (rebuild !== undefined) {
      const args = new ChildDbRebuildArgs();
      args.iocUserName = item.iocUserName;
      args.iocPassword = item.iocPassword;
      args.customStrings = item.customStrings;
      result.config = rebuild(args, target);
    }
    // ④ 失败：按声明给精确文案（凭据型：凭据缺失；其余：未在本设备打开过）
    if (result.config === undefined) {
      result.failReason = rebuild !== undefined
        ? ResourceManager.getString($r('app.string.child_dbs_ioc_credentials_missing'))
        : ResourceManager.getString($r('app.string.child_dbs_remote_not_opened_on_device'));
    }
    return result;
  }

  /**
   * 链②：按 storageType+filePath 匹配设备本地 RecentFile（须带 storageConfig）
   */
  private static findRecentConfig(target: ChildTarget,
    recentFiles: RecentFile[]): StorageConfig | undefined {
    for (const recent of recentFiles) {
      if (recent.storageType === target.storageType && recent.filePath === target.filePath
        && recent.storageConfig !== undefined && recent.storageConfig !== null) {
        return recent.storageConfig;
      }
    }
    return undefined;
  }

  /**
   * 经 FileStorageFactory 注册表查找存储的子库适配器（未注册/未声明返回 undefined）
   */
  private static findChildDb(storageType: StorageType): ChildDbSupport | undefined {
    const storage = FileStorageFactory.getInstance().getStorageMap().get(storageType);
    const pageConfig: PageConfig | undefined = storage === undefined ? undefined : storage.getPageConfig();
    return pageConfig === undefined ? undefined : pageConfig.childDb;
  }
}
