/**
 * 定义消息类型
 */

import { Kdbx } from "kdbxweb";

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
}

// 定义消息
export interface WorkerMessage {
  type: MessageType;
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

  constructor(filesDir: string, cacheDir: string, enableLocalCache: boolean,
    onlyUseCache: boolean, forceRefresh: boolean) {
    this.type = MessageType.INIT_WORKER;
    this.filesDir = filesDir;
    this.cacheDir = cacheDir;
    this.enableLocalCache = enableLocalCache;
    this.onlyUseCache = onlyUseCache;
    this.forceRefresh = forceRefresh;
  }
}


// 定义数据库加载结果
export class LoadMessage implements WorkerMessage {
  type: MessageType;
  message: string | number;

  constructor(type: MessageType, message: string | number) {
    this.type = type;
    this.message = message;
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
   * isMerge 时合并后模型的 KPSN 快照（跨线程直传，主线程免解密重解析）
   */
  snapshot?: ArrayBuffer;


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

export function toLoadMessage(message: string | Resource): LoadMessage {
  if (typeof message === 'string') {
    return new LoadMessage(MessageType.MESSAGE, message);
  }
  return new LoadMessage(MessageType.MESSAGE, message.id);
}

export function toErrorMessage(message: string | number): LoadMessage {
  return new LoadMessage(MessageType.ERROR, message);
}