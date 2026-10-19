import { UrlUtils } from '../../common/utils/UrlUtils';
import { ChildDbCredentials } from '../ChildDbCredentials';
import { ChildDbRebuildArgs, ChildDbSupport, ChildTarget, IocCredentials } from '../ChildDbSupport';
import { StorageConfig } from '../StorageConfig';
import { StorageType } from '../StorageType';
import { WebDAVStorageConfig } from './WebDAVConfig';

/**
 * WebDAV 子库支持适配器（ChildDbSupport 端口）：
 * URL 文法（webdav(s) 升格 https、http(s) 直连，filePath = 完整 http(s) URL）；
 * 统一解析链②由条目 Ioc 凭据 + URL origin 重建 Config；写侧提取
 * username/password 加密字段。
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
   *  filePath 为完整 http(s) URL，请求按绝对 URL 发出，config.url 取 origin 即可 */
  readonly rebuildConfig = (args: ChildDbRebuildArgs, target: ChildTarget): StorageConfig | undefined => {
    if (args.iocUserName.length === 0) {
      return undefined;
    }
    const origin: string = UrlUtils.getHost(target.filePath);
    if (origin.length === 0) {
      return undefined;
    }
    return new WebDAVStorageConfig(origin, args.iocUserName, args.iocPassword);
  };

  /** 写侧：从 storageConfig 解密提取连接凭据（类实例与 plain JSON 同名字段） */
  readonly extractCredentials = (config: StorageConfig): IocCredentials | undefined =>
    ChildDbCredentials.fromEncryptedFields(config, 'username', 'password');

  private static readonly SCHEME_PATTERN = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/(.*)$/;
}
