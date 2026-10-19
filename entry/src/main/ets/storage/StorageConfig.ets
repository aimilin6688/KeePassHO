
import { StorageType } from './StorageType';

/**
 * 存储配置接口
 */
export interface StorageConfig {}

/**
 * 子数据库（AutoOpen）scheme 解析文法种类（M6）
 *
 * 固定的通用 URL 文法集合：各存储在自身 PageConfig.childDbSchemes 中
 * 声明 scheme + 文法种类即可接入子库链路，存储无关代码零修改；
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
 * 单个 scheme 的子库声明（PageConfig.childDbSchemes 数组元素）
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
 * （远端子数据库 M6，各存储经 PageConfig.childDbSchemes 声明映射）
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
 * 凭据型存储 PageConfig.childDbConfigRebuilder 的入参
 * （条目中的连接凭据与全部自定义字符串字段原文）
 */
export class ChildDbRebuildArgs {
  /** 连接用户名（IocUserName；S3 为 AccessKeyId） */
  public iocUserName: string = '';
  /** 连接密码（IocPassword；S3 为 SecretAccessKey） */
  public iocPassword: string = '';
  /**
   * 条目全部自定义字符串字段原文（如 'S3Region'/'S3PathStyle'，
   * 供各存储 rebuilder 按需读取；新增字段无需改动解析侧）
   */
  public customStrings: Map<string, string> = new Map();
}

/**
 * 凭据字段声明（PageConfig.childDbCredentialKeys）：
 * 写侧从已打开子库 storageConfig 中提取连接凭据、写入条目
 * IocUserName/IocPassword 的加密字段名（类实例与 plain JSON 同名）
 */
export class ChildDbCredentialKeys {
  /** 连接用户名在 config 中的加密字段名（如 'username'/'accessKeyId'） */
  public userKey: string = '';
  /** 连接密码在 config 中的加密字段名（如 'password'/'secretAccessKey'） */
  public passwordKey: string = '';

  constructor(userKey: string, passwordKey: string) {
    this.userKey = userKey;
    this.passwordKey = passwordKey;
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
   * 子数据库 scheme 声明（M6，可选）：
   * 声明即接入子库链路——框架经 FileStorageFactory 注册表发现本声明，
   * 按 ChildDbUrlKind 固定文法解析/构造条目 URL。
   * 新存储接入子库只需：实现存储 + 在本 PageConfig 声明 + 工厂注册（后两项本就是必做项）。
   */
  childDbSchemes?: ChildDbScheme[];

  /**
   * 写侧默认 scheme（可选；缺省取 childDbSchemes[0].scheme。
   * PATH 文法的 buildUrl 用它拼 `scheme://filePath`）
   */
  childDbWriteScheme?: string;

  /**
   * 连接凭据字段声明（可选；凭据型存储）：
   * 写侧按字段名从子库 storageConfig（类实例或 plain JSON 同名字段）
   * 解密提取连接凭据，写入条目 IocUserName/IocPassword。
   * 未声明（OAuth 型/LOCAL）则不写 Ioc 字段。
   */
  childDbCredentialKeys?: ChildDbCredentialKeys;

  /**
   * 打开时 storageConfig 重建（可选；凭据型存储）：
   * 由条目 Ioc 凭据 + ChildTarget 连接要素构造本存储 Config。
   * 未声明但声明了 childDbSchemes（OAuth 云盘型）→ 框架按
   * storageType+filePath 从设备本地 RecentFiles 克隆 storageConfig（令牌不进 kdbx）。
   */
  childDbConfigRebuilder?: (args: ChildDbRebuildArgs, target: ChildTarget) => StorageConfig | undefined;

  /**
   * 写侧附加自定义字符串（可选；如 S3 的 S3Region/S3PathStyle 微调字段）：
   * 由已打开子库 storageConfig 产出要写入条目的自定义字符串字段表
   * （键 = kdbx 自定义字段名，值 = 字段原文），框架统一写入。
   */
  childDbExtraFields?: (config: StorageConfig) => Map<string, string>;
}
