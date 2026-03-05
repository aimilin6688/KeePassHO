import { ChineseHelper, pinyin4js, PinyinFormat } from '@ohos/pinyin4js';

/**
 * 字符串工具类
 */
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

  /**
   * 获取字符串的首字母（支持中文拼音）
   * 1、如果是字母则转成 大小
   * 2、如果是汉字则获取第一个字符的拼音首字母
   * 3、其他 返回 #
   */
  public static getFirstLetter(str: string): string {
    if (!str || str.length === 0) {
      return '#';
    }
    const firstChar = str.charAt(0);
    // 检查是否是字母
    if (/[a-zA-Z]/.test(firstChar)) {
      return firstChar.toUpperCase();
    }
    // 检查是否是中文，使用 pinyin4js 获取拼音首字母
    if (ChineseHelper.isChinese(firstChar)) {
      const pinyin: string = pinyin4js.getShortPinyin(firstChar);
      if (pinyin && pinyin.length > 0) {
        return pinyin.charAt(0).toUpperCase();
      }
    }
    // 数字或其他字符归类到 #
    return '#';
  }

  /**
   * 获取字符串的拼音
   * @param str
   * @returns 结果
   */
  public static getPinyin(str: string): string {
    if (!str || str.length === 0) {
      return '';
    }
    return pinyin4js.convertToPinyinString(str, '', PinyinFormat.WITHOUT_TONE) ?? str;
  }
}