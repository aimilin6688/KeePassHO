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
   * 流式读取文件到本地目标路径（分块下载/复制，避免整缓冲驻留内存）
   * 默认实现包装 read()（整缓冲）；适配器按需迁移为真正的流式下载
   * @param path 远端文件路径
   * @param destPath 本地目标文件路径（调用方负责生命周期）
   * @param onProgress 下载进度回调（可选，opt-in 能力）；未实现/未传入时不影响读取语义
   * @return Promise<FileInfo> 远端文件信息（含 version）
   * @throws 如果读取失败则抛出异常
   */
  readToFile(path: string, destPath: string, onProgress?: TransferProgressCallback): Promise<FileInfo>;

  /**
   * 写入文件内容
   * @param path 文件路径
   * @param content 文件内容
   * @param option 写入选项，传入 expectedVersion 时支持条件写入（写入前校验远端版本，不一致抛出 VERSION_CONFLICT）
   * @param onProgress 上传进度回调（可选，opt-in 能力）；未实现/未传入时不影响写入语义
   * @throws 如果写入失败则抛出异常
   */
  write(path: string, content: ArrayBuffer, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<void>;

  /**
   * 流式从本地源文件写入到远端（分块上传/复制，避免整缓冲驻留内存）
   * 默认实现包装 write()（整缓冲）；适配器按需迁移为真正的流式上传
   * @param path 远端文件路径
   * @param srcPath 本地源文件路径
   * @param option 写入选项，支持条件写入
   * @param onProgress 上传进度回调（可选，opt-in 能力）；未实现/未传入时不影响写入语义
   * @return Promise<FileInfo> 写入后的远端文件信息（含 version）
   * @throws 如果写入失败则抛出异常
   */
  writeFromFile(path: string, srcPath: string, option?: WriteOption, onProgress?: TransferProgressCallback): Promise<FileInfo>;

  /**
   * 检查文件是否存在
   * @param path 文件路径
   * @return Promise<boolean> 文件是否存在
   */
  exists(path: string): Promise<boolean>;

  /**
   * 获取文件信息；文件确定不存在时返回 null，无法判定（网络错误、令牌失效等）时抛异常。
   * 契约成员：所有实现必须提供（继承 BaseFileStorage 时为抽象原语，exists/getInfo 由基类派生）。
   * 语义约束：必须与 getInfo 同源（同一次请求形态），禁止把一切异常映射为 null。
   * @param path 文件路径
   * @return Promise<FileInfo | null> 文件信息，确定不存在时为 null
   */
  getInfoOrNull(path: string): Promise<FileInfo | null>;

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

  /**
   * 声明本存储的 FileInfo.version 是否可信可用于保存链路的版本预检快速路径
   * （版本相等即可跳过"全量下载 + 内容哈希"的冲突校验，配合条件写入写前复核兜底）。
   * 可选能力成员：未实现视为 false（保持全量校验语义，行为不变）。
   * 由具体存储实现自行 opt-in（能力协商），编排层不含任何 provider 分支；
   * 返回 true 的实现须同时保证：version 随内容变化（不同内容必产生不同 version）
   * 且 write/writeFromFile 履约 expectedVersion 条件写入。
   */
  supportsVersionFastPath?(): boolean;

  /**
   * 版本快速路径（加载链路）：本地缓存元数据与远端版本+尺寸一致时，把缓存内容复制到 destPath，
   * 返回 true（命中），调用方据此跳过全量下载；否则返回 false（miss），调用方回落 readToFile。
   * 可选能力成员：仅 CacheStorage 装饰器实现，其余实现视为 false（LOCAL 天然无需缓存快速路径）。
   * 命中前提（实现方保证）：本地缓存开关开启、非 only_use_cache、非 force_refresh（命中判定时消费一次性标志）、
   * 缓存元数据存在且 version 与 size 同时匹配、缓存文件本地拷贝成功。
   * @param path 远端路径
   * @param destPath 本地目标路径
   * @param expectedVersion 远端当前版本（调用方由守卫 getInfo 取得的事实）
   * @param expectedSize 远端当前大小（版本之外的第二道防线）
   * @return Promise<boolean> true 表示命中（destPath 已就绪），false 表示未命中
   */
  readCacheToFile?(path: string, destPath: string, expectedVersion: string,
    expectedSize: number): Promise<boolean>;
}

/**
 * 传输进度回调（方向中立：下载已接收字节 / 上传已发送字节）
 * 仅在流式 readToFile/writeFromFile 链路中作为可选能力透传；
 * 未实现/未传入时存储行为完全不变
 * @param transferredBytes 已传输字节（下载=已接收，上传=已确认）
 * @param totalBytes 总字节
 */
export type TransferProgressCallback = (transferredBytes: number, totalBytes: number) => void;

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
