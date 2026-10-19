/**
 * 子库条目 Ioc 高级连接字段共享解析（kp2a IocKnownProperties 同名约定）
 *
 * kp2a KeeAutoExec.cs TryGetDatabaseIoc 从 AutoOpen 条目读取下列自定义字段
 * 并写入远端连接信息：IocTimeout（毫秒）/ IocPreAuth / IocUserAgent /
 * IocExpect100Continue / IocPassive。本应用中这些字段经 customStrings
 * 透传到各存储适配器 rebuildConfig 按需消费（S3Region/S3PathStyle 同机制）。
 * 本类只提供统一解析（数字/布尔/字符串），不绑定具体存储语义。
 */
export class ChildDbIocFields {
  /** 连接超时（毫秒，正整数） */
  public static readonly TIMEOUT = 'IocTimeout';
  /** 预先发送认证（不等 401 挑战；WebDAV Basic） */
  public static readonly PRE_AUTH = 'IocPreAuth';
  /** 自定义 User-Agent */
  public static readonly USER_AGENT = 'IocUserAgent';
  /** 上传请求体前先协商 100-continue */
  public static readonly EXPECT_100_CONTINUE = 'IocExpect100Continue';
  /** FTP 被动模式 */
  public static readonly PASSIVE = 'IocPassive';

  /**
   * 解析 IocTimeout（毫秒）：空串/非数字/非正数视为未设置
   */
  public static parseTimeoutMs(customStrings: Map<string, string>): number | undefined {
    const raw = ChildDbIocFields.readTrimmed(customStrings, ChildDbIocFields.TIMEOUT);
    if (raw.length === 0) {
      return undefined;
    }
    const parsed = Number(raw);
    if (isNaN(parsed) || parsed <= 0) {
      return undefined;
    }
    return Math.trunc(parsed);
  }

  /**
   * 解析 True/False 布尔字段（大小写不敏感；其余值视为未设置）
   */
  public static parseBool(customStrings: Map<string, string>,
    fieldName: string): boolean | undefined {
    const raw = ChildDbIocFields.readTrimmed(customStrings, fieldName).toLowerCase();
    if (raw === 'true') {
      return true;
    }
    if (raw === 'false') {
      return false;
    }
    return undefined;
  }

  /**
   * 解析字符串字段（去除首尾空白；未设置返回空串）
   */
  public static parseString(customStrings: Map<string, string>, fieldName: string): string {
    return ChildDbIocFields.readTrimmed(customStrings, fieldName);
  }

  /**
   * 读取字段原文并去除首尾空白
   */
  private static readTrimmed(customStrings: Map<string, string>, fieldName: string): string {
    const raw = customStrings.get(fieldName);
    if (raw === undefined) {
      return '';
    }
    return raw.replace(/^\s+/, '').replace(/\s+$/, '');
  }
}
