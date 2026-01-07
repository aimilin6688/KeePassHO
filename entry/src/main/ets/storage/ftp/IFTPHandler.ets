/**
 * 文件信息接口
 */
export interface FileItemInfo {
  name: string;
  size: number;
  isDirectory: boolean;
  modifiedTime: number;
}

/**
 * 存储处理器接口
 * 定义了FTP和SFTP处理器需要实现的通用方法
 */
export interface IFTPHandler {
  /**
   * 连接到服务器
   */
  connect(): Promise<void>;

  /**
   * 关闭连接
   */
  close(): Promise<void>;

  /**
   * 从远程路径下载文件到本地
   */
  downloadFrom(remotePath: string, localPath: string): Promise<void>;

  /**
   * 从本地上传文件到远程路径
   */
  uploadTo(localPath: string, remotePath: string): Promise<void>;

  /**
   * 检查路径是否存在
   */
  exists(path: string): Promise<boolean>;

  /**
   * 获取文件信息
   */
  getFileInfo(path: string): Promise<FileItemInfo>;

  /**
   * 列出目录内容
   */
  listDir(path: string): Promise<Array<FileItemInfo>>;
}
