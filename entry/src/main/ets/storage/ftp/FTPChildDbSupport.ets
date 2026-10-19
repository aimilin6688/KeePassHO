import { hilog } from '@kit.PerformanceAnalysisKit';

import { ChildDbCredentials } from '../ChildDbCredentials';
import { ChildDbIocFields } from '../ChildDbIocFields';
import { ChildDbRebuildArgs, ChildDbSupport, ChildTarget, IocCredentials } from '../ChildDbSupport';
import { StorageConfig } from '../StorageConfig';
import { StorageType } from '../StorageType';
import { FTPStorageConfig, FTPStorageConfigOptions, ProtocolType } from './FTPConfig';

const DOMAIN = 0x0000;
const TAG = 'FTPChildDbSupport';

/** FTP 超时默认值（毫秒，与 FTPStorageConfig 构造默认一致） */
const FTP_TIMEOUT_DEFAULT_MS = 30000;

/**
 * FTP/SFTP 子库支持适配器（ChildDbSupport 端口）：
 * AUTHORITY 文法 `ftp/sftp://host[:port]/远端路径`（默认端口 21/22，filePath
 * 统一带前导 '/'，与远端路径约定一致）；统一解析链②由条目 Ioc 凭据 +
 * host[:port] 重建 Config；写侧提取 username/password 加密字段。
 * Ioc 高级字段：IocTimeout（毫秒）重建进 Config；IocPassive 仅提示——
 * @ohos/basic-ftp 仅实现被动模式（PASV/EPSV），主动模式（PORT）不可用。
 */
export class FTPChildDbSupport implements ChildDbSupport {
  readonly schemes: string[] = ['ftp', 'sftp'];
  /** 打开侧：`host[:port]/远端路径`（rest 或 host 为空不支持） */
  readonly parseTarget = (url: string): ChildTarget | undefined => {
    const parsed = FTPChildDbSupport.parseAuthorityUrl(url);
    if (parsed === undefined) {
      return undefined;
    }
    const target = new ChildTarget();
    target.storageType = StorageType.FTP;
    target.filePath = parsed.remotePath;
    target.url = url;
    return target;
  };
  /** 写侧：`ftp/sftp://host[:port]/远端路径`；端口为协议默认值（21/22）时省略 */
  readonly buildUrl = (filePath: string, config?: StorageConfig): string => {
    let host = '';
    let port = 0;
    let isSftp = false;
    if (config !== undefined && config !== null) {
      const record = config as Record<string, Object>;
      host = record['host'] !== undefined ? String(record['host']) : '';
      const portRaw = record['port'];
      port = portRaw !== undefined ? Number(portRaw) : 0;
      isSftp = record['protocol'] !== undefined && String(record['protocol']) === 'SFTP';
    }
    const scheme = isSftp ? 'sftp' : 'ftp';
    const defaultPort = isSftp ? 22 : 21;
    const portSuffix = port > 0 && port !== defaultPort ? ':' + port : '';
    const remotePath = filePath.startsWith('/') ? filePath : '/' + filePath;
    return scheme + '://' + host + portSuffix + remotePath;
  };
  /**
   * 统一解析链②（Ioc 凭据 + host[:port] → FTPStorageConfig；
   *  端口未指定时由配置类取协议默认值 21/22；
   *  IocTimeout（毫秒）透传，IocPassive=False 时提示主动模式不支持并按被动继续）
   */
  readonly rebuildConfig = (args: ChildDbRebuildArgs, target: ChildTarget): StorageConfig | undefined => {
    const parsed = FTPChildDbSupport.parseAuthorityUrl(target.url);
    if (args.iocUserName.length === 0 || parsed === undefined || parsed.host.length === 0) {
      return undefined;
    }
    if (ChildDbIocFields.parseBool(args.customStrings, ChildDbIocFields.PASSIVE) === false) {
      hilog.warn(DOMAIN, TAG,
        'IocPassive=False (active mode) requested but @ohos/basic-ftp supports passive only: %{public}s',
        target.url);
    }
    const options: FTPStorageConfigOptions = parsed.sftp
      ? { port: parsed.port > 0 ? parsed.port : 22, protocol: ProtocolType.SFTP }
      : { port: parsed.port > 0 ? parsed.port : 21, protocol: ProtocolType.FTP };
    const timeoutMs: number | undefined = ChildDbIocFields.parseTimeoutMs(args.customStrings);
    if (timeoutMs !== undefined) {
      options.timeout = timeoutMs;
    }
    return new FTPStorageConfig(parsed.host, args.iocUserName, args.iocPassword, options);
  };
  /** 写侧：从 storageConfig 解密提取连接凭据（类实例与 plain JSON 同名字段） */
  readonly extractCredentials = (config: StorageConfig): IocCredentials | undefined =>
  ChildDbCredentials.fromEncryptedFields(config, 'username', 'password');

  /** 写侧附加自定义字符串：IocTimeout 非默认值时产出（保持条目简洁，默认值不写） */
  readonly extraFields = (config: StorageConfig): Map<string, string> => {
    const fields = new Map<string, string>();
    let timeout: number | undefined = undefined;
    if (config instanceof FTPStorageConfig) {
      timeout = config.timeout;
    } else {
      const record = config as Record<string, Object>;
      const timeoutValue: Object | undefined = record['timeout'];
      timeout = timeoutValue === undefined ? undefined : Number(timeoutValue);
    }
    if (timeout !== undefined && !isNaN(timeout) && timeout > 0 && timeout !== FTP_TIMEOUT_DEFAULT_MS) {
      fields.set(ChildDbIocFields.TIMEOUT, String(timeout));
    }
    return fields;
  };

  /**
   * AUTHORITY 文法解析（`scheme://host[:port]/远端路径`）：
   * rest 为空或 host 为空返回 undefined；remotePath 统一带前导 '/'。
   */
  private static parseAuthorityUrl(url: string): FtpUrlParts | undefined {
    const match = FTPChildDbSupport.SCHEME_PATTERN.exec(url);
    if (match === null) {
      return undefined;
    }
    const scheme = match[1].toLowerCase();
    const rest = match[2];
    if (rest.length === 0) {
      return undefined;
    }
    const parts = new FtpUrlParts();
    parts.sftp = scheme === 'sftp';
    const slashIdx = rest.indexOf('/');
    const authority = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
    let remotePath = slashIdx >= 0 ? rest.substring(slashIdx) : '';
    if (remotePath.length === 0 || !remotePath.startsWith('/')) {
      remotePath = '/' + remotePath;
    }
    const colonIdx = authority.indexOf(':');
    if (colonIdx >= 0) {
      parts.host = authority.substring(0, colonIdx);
      const port = Number(authority.substring(colonIdx + 1));
      parts.port = isNaN(port) || port <= 0 ? 0 : Math.trunc(port);
    } else {
      parts.host = authority;
    }
    if (parts.host.length === 0) {
      return undefined;
    }
    parts.remotePath = remotePath;
    return parts;
  }

  private static readonly SCHEME_PATTERN = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/(.*)$/;
}

/**
 * AUTHORITY 文法解析中间结果（适配器内部使用，不外泄）
 */
class FtpUrlParts {
  host: string = '';
  port: number = 0;
  sftp: boolean = false;
  remotePath: string = '';
}
