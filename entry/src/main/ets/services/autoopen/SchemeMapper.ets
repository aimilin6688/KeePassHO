import { ChildDbScheme, ChildDbUrlKind, ChildTarget, PageConfig, StorageConfig, StorageType } from '../../storage';
import { FileStorageFactory } from '../../storage/FileStorageFactory';
import { AutoOpenPathResolver } from './AutoOpenPathResolver';

// 类型 re-export：ChildTarget 契约已上移存储层（PageConfig 声明依赖），
// 此处保持既有导入路径（services/autoopen 内部与单测）不变
export { ChildTarget } from '../../storage';

/**
 * AutoOpen 条目 URL 的 scheme → StorageType 映射器（M6.1，注册表驱动）
 *
 * 各存储在自身 PageConfig.childDbSchemes 中声明 scheme + ChildDbUrlKind 文法；
 * 本类经 FileStorageFactory 注册表发现声明并按固定文法解析/构造 URL。
 * 新增存储接入子库：实现存储 + PageConfig 声明 + 工厂注册（均为存储层既有必做项），
 * 本文件及全部存储无关代码零修改。
 *
 * 框架内置默认（不属于任何存储声明）：
 * - 裸相对/绝对路径 → LOCAL（M1-M5 既有语义）；
 * - `file://` URI → LOCAL（本地 filePath 即 file:// 形态，保留原文）。
 * `kdbx://` 前缀（KeePassXC 2.8 私有写法）不在此处处理：上游
 * `AutoOpenPathResolver.resolveUrl` 统一剥离后再按裸路径进入本类。
 *
 * 文法（固定通用集合，见 ChildDbUrlKind；AUTHORITY 约定 config 字段名
 * host/port/protocol，ENDPOINT_BUCKET 约定 endpoint/bucket）：
 * - PATH：rest 原样为 filePath（OAuth 云盘）；
 * - URL：完整 URL 为 filePath（WebDAV 直连；webdav(s) 升格 https）；
 * - AUTHORITY：host[:port]/path → host/port/sftp/filePath（FTP/SFTP）；
 * - ENDPOINT_BUCKET：endpoint权威/bucket/key → endpoint/bucket/filePath（S3）。
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
   * 解析（已展开占位符的）子库 URL
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
    const rest = match[2];
    // 框架默认：本地 file URI 保留原文（本应用本地 filePath 即 file:// 形态）
    if (scheme === 'file') {
      return SchemeMapper.local(normalized);
    }
    const found = SchemeMapper.findScheme(scheme);
    if (found === undefined) {
      return undefined;
    }
    const target = new ChildTarget();
    target.storageType = found.storageType;
    switch (found.schemeDecl.kind) {
      case ChildDbUrlKind.URL:
        return SchemeMapper.parseUrlKind(target, normalized, rest, found.schemeDecl);
      case ChildDbUrlKind.AUTHORITY:
        return SchemeMapper.parseAuthorityKind(target, rest, found.schemeDecl);
      case ChildDbUrlKind.ENDPOINT_BUCKET:
        return SchemeMapper.parseEndpointBucketKind(target, rest);
      case ChildDbUrlKind.PATH:
      default:
        target.filePath = rest;
        return target;
    }
  }

  /**
   * 写侧反向映射：由已打开子库的存储信息拼装条目 URL（M6.4）
   * @param storageType 存储类型
   * @param filePath 子库文件路径（远端格式）
   * @param config 子库存储配置（读取 host/endpoint/bucket 等连接要素；缺省时
   *               AUTHORITY/ENDPOINT_BUCKET 产出降级 URL，PATH/URL 文法完全无影响）
   * @returns scheme URL；LOCAL 返回 filePath 原样（由调用方做 {DB_DIR} 相对化）
   */
  public static buildUrl(storageType: StorageType, filePath: string, config?: StorageConfig): string {
    const pageConfig = SchemeMapper.findPageConfig(storageType);
    if (pageConfig === undefined) {
      return filePath;
    }
    const schemes = pageConfig.childDbSchemes;
    if (schemes === undefined || schemes.length === 0) {
      // LOCAL / 未声明子库 scheme 的存储：原样返回
      return filePath;
    }
    switch (schemes[0].kind) {
      case ChildDbUrlKind.URL:
        // WebDAV filePath 即完整 http(s) URL（含 host），原样写入（https/http 直连语义）
        return filePath;
      case ChildDbUrlKind.AUTHORITY:
        return SchemeMapper.buildAuthorityUrl(filePath, config, pageConfig);
      case ChildDbUrlKind.ENDPOINT_BUCKET:
        return SchemeMapper.buildEndpointBucketUrl(filePath, config);
      case ChildDbUrlKind.PATH:
      default:
        return SchemeMapper.writeScheme(pageConfig) + '://' + filePath;
    }
  }

  // ==================== 注册表访问 ====================

  /**
   * 在 FileStorageFactory 注册表中查找 scheme 声明
   */
  private static findScheme(scheme: string): SchemeDeclEntry | undefined {
    const storageMap = FileStorageFactory.getInstance().getStorageMap();
    for (const entry of storageMap.entries()) {
      const pageConfig = entry[1].getPageConfig();
      const declarations = pageConfig.childDbSchemes;
      if (declarations === undefined) {
        continue;
      }
      for (const declaration of declarations) {
        if (declaration.scheme === scheme) {
          return new SchemeDeclEntry(entry[0], declaration);
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
   * 写侧默认 scheme：PageConfig.childDbWriteScheme，缺省取首个声明
   */
  private static writeScheme(pageConfig: PageConfig): string {
    if (pageConfig.childDbWriteScheme !== undefined && pageConfig.childDbWriteScheme.length > 0) {
      return pageConfig.childDbWriteScheme;
    }
    const schemes = pageConfig.childDbSchemes;
    return schemes !== undefined && schemes.length > 0 ? schemes[0].scheme : '';
  }

  // ==================== 解析文法实现 ====================

  private static local(filePath: string): ChildTarget {
    const target = new ChildTarget();
    target.storageType = StorageType.LOCAL;
    target.filePath = filePath;
    return target;
  }

  /**
   * URL 文法：完整 http(s) URL 为 filePath；声明升格时替换 scheme（webdav → https）
   */
  private static parseUrlKind(target: ChildTarget, normalized: string,
    rest: string, decl: ChildDbScheme): ChildTarget | undefined {
    if (decl.upgradeScheme !== undefined) {
      if (rest.length === 0) {
        return undefined;
      }
      target.filePath = decl.upgradeScheme + '://' + rest;
      return target;
    }
    // 无升格声明（http/https 直连）：原样保留
    target.filePath = normalized;
    return target;
  }

  /**
   * AUTHORITY 文法：`host[:port][/远端路径]`
   * filePath 统一带前导 '/'（与远端路径约定一致，RecentFiles 判重同构）
   */
  private static parseAuthorityKind(target: ChildTarget, rest: string,
    decl: ChildDbScheme): ChildTarget | undefined {
    if (rest.length === 0) {
      return undefined;
    }
    target.sftp = decl.sftp === true;
    const slashIdx = rest.indexOf('/');
    const authority = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
    let remotePath = slashIdx >= 0 ? rest.substring(slashIdx) : '';
    if (remotePath.length === 0 || !remotePath.startsWith('/')) {
      remotePath = '/' + remotePath;
    }
    const colonIdx = authority.indexOf(':');
    if (colonIdx >= 0) {
      target.host = authority.substring(0, colonIdx);
      const port = Number(authority.substring(colonIdx + 1));
      target.port = isNaN(port) || port <= 0 ? 0 : Math.trunc(port);
    } else {
      target.host = authority;
    }
    if (target.host.length === 0) {
      return undefined;
    }
    target.filePath = remotePath;
    return target;
  }

  /**
   * ENDPOINT_BUCKET 文法：`endpoint权威/bucket/key` → endpoint = https://authority，
   * filePath = `bucket/key`（与该存储 filePath 约定一致）
   */
  private static parseEndpointBucketKind(target: ChildTarget, rest: string): ChildTarget | undefined {
    if (rest.length === 0) {
      return undefined;
    }
    const slashIdx = rest.indexOf('/');
    const authority = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
    const pathPart = slashIdx >= 0 ? rest.substring(slashIdx + 1) : '';
    target.endpoint = 'https://' + authority;
    if (pathPart.length > 0) {
      const keySlash = pathPart.indexOf('/');
      target.bucket = keySlash >= 0 ? pathPart.substring(0, keySlash) : pathPart;
      target.filePath = pathPart;
    }
    return target;
  }

  // ==================== 写侧文法实现 ====================

  /**
   * AUTHORITY 写侧：`scheme://host[:port]/远端路径`；端口为声明默认值时省略。
   * config 字段约定：host / port / protocol（'SFTP' 时选 sftp 声明的 scheme）
   */
  private static buildAuthorityUrl(filePath: string, config: StorageConfig | undefined,
    pageConfig: PageConfig): string {
    let host = '';
    let port = 0;
    let isSftp = false;
    if (config !== undefined && config !== null) {
      const record = config as Record<string, Object>;
      host = record['host'] !== undefined ? String(record['host']) : '';
      const portRaw = record['port'];
      port = portRaw !== undefined ? Number(portRaw) : 0;
      isSftp = record['protocol'] !== undefined && String(record['protocol']) === 'SFTP';
    }
    const schemes = pageConfig.childDbSchemes;
    let scheme = SchemeMapper.writeScheme(pageConfig);
    let defaultPort: number | undefined = schemes !== undefined && schemes.length > 0
      ? schemes[0].defaultPort : undefined;
    if (isSftp && schemes !== undefined) {
      for (const declaration of schemes) {
        if (declaration.sftp === true) {
          scheme = declaration.scheme;
          defaultPort = declaration.defaultPort;
          break;
        }
      }
    }
    const portSuffix = port > 0 && port !== defaultPort ? ':' + port : '';
    const remotePath = filePath.startsWith('/') ? filePath : '/' + filePath;
    return scheme + '://' + host + portSuffix + remotePath;
  }

  /**
   * ENDPOINT_BUCKET 写侧：`scheme://endpoint权威/bucket/key`；
   * filePath 未含 bucket 前缀时补上。config 字段约定：endpoint / bucket
   */
  private static buildEndpointBucketUrl(filePath: string, config: StorageConfig | undefined): string {
    let endpoint = '';
    let bucket = '';
    if (config !== undefined && config !== null) {
      const record = config as Record<string, Object>;
      endpoint = record['endpoint'] !== undefined ? String(record['endpoint']) : '';
      bucket = record['bucket'] !== undefined ? String(record['bucket']) : '';
    }
    let authority = endpoint.replace(/^https:\/\//, '').replace(/^http:\/\//, '');
    authority = authority.replace(/\/+$/, '');
    let objectPath = filePath.startsWith('/') ? filePath.substring(1) : filePath;
    if (bucket.length > 0 && !objectPath.startsWith(bucket + '/')) {
      objectPath = bucket + '/' + objectPath;
    }
    return 's3://' + authority + '/' + objectPath;
  }
}

/**
 * 注册表 scheme 索引条目
 */
class SchemeDeclEntry {
  readonly storageType: StorageType;
  readonly schemeDecl: ChildDbScheme;

  constructor(storageType: StorageType, schemeDecl: ChildDbScheme) {
    this.storageType = storageType;
    this.schemeDecl = schemeDecl;
  }
}
