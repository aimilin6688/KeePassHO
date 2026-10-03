import { PageConfig, StorageConfig } from '.';

/**
 * 文件存储接口
 * 定义了文件操作的基本行为，支持不同的存储方式（本地文件、WebDAV、FTP等）
 */
export interface IFileStorage {

  /**
   * 获取页面配置
   * @return PageConfig 页面配置
   */
  getPageConfig(): PageConfig;

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
   * @param option 写入选项，传入 expectedVersion 时支持条件写入（写入前校验远端版本，不一致抛出 VERSION_CONFLICT）
   * @throws 如果写入失败则抛出异常
   */
  write(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void>;

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
 * 写入选项
 */
export interface WriteOption {
  /**
   * 期望的远端当前版本（来自上次 read/getInfo 的 FileInfo.version）
   * 传入后由存储实现决定校验方式：支持原生条件写的存储在服务端原子校验，
   * 不支持的存储在写入前重新获取版本比对（写前复核），不一致时抛出 VERSION_CONFLICT
   */
  expectedVersion?: string | null;
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

  /**
   * 存储原生版本标识（不透明字符串，仅用于相等比较，不可解析其内容）
   * 各存储实现自定义语义（如 ETag、Last-Modified、size+mtime 复合串），
   * 无此能力的存储返回 null，由上层用内容哈希兜底
   */
  version?: string | null;
}

/**
 * 文件类型
 */
export enum FileType {
  DIR = "DIR",
  FILE = "FILE"
}

/**
 * 文件信息实现类
 * 用于创建 FileInfo 对象
 */
export class FileInfoImpl implements FileInfo {
  name: string = '';
  size: number = 0;
  modifiedTime: number = 0;
  path: string = '';
  type: FileType = FileType.FILE;
  childrenCount: number = 0;
  version: string | null = null;
}

/**
 * 文件内容信息
 */
export class FileContentInfo implements FileInfo {
  name: string = '';
  size: number = 0;
  modifiedTime: number = 0;
  path: string = '';
  content: ArrayBuffer = new ArrayBuffer(0);
  type: FileType = FileType.FILE;
  childrenCount: number = 0;
  version: string | null = null;

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
    this.version = fileInfo.version ?? null;
  }

  get fileInfo(): FileInfo {
    const info = new FileInfoImpl();
    info.name = this.name;
    info.size = this.size;
    info.modifiedTime = this.modifiedTime;
    info.path = this.path;
    info.type = this.type;
    info.childrenCount = this.childrenCount;
    info.version = this.version;
    return info;
  }
}
