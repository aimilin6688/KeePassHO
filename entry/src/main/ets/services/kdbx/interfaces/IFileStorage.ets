import { StorageConfig } from ".";

/**
 * 文件存储接口
 * 定义了文件操作的基本行为，支持不同的存储方式（本地文件、WebDAV、FTP等）
 */
export interface IFileStorage {

  /**
   * 初始化存储配置
   * @param config
   */
  init(config: StorageConfig): void;

  /**
   * 读取文件内容
   * @param path 文件路径
   * @return Promise<ArrayBuffer> 文件内容
   * @throws 如果读取失败则抛出异常
   */
  read(path: string): Promise<ArrayBuffer>;

  /**
   * 写入文件内容
   * @param path 文件路径
   * @param content 文件内容
   * @throws 如果写入失败则抛出异常
   */
  write(path: string, content: ArrayBuffer): Promise<void>;

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
  getInfo(path: string): Promise<FileInfo>;

  /**
   * 获取目录内容
   * @param path 目录路径
   * @return Promise<Array<FileInfo>> 目录内容
   * @throws 如果获取失败则抛出异常
   */
  listDir(path: string): Promise<Array<FileInfo>>;
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
   * 最后修改时间,单位为毫秒
   */
  modifiedTime: number;

  /**
   * 文件路径
   */
  path: string;

  /**
   * 类型：DIR - 文件夹， FILE - 文件
   */
  type: FileType;

  /**
   * 文件夹子节点个数
   */
  childrenCount: number;
}

/**
 * 文件类型
 */
export enum FileType {
  DIR = "DIR",
  FILE = "FILE"
}

/**
 * 文件内容信息
 */
export class FileContentInfo implements FileInfo {
  name: string;
  size: number;
  modifiedTime: number;
  path: string;
  content: ArrayBuffer;
  type: FileType;
  childrenCount: number;

  /**
   * 文件内容信息
   * @param fileInfo 文件信息
   * @param content 数据库内容
   */
  constructor(fileInfo: FileInfo, content: ArrayBuffer) {
    this.name = fileInfo.name;
    this.size = fileInfo.size;
    this.modifiedTime = fileInfo.modifiedTime;
    this.path = fileInfo.path;
    this.content = content;
    this.type = fileInfo.type;
    this.childrenCount = fileInfo.childrenCount;
  }

  get fileInfo(): FileInfo {
    return {
      name: this.name,
      size: this.size,
      modifiedTime: this.modifiedTime,
      path: this.path,
      type: this.type,
      childrenCount: this.childrenCount
    };
  }
}
