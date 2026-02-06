
/**
 * KeePassHoError
 */
export class KeePassHoError extends Error {
  public readonly code: string;

  constructor(code: string, message?: string) {
    super('Error ' + code + (message ? ': ' + message : ''));

    this.name = 'KeePassHoError';
    this.code = code;
  }
}

/**
 * 错误码
 */
export enum ErrorCodes {
  FILE_NOT_PERMISSION = 'FILE_NOT_PERMISSION',
  FILE_EMPTY = 'FILE_EMPTY',
  FILE_PATH_EMPTY = 'FILE_PATH_EMPTY',
  UI_CONTEXT_NOT_INIT = "UI_CONTEXT_NOT_INIT",
  FILE_TYPE_NOT_SUPPORT = 'FILE_TYPE_NOT_SUPPORT',
  FILE_IMPORT_ERROR = 'FILE_IMPORT_ERROR',
  INVALID_CSV_HEADER = "INVALID_CSV_HEADER",
  READ_ONLY = "READ_ONLY",
}