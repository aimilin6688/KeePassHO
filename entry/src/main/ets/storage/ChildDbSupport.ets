import { StorageConfig } from './StorageConfig';
import { StorageType } from './StorageType';

/**
 * 子数据库（AutoOpen）支持端口与通用值类型（M6 / M6.9，自 StorageConfig.ets 抽取）
 *
 * 本文件只定义端口契约与通用值类型，不含任何具体实现：
 * - 端口实现（各存储适配器）见 storage/PathChildDbSupport.ets 与
 *   各存储模块的 *ChildDbSupport.ets；
 * - 各适配器自带 URL 文法（parseTarget/buildUrl），框架不做文法假设。
 */

/**
 * 子库打开目标：AutoOpen 条目 URL 经适配器解析后的通用结果
 * （远端子数据库 M6，各存储经 PageConfig.childDb 适配器产出）
 *
 * 仅含框架所需通用要素；host/port/endpoint/bucket 等文法细节由各适配器
 * 内部解析（rebuildConfig 可重解析 url 原文），不外泄到框架层。
 */
export class ChildTarget {
  /** 存储类型 */
  public storageType: StorageType = StorageType.LOCAL;
  /** 子库文件路径（远端格式与正常打开该存储的 filePath 一致） */
  public filePath: string = '';
  /** 产出本目标的子库 URL 原文（适配器 rebuildConfig 重解析文法用） */
  public url: string = '';

  /**
   * 是否远端存储（非 LOCAL）
   */
  public isRemote(): boolean {
    return this.storageType !== StorageType.LOCAL;
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
}

/**
 * 子库支持端口（Port-Adapter，M6.9）：
 * 每个存储一个适配器，声明于自身 PageConfig.childDb；子库框架
 * （SchemeMapper / AutoOpenConfigRebuilder / AutoOpenEntryService）
 * 只依赖本接口，存储类型零枚举（依赖倒置，框架拥有端口）。
 * 新存储接入子库 = 在自身 PageConfig 写一行 childDb 声明
 * （OAuth 型用框架提供的 PathChildDbSupport），框架与其余存储零改动。
 */
export interface ChildDbSupport {
  /** 支持的条目 URL scheme（小写；框架据此路由 parseTarget/buildUrl；唯一必填项） */
  schemes: string[];

  /**
   * 打开侧：解析（已展开占位符的）子库条目 URL 为打开目标
   * （各存储自定义文法；URL 为空或文法不匹配返回 undefined）
   */
  parseTarget: (url: string) => ChildTarget | undefined;

  /**
   * 写侧：由子库文件路径（+已打开子库配置）构造条目 URL
   * @param filePath 子库文件路径（远端格式）
   * @param config 已打开子库存储配置（缺省时产出降级 URL）
   */
  buildUrl: (filePath: string, config?: StorageConfig) => string;

  /**
   * 打开侧（可选；凭据型存储）：统一解析链②——RecentFiles 未命中时由
   * 条目 IocUserName/IocPassword + customStrings + ChildTarget（含 url
   * 原文）重建 Config（新设备首开兜底，kp2a 语义；不声明则该存储子库
   * 须先在本设备手动打开过一次）
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
