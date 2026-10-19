import { ChildDbRebuildArgs, ChildDbScheme, ChildDbSupport, ChildDbUrlKind, ChildTarget,
  IocCredentials } from '../ChildDbSupport';
import { PageConfig, StorageConfig } from '../StorageConfig';
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
 * FTP/SFTP 子库支持适配器（ChildDbSupport 端口，M6.9）：
 * AUTHORITY 文法（ftp 默认端口 21 / sftp 默认端口 22）；统一解析链②由条目
 * Ioc 凭据 + host[:port] 重建 Config；写侧提取 username/password 加密字段。
 */
export class FTPChildDbSupport implements ChildDbSupport {
  readonly schemes: ChildDbScheme[] = [
    new ChildDbScheme('ftp', ChildDbUrlKind.AUTHORITY, undefined, false, 21),
    new ChildDbScheme('sftp', ChildDbUrlKind.AUTHORITY, undefined, true, 22)
  ];

  /** 统一解析链②（Ioc 凭据 + host[:port] → FTPStorageConfig；
   *  端口未指定时由配置类取协议默认值 21/22） */
  readonly rebuildConfig = (args: ChildDbRebuildArgs, target: ChildTarget): StorageConfig | undefined => {
    if (args.iocUserName.length === 0 || target.host.length === 0) {
      return undefined;
    }
    const options: FTPStorageConfigOptions = target.sftp
      ? { port: target.port > 0 ? target.port : 22, protocol: ProtocolType.SFTP }
      : { port: target.port > 0 ? target.port : 21, protocol: ProtocolType.FTP };
    return new FTPStorageConfig(target.host, args.iocUserName, args.iocPassword, options);
  };

  /** 写侧：从 storageConfig 解密提取连接凭据（类实例与 plain JSON 同名字段） */
  readonly extractCredentials = (config: StorageConfig): IocCredentials | undefined =>
    IocCredentials.fromEncryptedFields(config, 'username', 'password');
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
  // M6.9 子库支持适配器（AUTHORITY 文法；凭据型：链②重建 + 写侧凭据提取）
  childDb: new FTPChildDbSupport()
} as PageConfig;