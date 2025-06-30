/**
 * 文件存储接口
 * 定义了文件操作的基本行为，支持不同的存储方式（本地文件、WebDAV、FTP等）
 */
export interface IFileStorage {
  /**
   * 读取文件内容
   * @param path 文件路径
   * @return Promise<ArrayBuffer> 文件内容
   * @throws 如果读取失败则抛出异常
   */
  readFile(path: string): Promise<ArrayBuffer>;

  /**
   * 写入文件内容
   * @param path 文件路径
   * @param content 文件内容
   * @throws 如果写入失败则抛出异常
   */
  writeFile(path: string, content: ArrayBuffer): Promise<void>;

  /**
   * 检查文件是否存在
   * @param path 文件路径
   * @return Promise<boolean> 文件是否存在
   */
  exists(path: string): Promise<boolean>;

  /**
   * 获取文件信息
   * @param path 文件路径
   * @return Promise<FileInfo> 文件信息
   * @throws 如果获取失败则抛出异常
   */
  getFileInfo(path: string): Promise<FileInfo>;
}

/**
 * 文件信息接口
 */
export interface FileInfo {
  /**
   * 文件名
   */
  name: string;

  /**
   * 文件大小（字节）
   */
  size: number;

  /**
   * 最后修改时间
   */
  modifiedTime: Date;

  /**
   * 文件路径
   */
  path: string;
}
