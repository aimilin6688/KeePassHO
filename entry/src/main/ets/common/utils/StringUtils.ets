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

  /**
   * 获取XML标签内容
   * @param xmlString 字符串
   * @param tagName 标签
   * @returns 结果
   */
  public static getTagContent(xmlString: string, tagName: string) {
    // 构建正则表达式来匹配标签
    const pattern = new RegExp(`<${tagName}>(.*?)<\/${tagName}>`, 'i');
    const match = xmlString.match(pattern);
    if (match && match.length >= 2) {
      return match[1];
    }
    return '';
  }

  /**
   * 判断字符串是否非空
   */
  public static isNotBlank(str: string): boolean {
    if (str == undefined || str == null || str == '') {
      return false;
    }
    if (str.trim() == '') {
      return false;
    }
    return true;
  }
}