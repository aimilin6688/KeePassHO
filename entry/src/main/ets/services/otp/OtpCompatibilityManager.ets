/**
 * OTP 兼容层管理器
 * 单例模式 + 自动注册机制
 */
import { KdbxEntry } from 'kdbxweb';
import { IOtpFieldParser } from './IOtpFieldParser';
import { KdbxUtils } from '../../common/utils/KdbxUtils';
import { OtpUrlParser } from './parsers/OtpUrlParser';
import { KeePass2Parser } from './parsers/KeePass2Parser';
import { KeeOtpParser } from './parsers/KeeOtpParser';
import { KeeTrayTotpParser } from './parsers/KeeTrayTotpParser';

/**
 * OTP 提取结果接口
 */
export interface OtpExtractionResult {
  urls: string[];
  processedFields: Set<string>;
}

/**
 * OTP 兼容层管理器（单例）
 */
export class OtpCompatibilityManager {
  private static instance: OtpCompatibilityManager | null = null;
  private parsers: IOtpFieldParser[] = [];

  /**
   * 私有构造函数（单例模式）
   */
  private constructor() {
    this.registerDefaultParsers();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): OtpCompatibilityManager {
    if (!OtpCompatibilityManager.instance) {
      OtpCompatibilityManager.instance = new OtpCompatibilityManager();
    }
    return OtpCompatibilityManager.instance;
  }

  /**
   * 自动注册所有内置解析器
   */
  private registerDefaultParsers(): void {
    this.parsers = [
      new OtpUrlParser(),       // 优先级 10
      new KeePass2Parser(),     // 优先级 20
      new KeeOtpParser(),       // 优先级 30
      new KeeTrayTotpParser(),  // 优先级 30
    ];
    // 按优先级排序（数字越小优先级越高）
    this.parsers.sort((a, b) => a.priority - b.priority);
  }

  /**
   * 核心提取逻辑：从条目中提取 OTP URL 及已处理的字段名
   * @param entry KeePass 条目
   * @returns 包含 OTPURL 数组和已处理字段名集合的对象
   */
  private doExtractOtpUrls(entry: KdbxEntry): OtpExtractionResult {
    const urls: string[] = [];
    const processedFields = new Set<string>();

    // 遍历所有解析器
    for (const parser of this.parsers) {
      entry.fields.forEach((value, key) => {
        // 跳过已处理的字段
        if (processedFields.has(key)) {
          return;
        }

        const valueStr = KdbxUtils.getValueString(value);
        if (parser.canParse(key, valueStr)) {
          try {
            const parsedUrls = parser.parse(key, valueStr, entry);
            urls.push(...parsedUrls);
            processedFields.add(key);
            // 从解析器获取关联字段并添加到已处理集合
            if (parser.associatedFields) {
              const associatedFields = parser.associatedFields.get(key);
              if (associatedFields) {
                for (const field of associatedFields) {
                  processedFields.add(field);
                }
              }
            }
          } catch (error) {
            // 静默忽略解析错误
          }
        }
      });
    }

    const result: OtpExtractionResult = { urls, processedFields };
    return result;
  }

  /**
   * 从条目中提取所有 OTP URL
   * @param entry KeePass 条目
   * @returns OTPURL 数组
   */
  public extractOtpUrls(entry: KdbxEntry): string[] {
    return this.doExtractOtpUrls(entry).urls;
  }

  /**
   * 从条目中提取所有 OTP URL 及已处理的字段名
   * @param entry KeePass 条目
   * @returns 包含 OTPURL 数组和已处理字段名集合的对象
   */
  public extractOtpUrlsWithProcessedFields(entry: KdbxEntry): OtpExtractionResult {
    return this.doExtractOtpUrls(entry);
  }

  /**
   * 注册自定义解析器（用于扩展）
   * @param parser 解析器实例
   */
  public registerParser(parser: IOtpFieldParser): void {
    this.parsers.push(parser);
    this.parsers.sort((a, b) => a.priority - b.priority);
  }

  /**
   * 获取所有已注册的解析器（用于测试）
   * @returns 解析器列表
   */
  public getParsers(): IOtpFieldParser[] {
    return [...this.parsers];
  }

  /**
   * 重置单例（仅用于测试）
   */
  public static resetInstance(): void {
    OtpCompatibilityManager.instance = null;
  }
}
