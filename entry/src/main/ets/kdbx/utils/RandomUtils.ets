/**
 * RandomUtils.ets
 *
 * 随机数生成工具类
 */

import { Binary } from '../models/KdbxTypes';
import { ByteUtils } from './ByteUtils';

export class RandomUtils {
  // 默认字符集：大写字母、小写字母和数字
  private static readonly DEFAULT_CHARS: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  /**
   * 生成指定长度的随机字节数组
   * @param length 字节数组长度
   * @returns 随机字节数组
   */
  public static getRandomBytes(length: number): Binary {
    return ByteUtils.randomBytes(length);
  }

  /**
   * 生成指定范围内的随机整数
   * @param min 最小值（包含）
   * @param max 最大值（包含）
   * @returns 随机整数
   */
  public static getRandomInt(min: number, max: number): number {
    const range = max - min + 1;
    const bytes = RandomUtils.getRandomBytes(4);
    const value = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
    return min + (Math.abs(value) % range);
  }

  /**
   * 生成UUID v4
   * @returns UUID字符串
   */
  public static generateUUID(): string {
    const bytes = RandomUtils.getRandomBytes(16);

    // 设置版本为4
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // 设置变体为RFC4122
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    const hex = Array.from(bytes)
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');

    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  /**
   * 生成指定长度的随机密码
   * @param length 密码长度
   * @param includeUppercase 是否包含大写字母
   * @param includeLowercase 是否包含小写字母
   * @param includeNumbers 是否包含数字
   * @param includeSpecial 是否包含特殊字符
   * @returns 随机密码
   */
  public static generatePassword(
    length: number = 16,
    includeUppercase: boolean = true,
    includeLowercase: boolean = true,
    includeNumbers: boolean = true,
    includeSpecial: boolean = true
  ): string {
    const uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lowercase = 'abcdefghijklmnopqrstuvwxyz';
    const numbers = '0123456789';
    const special = '!@#$%^&*()_+-=[]{}|;:,.<>?';

    let chars = '';
    if (includeUppercase) chars += uppercase;
    if (includeLowercase) chars += lowercase;
    if (includeNumbers) chars += numbers;
    if (includeSpecial) chars += special;

    if (chars.length === 0) {
      throw new Error('至少需要选择一种字符类型');
    }

    let password = '';
    const randomBytes = RandomUtils.getRandomBytes(length);

    for (let i = 0; i < length; i++) {
      const randomIndex = randomBytes[i] % chars.length;
      password += chars[randomIndex];
    }

    // 确保密码包含所有要求的字符类型
    let missingTypes:string[] = [];
    if (includeUppercase && !password.match(/[A-Z]/)) missingTypes.push(uppercase);
    if (includeLowercase && !password.match(/[a-z]/)) missingTypes.push(lowercase);
    if (includeNumbers && !password.match(/[0-9]/)) missingTypes.push(numbers);
    if (includeSpecial && !password.match(/[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]/)) missingTypes.push(special);

    // 替换一些字符以满足所有要求
    for (let i = 0; i < missingTypes.length; i++) {
      const type = missingTypes[i];
      const pos = RandomUtils.getRandomInt(0, length - 1);
      const char = type[RandomUtils.getRandomInt(0, type.length - 1)];
      password = password.substring(0, pos) + char + password.substring(pos + 1);
    }

    return password;
  }
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
