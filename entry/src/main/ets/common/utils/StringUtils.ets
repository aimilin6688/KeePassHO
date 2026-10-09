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

  /**
   * 移除字符串结尾已追加的传输进度（" 50%" 或 " 1.0 KB / 2.0 KB"）
   * 用于进度文案刷新时先剥离上一次的进度，再拼接本次进度，避免进度不断累积
   * @param str 原始文案
   * @returns 去掉结尾进度后的文案
   */
  public static removeTrailingProgress(str: string): string {
    if (!str) {
      return '';
    }
    // 字节明细：" 1.0 KB / 2.0 KB"
    const byteDetail = /\s*\d+(?:\.\d+)?\s*(?:B|KB|MB|GB)\s*\/\s*\d+(?:\.\d+)?\s*(?:B|KB|MB|GB)\s*$/i;
    // 百分比：" 50%"
    const percent = /\s*\d+(?:\.\d+)?\s*%\s*$/;
    return str.replace(byteDetail, '').replace(percent, '');
  }

  /**
   * 格式化文件大小
   * @param size 文件大小（字节）
   * @returns 格式化后的字符串，如 "1.5 KB"
   */
  public static formatFileSize(size: number): string {
    if (size < 0) {
      return '-';
    }
    if (size < 1024) {
      return size + ' B';
    } else if (size < 1024 * 1024) {
      return (size / 1024).toFixed(1) + ' KB';
    } else if (size < 1024 * 1024 * 1024) {
      return (size / (1024 * 1024)).toFixed(1) + ' MB';
    } else {
      return (size / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
    }
  }
}