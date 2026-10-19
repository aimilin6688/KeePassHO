import { UrlUtils } from '../../common/utils/UrlUtils';
import { ChildDbCredentials } from '../ChildDbCredentials';
import { ChildDbIocFields } from '../ChildDbIocFields';
import { ChildDbRebuildArgs, ChildDbSupport, ChildTarget, IocCredentials } from '../ChildDbSupport';
import { StorageConfig } from '../StorageConfig';
import { StorageType } from '../StorageType';
import { WebDAVStorageConfig, WebDAVStorageConfigOptions } from './WebDAVConfig';

/**
 * WebDAV 子库支持适配器（ChildDbSupport 端口）：
 * URL 文法（webdav(s) 升格 https、http(s) 直连，filePath = 完整 http(s) URL）；
 * 统一解析链②由条目 Ioc 凭据 + URL origin 重建 Config；写侧提取
 * username/password 加密字段。Ioc 高级字段（kp2a IocKnownProperties）：
 * IocTimeout/IocUserAgent/IocPreAuth/IocExpect100Continue 重建进 Config。
 */
export class WebDAVChildDbSupport implements ChildDbSupport {
  readonly schemes: string[] = ['webdav', 'webdavs', 'http', 'https'];

  /** 打开侧：webdav(s) 升格 https（rest 为空不支持）；http(s) 原样直连 */
  readonly parseTarget = (url: string): ChildTarget | undefined => {
    const match = WebDAVChildDbSupport.SCHEME_PATTERN.exec(url);
    if (match === null) {
      return undefined;
    }
    const scheme = match[1].toLowerCase();
    const rest = match[2];
    const target = new ChildTarget();
    target.storageType = StorageType.WEBDAV;
    target.url = url;
    if (scheme === 'webdav' || scheme === 'webdavs') {
      if (rest.length === 0) {
        return undefined;
      }
      target.filePath = 'https://' + rest;
      return target;
    }
    // http/https 直连：原样保留
    target.filePath = url;
    return target;
  };

  /** 写侧：filePath 即完整 http(s) URL（含 host），原样写入（https/http 直连语义） */
  readonly buildUrl = (filePath: string, config?: StorageConfig): string => filePath;

  /** 统一解析链②（Ioc 凭据 + URL origin → WebDAVStorageConfig）：
    *  filePath 为完整 http(s) URL，请求按绝对 URL 发出，config.url 取 origin 即可；
    *  Ioc 高级字段（IocTimeout 毫秒 / IocUserAgent / IocPreAuth / IocExpect100Continue）
    *  经 customStrings 透传，此处按需消费重建 */
  readonly rebuildConfig = (args: ChildDbRebuildArgs, target: ChildTarget): StorageConfig | undefined => {
    if (args.iocUserName.length === 0) {
      return undefined;
    }
    const origin: string = UrlUtils.getHost(target.filePath);
    if (origin.length === 0) {
      return undefined;
    }
    const userAgent: string = ChildDbIocFields.parseString(args.customStrings, ChildDbIocFields.USER_AGENT);
    const options: WebDAVStorageConfigOptions = {
      timeout: ChildDbIocFields.parseTimeoutMs(args.customStrings),
      userAgent: userAgent.length > 0 ? userAgent : undefined,
      preAuth: ChildDbIocFields.parseBool(args.customStrings, ChildDbIocFields.PRE_AUTH) === true,
      expect100Continue:
        ChildDbIocFields.parseBool(args.customStrings, ChildDbIocFields.EXPECT_100_CONTINUE) === true
    };
    return new WebDAVStorageConfig(origin, args.iocUserName, args.iocPassword, options);
  };

  /** 写侧：从 storageConfig 解密提取连接凭据（类实例与 plain JSON 同名字段） */
  readonly extractCredentials = (config: StorageConfig): IocCredentials | undefined =>
    ChildDbCredentials.fromEncryptedFields(config, 'username', 'password');

  /** 写侧附加自定义字符串：Ioc 高级字段非默认值时产出（保持条目简洁，默认值不写） */
  readonly extraFields = (config: StorageConfig): Map<string, string> => {
    const fields = new Map<string, string>();
    let timeout: number | undefined = undefined;
    let userAgent = '';
    let preAuth = false;
    let expect100Continue = false;
    if (config instanceof WebDAVStorageConfig) {
      timeout = config.timeout;
      userAgent = config.userAgent ?? '';
      preAuth = config.preAuth === true;
      expect100Continue = config.expect100Continue === true;
    } else {
      const record = config as Record<string, Object>;
      const timeoutValue: Object | undefined = record['timeout'];
      timeout = timeoutValue === undefined ? undefined : Number(timeoutValue);
      const userAgentValue: Object | undefined = record['userAgent'];
      userAgent = userAgentValue === undefined ? '' : String(userAgentValue);
      preAuth = record['preAuth'] !== undefined && String(record['preAuth']) === 'true';
      expect100Continue =
        record['expect100Continue'] !== undefined && String(record['expect100Continue']) === 'true';
    }
    if (timeout !== undefined && !isNaN(timeout) && timeout > 0) {
      fields.set(ChildDbIocFields.TIMEOUT, String(timeout));
    }
    if (userAgent.length > 0) {
      fields.set(ChildDbIocFields.USER_AGENT, userAgent);
    }
    if (preAuth) {
      fields.set(ChildDbIocFields.PRE_AUTH, 'True');
    }
    if (expect100Continue) {
      fields.set(ChildDbIocFields.EXPECT_100_CONTINUE, 'True');
    }
    return fields;
  };

  private static readonly SCHEME_PATTERN = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/(.*)$/;
}
