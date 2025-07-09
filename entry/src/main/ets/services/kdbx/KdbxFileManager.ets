import { IFileStorage, StorageType, FileStorageFactory, getDefaultStorage } from './interfaces';
// 导出FileInfo类型
import { FileInfo } from './interfaces/IFileStorage';
export { FileInfo };
/**
 * KDBX文件管理器
 * 用于处理KDBX文件的加载和保存
 */
export class KdbxFileManager {
  private storage: IFileStorage;

  /**
   * 构造函数
   * @param storageType 存储类型，默认为本地存储
   */
  constructor(storageType: StorageType = StorageType.LOCAL) {
    this.storage = FileStorageFactory.getInstance().getStorage(storageType);
  }

  /**
   * 加载KDBX文件
   * @param path 文件路径
   * @return Promise<ArrayBuffer> 文件内容
   * @throws 如果加载失败则抛出异常
   */
  public async loadKdbxFile(path: string): Promise<ArrayBuffer> {
    try {
      // 检查文件是否存在
      const exists = await this.storage.exists(path);
      if (!exists) {
        throw new Error(`KDBX file does not exist: ${path}`);
      }

      // 读取文件内容
      return this.storage.readFile(path);
    } catch (error) {
      throw new Error(`Failed to load KDBX file: ${error.message}`);
    }
  }

  /**
   * 保存KDBX文件
   * @param path 文件路径
   * @param content 文件内容
   * @throws 如果保存失败则抛出异常
   */
  public async saveKdbxFile(path: string, content: ArrayBuffer): Promise<void> {
    try {
      // 写入文件内容
      return this.storage.writeFile(path, content);
    } catch (error) {
      throw new Error(`Failed to save KDBX file: ${error.message}`);
    }
  }

  /**
   * 获取KDBX文件信息
   * @param path 文件路径
   * @return Promise<FileInfo> 文件信息
   * @throws 如果获取失败则抛出异常
   */
  public async getKdbxFileInfo(path: string): Promise<FileInfo> {
    try {
      return await this.storage.getFileInfo(path);
    } catch (error) {
      throw new Error(`Failed to get KDBX file info: ${error.message}`);
    }
  }

  /**
   * 切换存储类型
   * @param storageType 新的存储类型
   * @throws 如果指定类型的存储未注册则抛出异常
   */
  public switchStorage(storageType: StorageType): void {
    this.storage = FileStorageFactory.getInstance().getStorage(storageType);
  }

  /**
   * 检查文件是否存在
   * @param filePath 文件路径
   * @return Promise<boolean> 文件是否存在
   */
  public async exists(filePath: string): Promise<boolean> {
    return this.storage.exists(filePath);
  }
}



