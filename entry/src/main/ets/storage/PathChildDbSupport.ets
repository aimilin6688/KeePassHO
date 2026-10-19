import { ChildDbSupport, ChildTarget } from './ChildDbSupport';
import { StorageConfig } from './StorageConfig';
import { StorageType } from './StorageType';

/**
 * PATH 文法适配器（OAuth 云盘共享，框架提供）：
 * `scheme://rest` — rest 原样为 filePath；令牌不进 kdbx，打开时统一解析链
 * 从设备本地 RecentFiles 复用（未命中 → 提示先手动打开一次）。
 * 不声明 rebuildConfig/extractCredentials（OAuth 型语义）。
 */
export class PathChildDbSupport implements ChildDbSupport {
  readonly schemes: string[];
  private readonly storageType: StorageType;
  private readonly scheme: string;

  constructor(storageType: StorageType, scheme: string) {
    this.storageType = storageType;
    this.scheme = scheme;
    this.schemes = [scheme];
  }

  /** 打开侧：`scheme://rest` → rest 原样为 filePath */
  readonly parseTarget = (url: string): ChildTarget | undefined => {
    const prefix = this.scheme + '://';
    if (!url.toLowerCase().startsWith(prefix)) {
      return undefined;
    }
    const target = new ChildTarget();
    target.storageType = this.storageType;
    target.filePath = url.substring(prefix.length);
    target.url = url;
    return target;
  };


  /** 写侧：`scheme://filePath` */
  readonly buildUrl = (filePath: string, config?: StorageConfig): string => this.scheme + '://' + filePath;
}
