/**
 * OTP 字段解析器接口
 * 采用策略模式，每种 OTP 格式一个解析器
 */
import { KdbxEntry } from 'kdbxweb';

/**
 * OTP 字段解析器接口
 */
export interface IOtpFieldParser {
  /**
   * 解析器名称（用于日志和调试）
   */
  readonly name: string;

  /**
   * 优先级（数字越小优先级越高）
   * - 10: 标准 OTPURL（最高优先级）
   * - 20: KeePass2 原生字段
   * - 30: KeeOTP、KeeTrayTotp 等
   */
  readonly priority: number;

  /**
   * 关联字段列表（当主字段被解析时，这些字段也应该被隐藏）
   * key: 主字段名，value: 关联字段名列表
   */
  readonly associatedFields?: Map<string, string[]>;

  /**
   * 判断是否能解析该字段
   * @param fieldName 字段名称
   * @param fieldValue 字段值
   * @returns 是否能解析
   */
  canParse(fieldName: string, fieldValue: string): boolean;

  /**
   * 解析指定字段的 OTP 数据，返回标准 OTPURL 数组
   * @param fieldName 字段名称
   * @param fieldValue 字段值
   * @param entry KeePass 条目（用于获取相关字段如 Title）
   * @returns OTPURL 数组（可能为空）
   */
  parse(fieldName: string, fieldValue: string, entry: KdbxEntry): string[];
}
