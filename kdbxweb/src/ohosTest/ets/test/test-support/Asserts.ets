import { ByteUtils } from "../../../../main/ets";

/**
 * 自定义断言
 * @file: Asserts.ets
 */
type allExpectType = Object | undefined | null

/**
 * 自定义断言
 * @param actual
 * @returns
 */
export function expects(actual: allExpectType | Function): Asserts {
  return new Asserts(actual);
}


export class Asserts {
  private actual: allExpectType

  constructor(actual: allExpectType) {
    this.actual = actual
  }

  /**
   * 验证值在指定范围内（包含边界）
   * @param actual 实际值
   * @param min 最小值
   * @param max 最大值
   * @param message 可选错误信息
   */
  public assertWithinRange(min: number, max: number, message?: string): void {
    const actual = this.actual as number;
    if (actual < min || actual > max) {
      throw new Error(message || `Expected value between ${min}-${max}, but got ${actual}`);
    }
  }

  /**
   * 验证字符串匹配正则表达式
   * @param actual 实际字符串
   * @param pattern 正则表达式
   * @param message 可选错误信息
   */
  public assertMatchPattern(pattern: RegExp, message?: string): void {
    const actual = this.actual as string;
    if (!pattern.test(actual)) {
      throw new Error(message || `"${actual}" does not match pattern ${pattern}`);
    }
  }

  /**
   * 验证对象是否为指定类型
   * @param actual
   * @param expected
   * @param message
   */
  public assertInstanceOf(expected: ESObject, message?: string): void {
    if (!(this.actual instanceof expected)) {
      throw new Error(message || `Expected ${this.actual} to be an instance of ${expected}`);
    }
  }

  /**
   * 验证字符串是否包含指定字符串
   * @param actual
   * @param expected
   * @param message
   */
  public assertContain(expected: string, message?: string): void {
    const actual = this.actual as string;
    if (actual.indexOf(expected) === -1) {
      throw new Error(message || `Expected ${actual} to contain ${expected}`);
    }
  }

  /**
   * 验证函数是否抛出错误
   * @param func
   * @param message
   */
  public assertThrowError(func: Function, message?: string): void {
    try {
      if (typeof this.actual === 'function') {
        this.actual();
      }
    } catch (e) {
      func(e);
      return;
    }
    throw new Error(message || `Expected ${func} to throw an error`);
  }

  /**
   * 验证数组是否相等
   * @param actual
   * @param expected
   * @param message
   */
  public assertArrayEqual(expected: Uint8Array, message?: string): void {
    const actual = this.actual as Uint8Array;
    if(!ByteUtils.arrayBufferEquals(actual, expected)){
      throw new Error(message || `Expected ${actual} equal to ${expected}`);
    }
  }
}