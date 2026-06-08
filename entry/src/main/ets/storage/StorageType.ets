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
  ONEDRIVE = 'ONEDRIVE',

  /**
   * S3兼容存储
   */
  S3 = 'S3',

  /**
   * pCloud云存储
   */
  PCLOUD = 'PCLOUD',

  /**
   * 百度网盘存储
   */
  BAIDU_NETDISK = 'BAIDU_NETDISK'
}
