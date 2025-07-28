import { StorageConfig, StorageType } from '../services/kdbx/interfaces';
import { AuthTypeInfo, CredentialsParam, DbFileParam } from '../services/TypeDefined';
import { MessageType, WorkerMessage } from './WorkerParam';

// 定义数据库加载请求
export class LoadDatabase implements WorkerMessage, CredentialsParam {
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
  keyFilePath?: string;
  /**
   * 存储类型
   */
  storageType: StorageType;
  /**
   * 存储配置信息
   */
  storageConfig: StorageConfig;

  constructor(filePath: string, fileName: string, password: string, authType: AuthTypeInfo,
    keyFilePath?: string, storageType?: StorageType | null, storageConfig?: StorageConfig | null) {
    this.type = MessageType.LOAD_DATABASE;
    this.filePath = filePath;
    this.fileName = fileName;
    this.password = password;
    this.authType = authType;
    this.keyFilePath = keyFilePath;
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
      dbFileParam.keyFilePath,
      dbFileParam.storageType,
      dbFileParam.storageConfig
    );
  }
}