import { FileContentInfo, FileStorageFactory, IFileStorage, StorageConfig, StorageType } from './interfaces';
// 导出FileInfo类型
import { FileInfo } from './interfaces/IFileStorage';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ResourceManager from '../../common/utils/ResourceManager';


const DOMAIN = 0x0000;
const TAG = 'WebDavClient';

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
  constructor(storageType: StorageType = StorageType.LOCAL, storageConfig?: StorageConfig) {
    this.storage = FileStorageFactory.getInstance().getStorage(storageType);
    if (storageConfig) {
      this.init(storageConfig);
    }
  }

  /**
   * 初始化存储
   * @param storageConfig
   */
  public init(storageConfig: StorageConfig): KdbxFileManager {
    this.storage.init(storageConfig);
    return this;
  }

  /**
   * 加载KDBX文件
   * @param path 文件路径
   * @return Promise<ArrayBuffer> 文件内容
   * @throws 如果加载失败则抛出异常
   */
  public async read(path: string): Promise<FileContentInfo> {
    try {
      // 检查文件是否存在
      const fileInfo = await this.storage.getInfo(path);
      if (!fileInfo) {
        hilog.error(DOMAIN, TAG, 'KDBX file does not exist: %{public}s', path);
        throw new Error(ResourceManager.getString($r('app.string.file_not_exists')));
      }
      // 读取文件内容
      const content = await this.storage.read(path);
      // 返回文件内容
      return new FileContentInfo(fileInfo, content);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load KDBX file: %{public}s', error.message)
      throw new Error(error.message);
    }
  }

  /**
   * 保存KDBX文件
   * @param path 文件路径
   * @param content 文件内容
   * @throws 如果保存失败则抛出异常
   */
  public async write(path: string, content: ArrayBuffer): Promise<void> {
    try {
      // 写入文件内容
      return this.storage.write(path, content);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to save KDBX file: %{public}s', error.message)
      throw new Error(error.message);
    }
  }

  /**
   * 获取KDBX文件信息
   * @param path 文件路径
   * @return Promise<FileInfo> 文件信息
   * @throws 如果获取失败则抛出异常
   */
  public async getInfo(path: string): Promise<FileInfo> {
    try {
      return await this.storage.getInfo(path);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to get KDBX file info: %{public}s', error.message)
      throw new Error(error.message);
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



