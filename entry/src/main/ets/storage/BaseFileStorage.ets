import { FileInfo, IFileStorage, TransferProgressCallback, WriteOption } from './IFileStorage';
import { PageConfig, StorageConfig } from './StorageConfig';
import { FileTransfer } from './FileTransfer';
import { StorageError, StorageErrorCodes } from './StorageError';

/**
 * 文件存储抽象基类
 *
 * 收拢 IFileStorage 中可由原语派生的成员，消除各实现重复手写的样板代码：
 * - 存在性探测原语 getInfoOrNull：抽象成员，由具体存储实现（唯一权威来源）
 * - exists / getInfo：由 getInfoOrNull 派生（"确定不存在"与"无法判定"的区分由原语负责）
 * - readToFile / writeFromFile：默认整缓冲包装（FileTransfer）；已迁移真正流式的存储覆写
 * - supportsVersionFastPath：默认 false（能力协商，由可信版本标识的存储覆写为 true）
 *
 * 新增存储实现时只需继承本类并提供 6 个抽象原语。
 */
export abstract class BaseFileStorage implements IFileStorage {

  /**
   * 获取页面配置
   * @return PageConfig 页面配置
   */
  abstract getPageConfig(): PageConfig;

  /**
   * 初始化存储配置
   * @param config 存储配置
   */
  abstract init(config: StorageConfig): void;

  /**
   * 读取文件内容（整缓冲）
   * @param path 文件路径
   * @return Promise<ArrayBuffer> 文件内容
   * @throws 如果读取失败则抛出异常
   */
  abstract read(path: string): Promise<ArrayBuffer>;

  /**
   * 写入文件内容（整缓冲）
   * @param path 文件路径
   * @param content 文件内容
   * @param option 写入选项，支持条件写入（expectedVersion 不一致抛出 VERSION_CONFLICT）
   * @throws 如果写入失败则抛出异常
   */
  abstract write(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void>;

  /**
   * 获取文件信息；文件确定不存在时返回 null，无法判定（网络错误、令牌失效等）时抛异常。
   * 存在性探测的唯一权威原语：必须与实际请求形态同源，禁止把一切异常映射为 null。
   * @param path 文件路径
   * @return Promise<FileInfo | null> 文件信息，确定不存在时为 null
   */
  abstract getInfoOrNull(path: string): Promise<FileInfo | null>;

  /**
   * 获取目录内容
   * @param path 目录路径
   * @return Promise<Array<FileInfo>> 目录内容
   * @throws 如果获取失败则抛出异常
   */
  abstract listDir(path: string): Promise<Array<FileInfo>>;

  /**
   * 获取文件信息（由 getInfoOrNull 派生）
   * @param path 文件路径
   * @return Promise<FileInfo> 文件信息
   * @throws StorageError(FILE_INFO_ERROR) 文件确定不存在时抛出
   */
  public async getInfo(path: string): Promise<FileInfo> {
    const info: FileInfo | null = await this.getInfoOrNull(path);
    if (info === null) {
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, `File not found: ${path}`);
    }
    return info;
  }

  /**
   * 检查文件是否存在（由 getInfoOrNull 派生；"无法判定"错误原样上抛）
   * @param path 文件路径
   * @return Promise<boolean> 文件是否存在
   */
  public async exists(path: string): Promise<boolean> {
    return (await this.getInfoOrNull(path)) !== null;
  }

  /**
   * 流式读取文件到本地目标路径（默认实现：read() 整缓冲落盘）
   * 迁移为真正流式下载的存储覆写本方法
   * @param path 远端文件路径
   * @param destPath 本地目标文件路径（调用方负责生命周期）
   * @param onProgress 下载进度回调（可选，opt-in 能力）；默认实现不产生进度事件
   * @return Promise<FileInfo> 远端文件信息（含 version）
   */
  public async readToFile(path: string, destPath: string, onProgress?: TransferProgressCallback): Promise<FileInfo> {
    return FileTransfer.readToFileDefault(this, path, destPath);
  }

  /**
   * 流式从本地源文件写入到远端（默认实现：读源文件整缓冲后 write()）
   * 迁移为真正流式上传的存储覆写本方法
   * @param path 远端文件路径
   * @param srcPath 本地源文件路径
   * @param option 写入选项，支持条件写入
   * @param onProgress 上传进度回调（可选，opt-in 能力）；默认实现不产生进度事件
   * @return Promise<FileInfo> 写入后的远端文件信息（含 version）
   */
  public async writeFromFile(path: string, srcPath: string, option?: WriteOption, onProgress?: TransferProgressCallback): Promise<FileInfo> {
    return FileTransfer.writeFromFileDefault(this, path, srcPath, option);
  }

  /**
   * 声明本存储的 FileInfo.version 是否可信可用于保存链路的版本预检快速路径
   * 默认 false（保持全量校验语义）；由具备可信版本标识的存储覆写为 true
   */
  public supportsVersionFastPath(): boolean {
    return false;
  }

  /**
   * 版本快速路径（加载链路）默认不参与（默认 false → miss → 调用方走 readToFile 全量读取）。
   * 仅 CacheStorage 装饰器覆写；LOCAL 等不经缓存装饰的存储天然无需该能力。
   * @return Promise<boolean> 恒 false（未命中）
   */
  public readCacheToFile(path: string, destPath: string, expectedVersion: string,
    expectedSize: number): Promise<boolean> {
    return Promise.resolve(false);
  }
}
