import { LocationInfo } from '../services/beans/LocationParam';
import { StorageConfig, StorageType } from '../storage';
import { AuthTypeInfo, CredentialsParam, DbFileParam } from '../services/TypeDefined';
import { CachePolicyCarrier, MessageType, WorkerMessage } from './WorkerParam';

// 定义数据库加载请求
export class LoadDatabase implements WorkerMessage, CredentialsParam, CachePolicyCarrier {
  type: MessageType;
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
   * OTP / KeeChallenge 派生 secret（hex）：主线程派生后随 JSON 消息传入
   * （undefined 字段序列化时自动丢弃，见 KdbxLoadService 消息通道）
   */
  otpSecretHex?: string;
  /**
   * 挑战-应答（XC）预计算应答（hex）：两阶段加载第二阶段由固定应答回调消费
   */
  challengeResponseHex?: string;
  /**
   * 内联密钥文件内容（base64，AutoOpen 条目 KeyFile.bin 附件提取）：
   * 主线程提取后随 JSON 消息传入（undefined 字段序列化时自动丢弃），不持久化
   */
  keyFileDataBase64?: string;
  /**
   * 存储类型
   */
  storageType: StorageType;
  /**
   * 存储配置信息
   */
  storageConfig: StorageConfig;
  /**
   * 缓存策略随任务注入（Worker 常驻池化 #3：JSON 通道，undefined 字段序列化时自动丢弃）
   */
  enableLocalCache?: boolean;
  onlyUseCache?: boolean;
  forceRefresh?: boolean;
  /**
   * 调度层已解析的文件大小（字节，>0 有效）：守卫 CP1/CP-DISK 直接复用，跳过重复 getInfo
   */
  precheckSize?: number;

  constructor(filePath: string, fileName: string, password: string, authType: AuthTypeInfo,
    keyLocation?: LocationInfo, storageType?: StorageType, storageConfig?: StorageConfig, asyncLoad?: boolean) {
    this.type = MessageType.LOAD_DATABASE;
    this.filePath = filePath;
    this.fileName = fileName;
    this.password = password;
    this.authType = authType;
    this.keyLocation = keyLocation;
    this.storageType = storageType ?? StorageType.LOCAL;
    this.storageConfig = storageConfig ?? {};
  }

  /**
   * 通过 DbFileParam 初始化
   * @param dbFileParam
   * @returns
   */
  public static byDbFileParam(dbFileParam: DbFileParam): LoadDatabase {
    const loadDatabase = new LoadDatabase(
      dbFileParam.filePath,
      dbFileParam.fileName,
      dbFileParam.password,
      dbFileParam.authType,
      dbFileParam.keyLocation,
      dbFileParam.storageType,
      dbFileParam.storageConfig
    );
    // OTP secret 在两次保存间稳定（仅 Counter 前进），重载/合并可复用；
    // challengeResponseHex：XC 库两阶段保存成功后由 KdbxSaveService 单点更新为新应答
    // （文件 seed = 预挑战 salt），会话内重载/下拉刷新始终配对有效；
    // 远端被其他设备换 seed 时重载报 InvalidKey，回解锁页重新贴卡
    loadDatabase.otpSecretHex = dbFileParam.otpSecretHex;
    loadDatabase.challengeResponseHex = dbFileParam.challengeResponseHex;
    // KeyFile.bin 内联密钥随会话内重载传递（registry DbFileParam → LoadDatabase）
    loadDatabase.keyFileDataBase64 = dbFileParam.keyFileDataBase64;
    return loadDatabase;
  }
}