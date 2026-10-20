import { Kdbx } from 'kdbxweb';
import { LocationInfo } from '../services/beans/LocationParam';
import { StorageConfig, StorageType } from '../storage';
import { AuthTypeInfo, CredentialsParam, DbFileParam } from '../services/TypeDefined';
import { CachePolicyCarrier, MessageType, WorkerMessage } from './WorkerParam';


/**
 * 保存冲突处理策略
 */
export enum ConflictStrategy {
  /**
   * 自动：检测到远端已修改时通知上层（弹框让用户选择），本次不保存
   */
  AUTO = 'AUTO',
  /**
   * 合并：将远端修改合并进本地数据库后条件写入
   */
  MERGE = 'MERGE',
  /**
   * 覆盖：丢弃远端修改，用本地内容直接写入
   */
  OVERWRITE = 'OVERWRITE',
  /**
   * 重载：丢弃本地修改，从远端重新加载数据库（服务层拦截，不进入保存流程）
   */
  RELOAD = 'RELOAD',
}

/**
 * XC 两阶段保存挑战对：保存前主线程预生成 KDF salt 并完成 NFC 挑战所得
 * （salt 与应答原子成对传递：保存时注入 salt + 以固定应答消费；
 * 成功后由主线程单点更新会话 challengeResponseHex 为新应答）
 */
export interface SaveChallengePair {
  /**
   * 预挑战的 KDF salt（hex，32 字节）：保存时注入 kdfParameters 'S'
   */
  kdfSaltHex: string;
  /**
   * 对 kdfSaltHex 的 YubiKey HMAC-SHA1 应答（hex）：保存时以固定应答消费
   */
  responseHex: string;
}

export class SaveDatabaseMessage implements WorkerMessage, CachePolicyCarrier {
  type: MessageType;
  /**
   * 数据库文件
   */
  data: ArrayBuffer | Kdbx;
  dbFileParam: string;
  /**
   * 缓存策略随任务注入（Worker 常驻池化 #3：结构化克隆通道，不进 dbFileParam JSON 载荷）
   */
  enableLocalCache?: boolean;
  onlyUseCache?: boolean;
  forceRefresh?: boolean;

  constructor(data: ArrayBuffer | Kdbx, dbFileParam: DbFileParam, conflictStrategy?: string,
    saveChallenge?: SaveChallengePair) {
    this.type = MessageType.SAVE_DATABASE;
    this.data = data;
    this.dbFileParam = JSON.stringify({
      filePath: dbFileParam.filePath,
      fileName: dbFileParam.fileName,
      password: dbFileParam.password,
      authType: dbFileParam.authType,
      keyLocation: dbFileParam.keyLocation,
      storageType: dbFileParam.storageType,
      storageConfig: dbFileParam.storageConfig,
      modifiedTime: dbFileParam.modifiedTime,
      expectedVersion: dbFileParam.version ?? null,
      baseContentHash: dbFileParam.contentHash ?? null,
      conflictStrategy: conflictStrategy ?? ConflictStrategy.AUTO,
      newPassword: dbFileParam.newPassword,
      newKeyLocation: dbFileParam.newKeyLocation,
      notUseKeyFile: dbFileParam.notUseKeyFile,
      otpSecretHex: dbFileParam.otpSecretHex,
      challengeResponseHex: dbFileParam.challengeResponseHex,
      saveKdfSaltHex: saveChallenge?.kdfSaltHex,
      saveChallengeResponseHex: saveChallenge?.responseHex
    } as SaveDatabaseDbParam);
  }
}

export class SaveDatabase implements SaveDatabaseDbParam, WorkerMessage {
  type: MessageType;
  data: ArrayBuffer | Kdbx;
  filePath: string;
  fileName: string;
  password: string;
  authType: AuthTypeInfo;
  keyLocation?: LocationInfo;
  storageType: StorageType;
  storageConfig: StorageConfig;
  modifiedTime: number;
  /**
   * 期望的远端版本（基线A：存储原生版本标识）
   */
  expectedVersion?: string | null;
  /**
   * 基线远端内容哈希（基线B：内容 SHA256，最终裁判）
   */
  baseContentHash?: string | null;
  /**
   * 冲突处理策略
   */
  conflictStrategy?: string;
  newPassword?: string;
  newKeyLocation?: LocationInfo;
  notUseKeyFile?: boolean;
  /**
   * OTP / KeeChallenge 派生 secret（hex）：保存合并时重建凭证（解密远端副本）需要
   */
  otpSecretHex?: string;
  /**
   * 挑战-应答（XC）预计算应答（hex）：单次有效（KDF seed 每次保存后变化）
   */
  challengeResponseHex?: string;
  /**
   * XC 两阶段保存：预挑战 KDF salt（hex，32 字节），保存时注入 kdfParameters 'S'
   */
  saveKdfSaltHex?: string;
  /**
   * XC 两阶段保存：对 saveKdfSaltHex 的预计算应答（hex），保存时以固定应答消费
   */
  saveChallengeResponseHex?: string;

  constructor(dbParam: SaveDatabaseDbParam, message: SaveDatabaseMessage) {
    this.type = message.type;
    this.data = message.data;
    this.filePath = dbParam.filePath;
    this.fileName = dbParam.fileName;
    this.password = dbParam.password;
    this.authType = dbParam.authType;
    this.keyLocation = dbParam.keyLocation;
    this.storageType = dbParam.storageType;
    this.storageConfig = dbParam.storageConfig;
    this.modifiedTime = dbParam.modifiedTime;
    this.expectedVersion = dbParam.expectedVersion ?? null;
    this.baseContentHash = dbParam.baseContentHash ?? null;
    this.conflictStrategy = dbParam.conflictStrategy;
    this.newPassword = dbParam.newPassword;
    this.newKeyLocation = dbParam.newKeyLocation;
    this.notUseKeyFile = dbParam.notUseKeyFile;
    this.otpSecretHex = dbParam.otpSecretHex;
    this.challengeResponseHex = dbParam.challengeResponseHex;
    this.saveKdfSaltHex = dbParam.saveKdfSaltHex;
    this.saveChallengeResponseHex = dbParam.saveChallengeResponseHex;
  }
}

/**
 * 数据库保存参数
 */
export interface SaveDatabaseDbParam extends CredentialsParam {
  /**
   * 文件路径
   */
  filePath: string;

  /**
   * 文件名
   */
  fileName: string;

  /**
   * 密码
   */
  password: string;

  /**
   * 认证方式
   */
  authType: AuthTypeInfo;

  /**
   * 认证密码文件路径
   */
  keyLocation?: LocationInfo;

  /**
   * 存储类型
   */
  storageType: StorageType;

  /**
   * 存储配置信息
   */
  storageConfig: StorageConfig;

  /**
   * 最后修改时间,单位为毫秒
   */
  modifiedTime: number;

  /**
   * 期望的远端版本标识（来自 DbFileParam.version），用于冲突检测与条件写入
   */
  expectedVersion?: string | null;

  /**
   * 基线远端内容 SHA256（来自 DbFileParam.contentHash），冲突检测的最终裁判
   */
  baseContentHash?: string | null;

  /**
   * 冲突处理策略（ConflictStrategy 枚举值）
   */
  conflictStrategy?: string;

  /**
   * 新密码
   */
  newPassword?: string;

  /**
   * 新密钥文件路径
   */
  newKeyLocation?: LocationInfo;

  /**
   * 是否使用密钥文件
   */
  notUseKeyFile?: boolean;

  /**
   * XC 两阶段保存：预挑战 KDF salt（hex，32 字节）；与 saveChallengeResponseHex 原子成对
   */
  saveKdfSaltHex?: string;

  /**
   * XC 两阶段保存：对 saveKdfSaltHex 的预计算应答（hex）
   */
  saveChallengeResponseHex?: string;
}