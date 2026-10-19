
import { Sm4Utils } from '../common/utils/Sm4Utils';
import { StorageType } from './StorageType';

/**
 * 存储配置接口
 */
export interface StorageConfig {}

/**
 * 子数据库（AutoOpen）scheme 解析文法种类（M6）
 *
 * 固定的通用 URL 文法集合：各存储在自身 PageConfig.childDb 适配器的
 * schemes 中声明 scheme + 文法种类即可接入子库链路，存储无关代码零修改；
 * 仅当出现全新 URL 文法时才需扩展本枚举（罕见）。
 */
export enum ChildDbUrlKind {
  /** `scheme://rest`：rest 原样作为 filePath（OAuth 云盘类存储） */
  PATH = 'PATH',
  /** `scheme://host[:port]/远端路径`：host/port/协议进 ChildTarget（FTP/SFTP） */
  AUTHORITY = 'AUTHORITY',
  /** `scheme://endpoint权威/bucket/key`：endpoint/bucket 进 ChildTarget（S3） */
  ENDPOINT_BUCKET = 'ENDPOINT_BUCKET',
  /** 完整 URL 原样作为 filePath（WebDAV：http/https 直连、webdav(s) 升格 https） */
  URL = 'URL'
}

/**
 * 单个 scheme 的子库声明（ChildDbSupport.schemes 数组元素）
 */
export class ChildDbScheme {
  /** 小写 scheme 名（如 'webdav'、'sftp'） */
  scheme: string = '';
  /** URL 解析文法 */
  kind: ChildDbUrlKind = ChildDbUrlKind.PATH;
  /** URL 文法专用：升格目标 scheme（webdav/webdavs → 'https'）；缺省保留原文 */
  upgradeScheme?: string;
  /** AUTHORITY 文法专用：scheme 是否代表 SFTP（'sftp' → target.sftp = true） */
  sftp?: boolean;
  /** AUTHORITY 文法专用：协议默认端口（写侧 URL 省略该端口；FTP=21/SFTP=22） */
  defaultPort?: number;

  constructor(scheme: string, kind: ChildDbUrlKind, upgradeScheme?: string,
    sftp?: boolean, defaultPort?: number) {
    this.scheme = scheme;
    this.kind = kind;
    this.upgradeScheme = upgradeScheme;
    this.sftp = sftp;
    this.defaultPort = defaultPort;
  }
}

/**
 * 子数据库 scheme 解析结果：AutoOpen 条目 URL 剥离 scheme 后的打开目标
 * （远端子数据库 M6，各存储经 PageConfig.childDb 适配器声明映射）
 */
export class ChildTarget {
  /** 存储类型 */
  public storageType: StorageType = StorageType.LOCAL;
  /** 子库文件路径（远端格式与正常打开该存储的 filePath 一致） */
  public filePath: string = '';
  /** FTP/SFTP：主机名 */
  public host: string = '';
  /** FTP/SFTP：端口（0 = 未指定，由配置类取协议默认值） */
  public port: number = 0;
  /** FTP：是否 SFTP 协议 */
  public sftp: boolean = false;
  /** S3：endpoint（含协议，如 https://s3.amazonaws.com） */
  public endpoint: string = '';
  /** S3：存储桶（URL 首段；空串 = 未指定） */
  public bucket: string = '';

  /**
   * 是否远端存储（非 LOCAL）
   */
  public isRemote(): boolean {
    return this.storageType !== 'LOCAL';
  }
}

/**
 * 存储适配器 rebuildConfig 的入参
 * （条目中的连接凭据与全部自定义字符串字段原文）
 */
export class ChildDbRebuildArgs {
  /** 连接用户名（IocUserName；S3 为 AccessKeyId） */
  public iocUserName: string = '';
  /** 连接密码（IocPassword；S3 为 SecretAccessKey） */
  public iocPassword: string = '';
  /**
   * 条目全部自定义字符串字段原文（如 'S3Region'/'S3PathStyle'，
   * 供各存储适配器按需读取；新增字段无需改动解析侧）
   */
  public customStrings: Map<string, string> = new Map();
}

/**
 * 远端子库连接凭据（解密明文，仅内存中传递，写完即弃）
 */
export class IocCredentials {
  /** 连接用户名（IocUserName；S3 为 AccessKeyId） */
  public readonly userName: string;
  /** 连接密码（IocPassword；S3 为 SecretAccessKey） */
  public readonly password: string;

  constructor(userName: string, password: string) {
    this.userName = userName;
    this.password = password;
  }

  /**
   * 从 storageConfig（类实例或 plain JSON 同名字段——RecentFile 往返后为
   * plain JSON）按加密字段名解密提取连接凭据：
   * 各存储适配器 extractCredentials 的共享实现。
   * 字段缺失或解密失败（SM4 密钥变更/密文损坏）返回 undefined，调用方跳过写入。
   */
  public static fromEncryptedFields(config: StorageConfig, userKey: string,
    passwordKey: string): IocCredentials | undefined {
    try {
      const record = config as Record<string, Object>;
      const userName: Object | undefined = record[userKey];
      const password: Object | undefined = record[passwordKey];
      if (userName === undefined || password === undefined) {
        return undefined;
      }
      return new IocCredentials(Sm4Utils.tryDecryptWithPrefix(String(userName)),
        Sm4Utils.tryDecryptWithPrefix(String(password)));
    } catch (error) {
      return undefined;
    }
  }
}

/**
 * 子库支持端口（Port-Adapter，M6.9）：
 * 每个存储一个适配器，声明于自身 PageConfig.childDb；子库框架
 * （SchemeMapper / AutoOpenConfigRebuilder / AutoOpenEntryService）
 * 只依赖本接口，存储类型零枚举（依赖倒置，框架拥有端口）。
 * 新存储接入子库 = 在自身 PageConfig 写一行 childDb 声明
 * （OAuth 型用 PathChildDbSupport），框架与其余存储零改动。
 */
export interface ChildDbSupport {
  /** scheme + 文法声明（唯一必填项）：声明即接入子库解析/构造链路 */
  schemes: ChildDbScheme[];

  /** 写侧默认 scheme（缺省取 schemes[0].scheme） */
  writeScheme?: string;

  /**
   * 打开侧（可选；凭据型存储）：统一解析链②——RecentFiles 未命中时由
   * 条目 IocUserName/IocPassword + customStrings + ChildTarget 连接要素
   * 重建 Config（新设备首开兜底，kp2a 语义；不声明则该存储子库须先在
   * 本设备手动打开过一次）
   */
  rebuildConfig?: (args: ChildDbRebuildArgs, target: ChildTarget) => StorageConfig | undefined;

  /**
   * 写侧（可选；凭据型存储）：从已打开子库 storageConfig 解密提取连接凭据，
   * 写入条目 IocUserName/IocPassword；不声明则不写 Ioc 字段
   * （OAuth 型/令牌不入库）
   */
  extractCredentials?: (config: StorageConfig) => IocCredentials | undefined;

  /**
   * 写侧（可选）：由已打开子库 storageConfig 产出要写入条目的自定义字符串
   * 字段表（键 = kdbx 自定义字段名，值 = 字段原文，如 S3 的
   * S3Region/S3PathStyle 微调字段），框架统一写入
   */
  extraFields?: (config: StorageConfig) => Map<string, string>;
}

/**
 * PATH 文法适配器（OAuth 云盘共享，框架提供）：
 * 仅声明 scheme，rest 原样为 filePath；令牌不进 kdbx，打开时统一解析链
 * 从设备本地 RecentFiles 复用（未命中 → 提示先手动打开一次）
 */
export class PathChildDbSupport implements ChildDbSupport {
  readonly schemes: ChildDbScheme[];
  readonly writeScheme: string;

  constructor(scheme: string) {
    this.schemes = [new ChildDbScheme(scheme, ChildDbUrlKind.PATH)];
    this.writeScheme = scheme;
  }
}

/**
 * 页面配置信息
 */
export interface PageConfig {
  /**
    * 存储类型图标
    */
  icon: Resource;

  /**
    * 存储类型名称
    */
  title: ResourceStr;

  /**
    * 选择时存储类型描述
    */
  selectDesc: ResourceStr;

  /**
    * 保存时存储类型描述
    */
  saveDesc: ResourceStr;

  /**
    * 跳转页面路径
    */
  pageUrl: string;

  /**
    * 存储类型
    */
  storageType: string;

  /**
    * UI 测试定位用的组件标识（可选）
    */
  id?: string;

  /**
    * 子库支持适配器（M6.9，可选）：声明即接入子库链路——框架经
    * FileStorageFactory 注册表发现本声明，按 ChildDbUrlKind 固定文法
    * 解析/构造条目 URL。
    * 新存储接入子库只需在自身 PageConfig 加一行 childDb 声明
    * （OAuth 型 new PathChildDbSupport('scheme')）；凭据型按需在自身
    * 模块实现 ChildDbSupport 适配器类（rebuildConfig/extractCredentials/
    * extraFields 均可选）。
    */
  childDb?: ChildDbSupport;
}
