/**
 * 定义消息类型
 */

import { Kdbx } from "kdbxweb";
import { OAuth2Provider } from '../common/oauth2/OAuth2Types';
import { StorageConfig, StorageType } from '../storage';

export enum MessageType {
  /**
   * 加载数据库
   */
  LOAD_DATABASE = 'LOAD_DATABASE',
  /**
   * 保存数据库
   */
  SAVE_DATABASE = 'SAVE_DATABASE',
  /**
   * 加载消息
   */
  MESSAGE = 'MESSAGE',
  /**
   * 加载成功
   */
  SUCCESS = "SUCCESS",

  /**
   * 加载失败
   */
  ERROR = "ERROR",

  /**
   * 保存时检测到远端已被其他设备修改（冲突）
   */
  CONFLICT = 'CONFLICT',

  /**
   * Worker 启动初始化：注入主线程沙箱路径（Worker 线程无 Context）
   */
  INIT_WORKER = 'INIT_WORKER',

  /**
   * 预热请求（主线程 → Worker）：页面展示期建立 isolate 模块图 + 存储连接 + 探测大小
   */
  PREWARM = 'PREWARM',

  /**
   * 预热结果（Worker → 主线程）：探测到的文件大小回填加载调度缓存
   */
  PREWARM_RESULT = 'PREWARM_RESULT',

  /**
   * 传输进度（Worker → 主线程）：下载/上传字节进度，加载与保存共用
   */
  PROGRESS = 'PROGRESS',
}

// 定义消息
export interface WorkerMessage {
  type: MessageType;
}

/**
 * 缓存策略随任务注入协议（Worker 常驻池化 #3）。
 * 常驻模式下 INIT 快照会过期（用户中途改设置 / forceRefresh 一次性语义），
 * volatile 策略随每条任务消息走，路径/密钥仍保持 INIT 一次注入。
 * 未经 DatabaseWorkerFactory.attachCachePolicy 注入的旧格式消息三字段保持
 * undefined，Worker 壳不覆盖 INIT 快照（兼容测试直连构造）。
 */
export interface CachePolicyCarrier {
  /** 是否启用本地缓存（主线程实时值快照） */
  enableLocalCache?: boolean;
  /** 是否仅使用本地缓存（主线程实时值快照） */
  onlyUseCache?: boolean;
  /** 强制刷新（一次性标志，主线程 attach 时就地消费） */
  forceRefresh?: boolean;
}

/**
 * Worker 初始化消息：携带主线程沙箱路径与缓存策略快照。
 * Actor 模型下 Worker 线程与宿主线程内存隔离、无 Context/AppStorage/preferences，
 * 存储层所需的 filesDir/cacheDir 与缓存策略只能以快照形式注入。
 */
export class InitWorkerMessage implements WorkerMessage {
  type: MessageType;
  /** 应用级文件目录（ApplicationContext.filesDir） */
  filesDir: string;
  /** 应用缓存目录（UIAbilityContext.cacheDir） */
  cacheDir: string;
  /** 是否启用本地缓存（SettingsService，主线程真实值快照） */
  enableLocalCache: boolean;
  /** 是否仅使用本地缓存（AppStorage，主线程真实值快照） */
  onlyUseCache: boolean;
  /** 强制刷新（AppStorage，主线程创建 Worker 时一次性消费） */
  forceRefresh: boolean;
  /** 附件缓存加密密钥（base64，S4 附件磁盘化；空字符串表示禁用） */
  attachCacheKey: string;
  /** 会话密钥（base64，§7.4 M0 会话文件包裹；主线程与 Worker 共享同一进程级密钥） */
  sessionKeyBase64: string;
  /** 会话目录路径（§7.4；Worker 产出的 M0 落在主线程会话目录，便于统一清扫） */
  sessionDir: string;

  constructor(filesDir: string, cacheDir: string, enableLocalCache: boolean,
    onlyUseCache: boolean, forceRefresh: boolean, attachCacheKey: string,
    sessionKeyBase64: string, sessionDir: string) {
    this.type = MessageType.INIT_WORKER;
    this.filesDir = filesDir;
    this.cacheDir = cacheDir;
    this.enableLocalCache = enableLocalCache;
    this.onlyUseCache = onlyUseCache;
    this.forceRefresh = forceRefresh;
    this.attachCacheKey = attachCacheKey;
    this.sessionKeyBase64 = sessionKeyBase64;
    this.sessionDir = sessionDir;
  }
}


// 定义数据库加载结果
export class LoadMessage implements WorkerMessage {
  type: MessageType;
  message: string | number;
  /**
   * 错误明细（原始错误文本，如 'bad argon2 version'）：
   * 由主线程与本地化前缀拼接展示详细错误（"文件损坏: bad argon2 version"）；
   * undefined 表示无明细，仅展示本地化前缀
   */
  detail?: string;

  constructor(type: MessageType, message: string | number, detail?: string) {
    this.type = type;
    this.message = message;
    this.detail = detail;
  }
}

/**
 * 传输进度消息（Worker → 主线程，加载/保存共用）
 * 纯数据类（结构化克隆安全），不携带文案——阶段文案仍走 MESSAGE 事件，
 * 由 UI 侧组合"阶段文本 + 百分比/字节明细"展示
 */
export class ProgressMessage implements WorkerMessage {
  type: MessageType;
  /** 进度百分比（0-100，floor，上限 100） */
  percent: number;
  /** 已传输字节（下载=已接收，上传=已确认） */
  transferredBytes: number;
  /** 总字节 */
  totalBytes: number;

  constructor(percent: number, transferredBytes: number, totalBytes: number) {
    this.type = MessageType.PROGRESS;
    this.percent = percent;
    this.transferredBytes = transferredBytes;
    this.totalBytes = totalBytes;
  }
}

/**
 * OAuth2 令牌快照（Worker → 主线程单向回传）
 * Worker 线程无 Context/preferences，刷新后的令牌无法就地持久化（§11.1）；
 * 保存成功时把最新令牌随 SuccessMessage 带回，由主线程更新内存配置并加密落盘
 */
export class TokenSnapshot {
  /** OAuth2 提供者 */
  provider: OAuth2Provider;
  /** 访问令牌（明文，仅跨线程消息内传输） */
  accessToken: string;
  /** 刷新令牌（明文） */
  refreshToken: string;
  /** 过期时间（时间戳，毫秒） */
  expiresAt: number;
  /** 令牌类型（如 Bearer） */
  tokenType?: string;
  /** 授权范围 */
  scope?: string;

  constructor(provider: OAuth2Provider, accessToken: string, refreshToken: string,
    expiresAt: number, tokenType?: string, scope?: string) {
    this.provider = provider;
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    this.expiresAt = expiresAt;
    this.tokenType = tokenType;
    this.scope = scope;
  }
}

// 成功消息
export class SuccessMessage implements WorkerMessage {
  type: MessageType;
  /**
   * xml格式的数据库内容
   */
  data: ArrayBuffer | Kdbx;
  /**
   * 最后修改时间,单位为毫秒
   */
  modifiedTime: number;

  /**
   * 数据库是否发生了合并
   */
  isMerge: boolean;

  /**
   * 写入后的远端文件版本标识（不透明字符串），无此能力的存储为 null
   */
  version?: string | null;

  /**
   * 写入内容的 SHA256（十六进制小写），作为下次保存的冲突检测基线
   */
  contentHash?: string | null;

  /**
   * isMerge 时合并后模型的会话文件路径（§7.4：M0 会话包裹文件，仅路径跨线程）
   * 主线程解包裹后还原模型；大缓冲不再随消息跨线程
   */
  m0Path?: string;

  /**
   * Worker 刷新后的 OAuth2 令牌快照（仅在本次保存周期内发生过刷新时携带），
   * 主线程收到后更新内存配置并加密持久化；无令牌刷新的存储为 null
   */
  tokenSnapshot?: TokenSnapshot | null;

  /**
   * 加载文件的压缩后大小（字节，来自 readToFile 的 FileInfo）；
   * 主线程收到后回填加载调度缓存与最近文件记录（下次分级调度零网络决策）
   */
  fileSize?: number;


  constructor(data: ArrayBuffer | Kdbx, modifiedTime: number, isMerge?: boolean, version?: string | null, contentHash?: string | null) {
    this.type = MessageType.SUCCESS;
    this.data = data;
    this.modifiedTime = modifiedTime;
    this.isMerge = isMerge || false;
    this.version = version ?? null;
    this.contentHash = contentHash ?? null;
  }
}

// 冲突消息：保存时检测到远端文件已被其他设备修改
export class ConflictMessage implements WorkerMessage {
  type: MessageType;
  /**
   * 远端文件最后修改时间,单位为毫秒
   */
  remoteModifiedTime: number;

  /**
   * 远端文件版本标识（不透明字符串）
   */
  remoteVersion: string | null;


  constructor(remoteModifiedTime: number, remoteVersion: string | null) {
    this.type = MessageType.CONFLICT;
    this.remoteModifiedTime = remoteModifiedTime;
    this.remoteVersion = remoteVersion;
  }
}

/**
 * 预热请求：仅元数据三要素，绝不携带密码/密钥（攻击面最小化）；
 * 不注入缓存策略（避免消费 forceRefresh 一次性标志，预热用 Worker 当前快照即可）
 */
export class PrewarmMessage implements WorkerMessage {
  type: MessageType;
  /** 文件路径 */
  filePath: string;
  /** 存储类型 */
  storageType: StorageType;
  /** 存储配置 */
  storageConfig: StorageConfig;

  constructor(filePath: string, storageType: StorageType, storageConfig: StorageConfig) {
    this.type = MessageType.PREWARM;
    this.filePath = filePath;
    this.storageType = storageType;
    this.storageConfig = storageConfig;
  }
}

/**
 * 预热结果：探测成功携带 size（>0）；探测失败仅携带 error（主线程仅记日志）
 */
export class PrewarmResultMessage implements WorkerMessage {
  type: MessageType;
  /** 文件路径 */
  filePath: string;
  /** 探测到的大小（字节），失败或未知时 undefined */
  size?: number;
  /** 远端版本标识（不透明字符串） */
  version?: string | null;
  /** 失败原因（仅日志用途） */
  error?: string;

  constructor(filePath: string, size?: number, version?: string | null, error?: string) {
    this.type = MessageType.PREWARM_RESULT;
    this.filePath = filePath;
    this.size = size;
    this.version = version ?? null;
    this.error = error;
  }
}

export function toLoadMessage(message: string | Resource): LoadMessage {
  if (typeof message === 'string') {
    return new LoadMessage(MessageType.MESSAGE, message);
  }
  return new LoadMessage(MessageType.MESSAGE, message.id);
}

export function toErrorMessage(message: string | number, detail?: string): LoadMessage {
  return new LoadMessage(MessageType.ERROR, message, detail);
}