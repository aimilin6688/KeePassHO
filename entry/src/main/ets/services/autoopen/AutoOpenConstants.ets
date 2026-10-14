/**
 * 子数据库（AutoOpen / Child Databases）常量定义
 *
 * 与 KeePass 桌面版内置 AutoOpen 机制、KeeAutoExec 插件（PC）、
 * KeePass2Android（KeeAutoExec.cs）字段约定保持兼容。
 */

/** 根组下用于存放子数据库描述条目的组名（大小写不敏感匹配） */
export const AUTO_OPEN_GROUP_NAME = 'AutoOpen';

/** 自定义字符串字段名 */
export class AutoOpenFieldName {
  /** 设备 CSV 过滤列表（KeeAutoExec 扩展） */
  public static readonly IF_DEVICE = 'IfDevice';
  /** 条目总开关：True / False */
  public static readonly ENABLED = 'Enabled';
  /** 是否在切换界面展示：True / False */
  public static readonly VISIBLE = 'Visible';
  /** 打开顺序（数值，小的先打开） */
  public static readonly PRIORITY = 'Priority';
  /** 打开前检查子库文件存在，不存在则静默跳过（True） */
  public static readonly SKIP_IF_NOT_EXISTS = 'SkipIfNotExists';
  /** 同上的旧字段名（KeeAutoExec 兼容） */
  public static readonly SKIP_IF_NOT_EXISTS_LEGACY = 'Skip if not exists';
  /** 密钥文件不存在时静默跳过（True） */
  public static readonly SKIP_IF_KEY_FILE_NOT_EXISTS = 'SkipIfKeyFileNotExists';
}

/** SprEngine 占位符（本应用以 AutoOpenPathResolver 做最小实现） */
export class AutoOpenPlaceholder {
  /** 父数据库文件所在目录 */
  public static readonly DB_DIR = '{DB_DIR}';
  /** 目录分隔符（HarmonyOS 为 '/'） */
  public static readonly ENV_DIRSEP = '{ENV_DIRSEP}';
}
