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
  /**
   * 认证过期（refresh_token 失效），需重新登录授权
   */
  AUTH_EXPIRED = 'AUTH_EXPIRED',
  /**
   * 条件写入失败：远端版本与 expectedVersion 不一致（已被其他设备修改）
   */
  VERSION_CONFLICT = 'VERSION_CONFLICT',
}