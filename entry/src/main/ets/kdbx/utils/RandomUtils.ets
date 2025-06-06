/**
 * 随机工具类
 * 提供随机字符串生成功能
 */
export class RandomUtils {
  // 默认字符集：大写字母、小写字母和数字
  private static readonly DEFAULT_CHARS: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  /**
   * 生成指定长度的随机字符串
   * @param length 要生成的字符串长度，默认32位
   * @param chars 可选的自定义字符集
   * @returns 生成的随机字符串
   */
  public static generateRandomString(length: number = 32, chars: string = RandomUtils.DEFAULT_CHARS): string {
    if (length <= 0) {
      throw new Error('Length must be greater than 0');
    }
    if (chars.length === 0) {
      throw new Error('Character set cannot be empty');
    }

    let result = '';
    const charsLength = chars.length;

    for (let i = 0; i < length; i++) {
      // 使用Math.random()生成随机索引
      const randomIndex = Math.floor(Math.random() * charsLength);
      result += chars[randomIndex];
    }

    return result;
  }

  /**
   * 生成32位随机字符串
   * 使用默认字符集（大小写字母和数字）
   * @returns 32位随机字符串
   */
  public static generate32BitString(): string {
    return RandomUtils.generateRandomString(32);
  }

  /**
   * 生成指定长度的随机数字字符串
   * @param length 要生成的字符串长度，默认32位
   * @returns 随机数字字符串
   */
  public static generateNumericString(length: number = 32): string {
    return RandomUtils.generateRandomString(length, '0123456789');
  }

  /**
   * 生成指定长度的随机十六进制字符串
   * @param length 要生成的字符串长度，默认32位
   * @returns 随机十六进制字符串（大写）
   */
  public static generateHexString(length: number = 32): string {
    return RandomUtils.generateRandomString(length, '0123456789ABCDEF');
  }

  /**
   * 生成指定长度的随机小写字母字符串
   * @param length 要生成的字符串长度，默认32位
   * @returns 随机小写字母字符串
   */
  public static generateLowerCaseString(length: number = 32): string {
    return RandomUtils.generateRandomString(length, 'abcdefghijklmnopqrstuvwxyz');
  }

  /**
   * 生成指定长度的随机大写字母字符串
   * @param length 要生成的字符串长度，默认32位
   * @returns 随机大写字母字符串
   */
  public static generateUpperCaseString(length: number = 32): string {
    return RandomUtils.generateRandomString(length, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
  }

  /**
   * 生成指定长度的随机字母字符串（不包含数字）
   * @param length 要生成的字符串长度，默认32位
   * @returns 随机字母字符串
   */
  public static generateLetterString(length: number = 32): string {
    return RandomUtils.generateRandomString(length, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz');
  }
}
