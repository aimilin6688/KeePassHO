/**
 * 存储类型枚举
 * 定义了支持的文件存储类型
 */
export enum StorageType {
  /**
   * 本地文件存储
   */
  LOCAL = 'LOCAL',

  /**
   * WebDAV存储
   */
  WEBDAV = 'WEBDAV',

  /**
   * FTP存储
   */
  FTP = 'FTP',

  /**
   * Microsoft OneDrive存储
   */
  ONEDRIVE = 'ONEDRIVE'
}
