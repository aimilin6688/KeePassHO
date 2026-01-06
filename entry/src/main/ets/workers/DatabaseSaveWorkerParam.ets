import { Kdbx } from 'kdbxweb';
import { LocationInfo } from '../services/beans/LocationParam';
import { StorageConfig, StorageType } from '../storage';
import { AuthTypeInfo, CredentialsParam, DbFileParam } from '../services/TypeDefined';
import { MessageType, WorkerMessage } from './WorkerParam';


export class SaveDatabaseMessage implements WorkerMessage {
  type: MessageType;
  /**
   * 数据库文件
   */
  data: ArrayBuffer | Kdbx;
  dbFileParam: string;

  constructor(data: ArrayBuffer | Kdbx, dbFileParam: DbFileParam) {
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
      newPassword: dbFileParam.newPassword,
      newKeyLocation: dbFileParam.newKeyLocation,
      notUseKeyFile: dbFileParam.notUseKeyFile
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
  newPassword?: string;
  newKeyLocation?: LocationInfo;
  notUseKeyFile?: boolean;

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
    this.newPassword = dbParam.newPassword;
    this.newKeyLocation = dbParam.newKeyLocation;
    this.notUseKeyFile = dbParam.notUseKeyFile;
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
}