export class StringUtils {
  /**
   * 移除字符串开头的指定字符串
   * @param str
   * @param start
   * @returns
   */
  public static removeStart(str: string, start: string): string {
    if (!str || !start) {
      return str;
    }
    return str.startsWith(start) ? str.substring(start.length) : str;
  }
}