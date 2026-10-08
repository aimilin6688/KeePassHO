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
    return new LoadDatabase(
      dbFileParam.filePath,
      dbFileParam.fileName,
      dbFileParam.password,
      dbFileParam.authType,
      dbFileParam.keyLocation,
      dbFileParam.storageType,
      dbFileParam.storageConfig
    );
  }
}