import { ChildDbCredentialKeys, ChildDbRebuildArgs, ChildDbScheme, ChildDbUrlKind, ChildTarget,
  PageConfig, StorageConfig } from '../StorageConfig';
import { Sm4Utils } from '../../common/utils/Sm4Utils';
import { StorageType } from '..';

/**
 * 协议类型枚举
 */
export enum ProtocolType {
  FTP = 'FTP',
  SFTP = 'SFTP'
}

/**
 * 安全类型
 */
export type SecureType = boolean | "implicit";

/**
 * FTP存储配置选项类
 */
export interface FTPStorageConfigOptions {
  timeout?: number;
  secure?: boolean | "implicit";
  port?: number;
  protocol?: ProtocolType;
}

/**
 * FTP存储配置类
 */
export class FTPStorageConfig implements StorageConfig {
  /**
   * 服务器地址
   */
  host: string;
  /**
   * 端口号，默认21 (SFTP默认22)
   */
  port: number;
  /**
   * 用户名, 加密后的Base64字符串
   */
  username: string;
  /**
   * 密码, 加密后的Base64字符串
   */
  password: string;
  /**
   * 超时时间（毫秒，可选）
   */
  timeout?: number;
  /**
   * 是否使用FTP over TLS (可选)
   */
  secure?: SecureType;
  /**
   * 协议类型 (可选)，默认 FTP
   */
  protocol?: ProtocolType;

  constructor(host: string, username: string, password: string, options?: FTPStorageConfigOptions) {
    this.host = host;
    this.port = options?.port || ((options?.protocol === ProtocolType.SFTP) ? 22 : 21);
    this.username = Sm4Utils.encryptWithPrefix(username);
    this.password = Sm4Utils.encryptWithPrefix(password);
    this.timeout = options?.timeout || 30000;
    this.secure = options?.secure;
    this.protocol = options?.protocol || ProtocolType.FTP;
  }

  public getUserNameText(): string {
    return Sm4Utils.decryptWithPrefix(this.username);
  }

  public getPasswordText(): string {
    return Sm4Utils.decryptWithPrefix(this.password);
  }

  public isSFTP(): boolean {
    return this.protocol === ProtocolType.SFTP;
  }
}

/**
 * 子库打开时 storageConfig 重建（PageConfig.childDbConfigRebuilder 契约，M6.3）：
 * Ioc 凭据 + host[:port] → FTPStorageConfig（端口未指定时由配置类取协议默认值 21/22）
 */
export function ftpChildDbConfigRebuilder(args: ChildDbRebuildArgs,
  target: ChildTarget): StorageConfig | undefined {
  if (args.iocUserName.length === 0 || target.host.length === 0) {
    return undefined;
  }
  const options: FTPStorageConfigOptions = target.sftp
    ? { port: target.port > 0 ? target.port : 22, protocol: ProtocolType.SFTP }
    : { port: target.port > 0 ? target.port : 21, protocol: ProtocolType.FTP };
  return new FTPStorageConfig(target.host, args.iocUserName, args.iocPassword, options);
}

/**
 * FTP页面配置类
 */
export const FTPPageConfig = {
  icon: $r("app.media.ic_ftp"),
  title: $r('app.string.ftp_button_title'),
  selectDesc: $r('app.string.location_ftp_desc_select'),
  saveDesc: $r('app.string.location_ftp_desc_save'),
  pageUrl: 'storage/ftp/FTPPage',
  storageType: StorageType.FTP,
  // M6 子库 scheme 声明（AUTHORITY 文法）：host[:port]/远端路径；默认端口写侧省略
  childDbSchemes: [
    new ChildDbScheme('ftp', ChildDbUrlKind.AUTHORITY, undefined, false, 21),
    new ChildDbScheme('sftp', ChildDbUrlKind.AUTHORITY, undefined, true, 22)
  ],
  childDbCredentialKeys: new ChildDbCredentialKeys('username', 'password'),
  childDbConfigRebuilder: ftpChildDbConfigRebuilder
} as PageConfig;