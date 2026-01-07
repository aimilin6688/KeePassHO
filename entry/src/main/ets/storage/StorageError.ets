/**
 * KeePassHoError
 */
export class StorageError extends Error {
  public readonly code: string;

  constructor(code: string, message?: string) {
    super('Error ' + code + (message ? ': ' + message : ''));

    this.name = 'StorageError';
    this.code = code;
  }
}

/**
 * 错误码
 */
export enum StorageErrorCodes {
  FILE_READ_ERROR = 'FILE_READ_ERROR',
  FILE_WRITE_ERROR = 'FILE_WRITE_ERROR',
  FILE_INFO_ERROR = 'FILE_INFO_ERROR',
  NOT_IMPLEMENTED = 'NOT_IMPLEMENTED',
  CLIENT_UNDEFINED = 'CLIENT_UNDEFINED',
  CONNECT_ERROR = 'CONNECT_ERROR',
}