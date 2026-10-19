import { ChildDbSupport, ChildTarget, PageConfig, StorageConfig, StorageType } from '../../storage';
import { FileStorageFactory } from '../../storage/FileStorageFactory';
import { AutoOpenPathResolver } from './AutoOpenPathResolver';

// 类型 re-export：ChildTarget 契约已上移存储层（PageConfig 声明依赖），
// 此处保持既有导入路径（services/autoopen 内部与单测）不变
export { ChildTarget } from '../../storage';

/**
 * AutoOpen 条目 URL 的 scheme 路由器（M6.1/M6.9，注册表驱动）
 *
 * 本类不实现任何 URL 文法：各存储在自身 PageConfig.childDb 适配器
 * （ChildDbSupport 端口，M6.9）中声明 schemes 并自带 parseTarget/buildUrl；
 * 本类经 FileStorageFactory 注册表发现适配器，按 scheme 路由解析、
 * 按存储类型路由构造。新增存储接入子库：实现存储 + PageConfig 声明
 * childDb + 工厂注册（均为存储层既有必做项），本文件及全部存储无关代码零修改。
 *
 * 框架内置默认（不属于任何存储声明）：
 * - 裸相对/绝对路径 → LOCAL（M1-M5 既有语义）；
 * - `file://` URI → LOCAL（本地 filePath 即 file:// 形态，保留原文）。
 * `kdbx://` 前缀（KeePassXC 2.8 私有写法）不在此处处理：上游
 * `AutoOpenPathResolver.resolveUrl` 统一剥离后再按裸路径进入本类。
 */
export class SchemeMapper {
  private static readonly SCHEME_PATTERN = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/(.*)$/;

  /**
   * 解析 AutoOpen 条目 URL 原文：占位符展开 → scheme 解析，一步到位
   * （UI 侧「已打开」判定 / 行存储图标等场景使用）
   * @param itemUrl 条目 URL 原文（可含 {DB_DIR} 等占位符或相对路径）
   * @param parentFilePath 父库文件路径
   * @returns 解析结果；URL 为空或 scheme 不受支持时返回 undefined
   */
  public static resolveTarget(itemUrl: string, parentFilePath: string): ChildTarget | undefined {
    const childUrl: string = AutoOpenPathResolver.resolveUrl(itemUrl, parentFilePath);
    if (childUrl.length === 0) {
      return undefined;
    }
    return SchemeMapper.parse(childUrl);
  }

  /**
   * 解析（已展开占位符的）子库 URL：按 scheme 路由到声明它的子库适配器，
   * 由适配器按自身文法解析（M6.9 起文法内聚于各适配器，本类零文法）
   * @param url AutoOpenPathResolver.resolveUrl 的产物
   * @returns 解析结果；URL 为空或 scheme 不受支持时返回 undefined
   */
  public static parse(url: string): ChildTarget | undefined {
    const normalized = url.replace(/^\s+/, '').replace(/\s+$/, '');
    if (normalized.length === 0) {
      return undefined;
    }
    const match = SchemeMapper.SCHEME_PATTERN.exec(normalized);
    if (match === null) {
      // 裸路径：本地相对/绝对路径（M1-M5 既有语义）
      return SchemeMapper.local(normalized);
    }
    const scheme = match[1].toLowerCase();
    // 框架默认：本地 file URI 保留原文（本应用本地 filePath 即 file:// 形态）
    if (scheme === 'file') {
      return SchemeMapper.local(normalized);
    }
    const childDb = SchemeMapper.findChildDb(scheme);
    if (childDb === undefined) {
      return undefined;
    }
    return childDb.parseTarget(normalized);
  }

  /**
   * 写侧反向映射：由已打开子库的存储信息拼装条目 URL（M6.4）
   * @param storageType 存储类型
   * @param filePath 子库文件路径（远端格式）
   * @param config 子库存储配置（各适配器按需读取连接要素；缺省时产出降级 URL）
   * @returns scheme URL；LOCAL 返回 filePath 原样（由调用方做 {DB_DIR} 相对化）
   */
  public static buildUrl(storageType: StorageType, filePath: string, config?: StorageConfig): string {
    const pageConfig = SchemeMapper.findPageConfig(storageType);
    const childDb = pageConfig === undefined ? undefined : pageConfig.childDb;
    if (childDb === undefined) {
      // LOCAL / 未声明子库适配器的存储：原样返回
      return filePath;
    }
    return childDb.buildUrl(filePath, config);
  }

  // ==================== 注册表访问 ====================

  /**
   * 在 FileStorageFactory 注册表中查找声明了该 scheme 的子库适配器
   */
  private static findChildDb(scheme: string): ChildDbSupport | undefined {
    const storageMap = FileStorageFactory.getInstance().getStorageMap();
    for (const entry of storageMap.entries()) {
      const childDb = entry[1].getPageConfig().childDb;
      if (childDb === undefined) {
        continue;
      }
      for (const declared of childDb.schemes) {
        if (declared === scheme) {
          return childDb;
        }
      }
    }
    return undefined;
  }

  /**
   * 查找指定存储类型的页面配置（未注册返回 undefined）
   */
  private static findPageConfig(storageType: StorageType): PageConfig | undefined {
    const storage = FileStorageFactory.getInstance().getStorageMap().get(storageType);
    return storage === undefined ? undefined : storage.getPageConfig();
  }

  /**
   * 框架默认：本地目标（裸路径 / file:// 原文）
   */
  private static local(filePath: string): ChildTarget {
    const target = new ChildTarget();
    target.storageType = StorageType.LOCAL;
    target.filePath = filePath;
    target.url = filePath;
    return target;
  }
}
