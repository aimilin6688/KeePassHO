/**
 * KDBX错误代码
 */
export enum KdbxErrorCode {
  // 通用错误
  UNKNOWN = 'UNKNOWN',
  NOT_IMPLEMENTED = 'NOT_IMPLEMENTED',
  INVALID_ARGUMENT = 'INVALID_ARGUMENT',
  OPERATION_FAILED = 'OPERATION_FAILED',

  // 文件相关错误
  FILE_NOT_FOUND = 'FILE_NOT_FOUND',
  FILE_ACCESS_DENIED = 'FILE_ACCESS_DENIED',
  FILE_CORRUPTED = 'FILE_CORRUPTED',
  INVALID_FILE_FORMAT = 'INVALID_FILE_FORMAT',
  UNSUPPORTED_VERSION = 'UNSUPPORTED_VERSION',
  FILE_LOCKED = 'FILE_LOCKED',

  // 加密相关错误
  ENCRYPTION_FAILED = 'ENCRYPTION_FAILED',
  DECRYPTION_FAILED = 'DECRYPTION_FAILED',
  INVALID_KEY = 'INVALID_KEY',
  INVALID_CREDENTIALS = 'INVALID_CREDENTIALS',
  KEY_DERIVATION_FAILED = 'KEY_DERIVATION_FAILED',
  INVALID_KEYFILE = 'INVALID_KEYFILE',

  // 压缩相关错误
  COMPRESSION_FAILED = 'COMPRESSION_FAILED',
  DECOMPRESSION_FAILED = 'DECOMPRESSION_FAILED',

  // XML相关错误
  XML_PARSING_FAILED = 'XML_PARSING_FAILED',
  XML_WRITING_FAILED = 'XML_WRITING_FAILED',
  INVALID_XML_STRUCTURE = 'INVALID_XML_STRUCTURE',

  // 数据库相关错误
  DATABASE_CORRUPTED = 'DATABASE_CORRUPTED',
  INVALID_DATABASE_STRUCTURE = 'INVALID_DATABASE_STRUCTURE',
  DATABASE_NOT_LOADED = 'DATABASE_NOT_LOADED',
  ENTRY_NOT_FOUND = 'ENTRY_NOT_FOUND',
  GROUP_NOT_FOUND = 'GROUP_NOT_FOUND',
  DUPLICATE_UUID = 'DUPLICATE_UUID',
  INVALID_FIELD = 'INVALID_FIELD',

  // 内存相关错误
  OUT_OF_MEMORY = 'OUT_OF_MEMORY',
  MEMORY_CORRUPTION = 'MEMORY_CORRUPTION',

  // 并发相关错误
  CONCURRENT_ACCESS = 'CONCURRENT_ACCESS',
  TRANSACTION_FAILED = 'TRANSACTION_FAILED',

  // 网络相关错误
  NETWORK_ERROR = 'NETWORK_ERROR',
  CONNECTION_FAILED = 'CONNECTION_FAILED',
  TIMEOUT = 'TIMEOUT',
  INVALID_IV = "INVALID_IV",
  INVALID_DATA = "INVALID_DATA"
}

/**
 * KDBX错误类
 */
export class KdbxError extends Error {
  /**
   * 错误代码
   */
  code: KdbxErrorCode;
  /**
   * 原始错误
   */
  originalError?: Error;
  /**
   * 额外信息
   */
  details?: object;

  /**
   * 构造函数
   * @param code 错误代码
   * @param message 错误消息
   * @param originalError 原始错误
   * @param details 额外信息
   */
  constructor(
    code: KdbxErrorCode = KdbxErrorCode.UNKNOWN,
    message?: string,
    originalError?: Error,
    details?: object
  ) {
    super(message || KdbxError.getDefaultMessage(code));
    this.name = 'KdbxError';
    this.code = code;
    this.originalError = originalError;
    this.details = details;
  }

  /**
   * 获取错误的默认消息
   * @param code 错误代码
   * @returns 默认错误消息
   */
  private static getDefaultMessage(code: KdbxErrorCode): string {
    switch (code) {
      // 通用错误
      case KdbxErrorCode.UNKNOWN:
        return '未知错误';
      case KdbxErrorCode.NOT_IMPLEMENTED:
        return '功能尚未实现';
      case KdbxErrorCode.INVALID_ARGUMENT:
        return '无效的参数';
      case KdbxErrorCode.OPERATION_FAILED:
        return '操作失败';

    // 文件相关错误
      case KdbxErrorCode.FILE_NOT_FOUND:
        return '文件未找到';
      case KdbxErrorCode.FILE_ACCESS_DENIED:
        return '文件访问被拒绝';
      case KdbxErrorCode.FILE_CORRUPTED:
        return '文件已损坏';
      case KdbxErrorCode.INVALID_FILE_FORMAT:
        return '无效的文件格式';
      case KdbxErrorCode.UNSUPPORTED_VERSION:
        return '不支持的文件版本';
      case KdbxErrorCode.FILE_LOCKED:
        return '文件已被锁定';

    // 加密相关错误
      case KdbxErrorCode.ENCRYPTION_FAILED:
        return '加密失败';
      case KdbxErrorCode.DECRYPTION_FAILED:
        return '解密失败';
      case KdbxErrorCode.INVALID_KEY:
        return '无效的密钥';
      case KdbxErrorCode.INVALID_CREDENTIALS:
        return '无效的凭证';
      case KdbxErrorCode.KEY_DERIVATION_FAILED:
        return '密钥派生失败';
      case KdbxErrorCode.INVALID_KEYFILE:
        return '无效的密钥文件';

    // 压缩相关错误
      case KdbxErrorCode.COMPRESSION_FAILED:
        return '压缩失败';
      case KdbxErrorCode.DECOMPRESSION_FAILED:
        return '解压缩失败';

    // XML相关错误
      case KdbxErrorCode.XML_PARSING_FAILED:
        return 'XML解析失败';
      case KdbxErrorCode.XML_WRITING_FAILED:
        return 'XML写入失败';
      case KdbxErrorCode.INVALID_XML_STRUCTURE:
        return '无效的XML结构';

    // 数据库相关错误
      case KdbxErrorCode.DATABASE_CORRUPTED:
        return '数据库已损坏';
      case KdbxErrorCode.INVALID_DATABASE_STRUCTURE:
        return '无效的数据库结构';
      case KdbxErrorCode.DATABASE_NOT_LOADED:
        return '数据库未加载';
      case KdbxErrorCode.ENTRY_NOT_FOUND:
        return '条目未找到';
      case KdbxErrorCode.GROUP_NOT_FOUND:
        return '组未找到';
      case KdbxErrorCode.DUPLICATE_UUID:
        return '重复的UUID';
      case KdbxErrorCode.INVALID_FIELD:
        return '无效的字段';

    // 内存相关错误
      case KdbxErrorCode.OUT_OF_MEMORY:
        return '内存不足';
      case KdbxErrorCode.MEMORY_CORRUPTION:
        return '内存损坏';

    // 并发相关错误
      case KdbxErrorCode.CONCURRENT_ACCESS:
        return '并发访问冲突';
      case KdbxErrorCode.TRANSACTION_FAILED:
        return '事务失败';

    // 网络相关错误
      case KdbxErrorCode.NETWORK_ERROR:
        return '网络错误';
      case KdbxErrorCode.CONNECTION_FAILED:
        return '连接失败';
      case KdbxErrorCode.TIMEOUT:
        return '操作超时';

      default:
        return '发生错误';
    }
  }

  /**
   * 获取错误处理建议
   * @returns 错误处理建议
   */
  getSuggestion(): string {
    switch (this.code) {
      case KdbxErrorCode.FILE_NOT_FOUND:
        return '请检查文件路径是否正确，文件是否存在。';

      case KdbxErrorCode.FILE_ACCESS_DENIED:
        return '请检查文件权限，确保应用有足够的访问权限。';

      case KdbxErrorCode.INVALID_CREDENTIALS:
        return '请检查密码或密钥文件是否正确。';

      case KdbxErrorCode.INVALID_KEYFILE:
        return '请确保使用有效的密钥文件格式（XML、二进制或十六进制）。';

      case KdbxErrorCode.DATABASE_CORRUPTED:
      case KdbxErrorCode.FILE_CORRUPTED:
        return '数据库文件可能已损坏，请尝试使用备份文件恢复。';

      case KdbxErrorCode.OUT_OF_MEMORY:
        return '请关闭其他应用释放内存，或增加设备内存。';

      case KdbxErrorCode.NETWORK_ERROR:
      case KdbxErrorCode.CONNECTION_FAILED:
        return '请检查网络连接是否正常。';

      case KdbxErrorCode.TIMEOUT:
        return '请检查网络连接，或稍后重试。';

      default:
        return '如果问题持续存在，请联系技术支持。';
    }
  }

  /**
   * 获取完整的错误信息
   * @returns 完整的错误信息
   */
  getFullMessage(): string {
    let message = `${this.message}\n错误代码: ${this.code}`;

    if (this.details) {
      message += `\n详细信息: ${JSON.stringify(this.details)}`;
    }

    if (this.originalError) {
      message += `\n原始错误: ${this.originalError.message}`;
      if (this.originalError.stack) {
        message += `\n堆栈跟踪: ${this.originalError.stack}`;
      }
    }

    message += `\n处理建议: ${this.getSuggestion()}`;

    return message;
  }

  /**
   * 创建一个新的KdbxError实例
   * @param code 错误代码
   * @param message 错误消息
   * @param originalError 原始错误
   * @param details 额外信息
   * @returns KdbxError实例
   */
  static create(
    code: KdbxErrorCode,
    message?: string,
    originalError?: Error,
    details?: ESObject
  ): KdbxError {
    return new KdbxError(code, message, originalError, details);
  }

  /**
   * 包装一个错误为KdbxError
   * @param error 原始错误
   * @param code 错误代码
   * @param message 额外消息
   * @param details 额外信息
   * @returns KdbxError实例
   */
  static wrap(
    error: Error,
    code: KdbxErrorCode = KdbxErrorCode.UNKNOWN,
    message?: string,
    details?: ESObject
  ): KdbxError {
    return new KdbxError(
      code,
      message || error.message,
      error,
      details
    );
  }
}
