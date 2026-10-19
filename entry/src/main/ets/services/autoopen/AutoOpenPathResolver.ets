import { AutoOpenPlaceholder } from './AutoOpenConstants';

/**
 * AutoOpen 条目 URL 的占位符展开与相对路径处理
 *
 * kdbxweb 无 SprEngine，本类实现最小占位符集：
 * - `{DB_DIR}`：父数据库文件所在目录；
 * - `{ENV_DIRSEP}`：目录分隔符（HarmonyOS 为 '/'）。
 * 裸相对路径按父库目录解析（PC 端 KeeAutoExec 按进程目录、kp2a 不支持，
 * 手机场景取父库目录最符合直觉；跨设备可移植写法推荐 `{DB_DIR}{ENV_DIRSEP}`）。
 * 另兼容 KeePassXC 2.8 特有的 `kdbx://` URL 前缀：剥离后余下按本地路径处理
 * （相对余项沿用父库目录解析，对齐 XC `openDatabaseFromEntry`；该前缀为 XC
 * 私有扩展，KeeAutoExec/kp2a 均不识别，本应用写侧不产出此写法）。
 */
export class AutoOpenPathResolver {
  /**
   * 取路径所在目录（最后一个 '/' 之前的部分；无 '/' 返回空串）
   */
  public static getDirName(path: string): string {
    if (path.length === 0) {
      return '';
    }
    const idx = path.lastIndexOf('/');
    if (idx <= 0) {
      return idx === 0 ? '/' : '';
    }
    return path.substring(0, idx);
  }

  /**
   * 展开 AutoOpen 条目 URL 为子库文件路径
   * @param url 条目 URL 原文（可含占位符或相对路径）
   * @param parentFilePath 父库文件路径
   * @returns 子库文件路径；URL 为空时返回空串
   */
  public static resolveUrl(url: string, parentFilePath: string): string {
    let normalized = url.replace(/^\s+/, '').replace(/\s+$/, '');
    if (normalized.length === 0) {
      return '';
    }
    const parentDir = AutoOpenPathResolver.getDirName(parentFilePath);
    // KeePassXC 2.8 兼容：剥离 kdbx:// 前缀（大小写敏感，对齐 XC openDatabaseFromEntry 的 startsWith 判定）
    if (normalized.startsWith('kdbx://')) {
      normalized = normalized.substring('kdbx://'.length);
      if (normalized.length === 0) {
        return '';
      }
    }
    normalized = normalized.split(AutoOpenPlaceholder.DB_DIR).join(parentDir);
    normalized = normalized.split(AutoOpenPlaceholder.ENV_DIRSEP).join('/');
    if (AutoOpenPathResolver.isAbsolutePath(normalized)) {
      return normalized;
    }
    // 裸相对路径：按父库目录解析
    if (parentDir.length === 0) {
      return normalized;
    }
    const sep = parentDir.endsWith('/') ? '' : '/';
    return parentDir + sep + normalized;
  }

  /**
   * 生成子库条目的可移植 URL：子库与父库同目录时写
   * `{DB_DIR}{ENV_DIRSEP}相对路径`，否则原样返回子库路径
   * @param childPath 子库文件路径
   * @param parentFilePath 父库文件路径
   */
  public static makeRelative(childPath: string, parentFilePath: string): string {
    if (childPath.length === 0) {
      return childPath;
    }
    const parentDir = AutoOpenPathResolver.getDirName(parentFilePath);
    if (parentDir.length === 0) {
      return childPath;
    }
    const prefix = parentDir.endsWith('/') ? parentDir : parentDir + '/';
    if (childPath.startsWith(prefix)) {
      return AutoOpenPlaceholder.DB_DIR + AutoOpenPlaceholder.ENV_DIRSEP + childPath.substring(prefix.length);
    }
    return childPath;
  }

  /**
   * 是否为绝对路径（POSIX 绝对路径或带 scheme 的 URI）
   */
  private static isAbsolutePath(path: string): boolean {
    if (path.startsWith('/')) {
      return true;
    }
    return /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(path);
  }
}
