/**
 * 导入导出错误码
 */
export enum ImportExportErrorCode {
  // 通用错误
  FILE_NOT_FOUND = 'FILE_NOT_FOUND',
  FILE_READ_ERROR = 'FILE_READ_ERROR',
  FILE_WRITE_ERROR = 'FILE_WRITE_ERROR',
  UNSUPPORTED_FORMAT = 'UNSUPPORTED_FORMAT',
  FILE_EMPTY = 'FILE_EMPTY',

  // 导入错误
  INVALID_FILE_FORMAT = 'INVALID_FILE_FORMAT',
  INVALID_CSV_HEADER = 'INVALID_CSV_HEADER',
  INVALID_JSON_FORMAT = 'INVALID_JSON_FORMAT',
  PARSE_ERROR = 'PARSE_ERROR',

  // 导出错误
  EXPORT_FAILED = 'EXPORT_FAILED',
  DATABASE_EMPTY = 'DATABASE_EMPTY',
}

/**
 * 导入错误
 */
export class ImportError extends Error {
  constructor(
    public readonly code: ImportExportErrorCode,
    message: string
  ) {
    super(message);
    this.name = 'ImportError';
  }
}

/**
 * 导出错误
 */
export class ExportError extends Error {
  constructor(
    public readonly code: ImportExportErrorCode,
    message: string
  ) {
    super(message);
    this.name = 'ExportError';
  }
}
