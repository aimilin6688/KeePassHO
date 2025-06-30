import { IFileStorage } from './IFileStorage';
import { LocalFileStorage } from './impl/LocalFileStorage';
import { StorageType } from './StorageType';

/**
 * 文件存储工厂类
 * 用于创建和管理不同类型的文件存储实现
 */
export class FileStorageFactory {
  private static instance: FileStorageFactory;
  private storageMap: Map<StorageType, IFileStorage> = new Map();

  private constructor() {
    // 注册默认的存储实现
    this.registerStorage(StorageType.LOCAL, new LocalFileStorage());
  }

  /**
   * 获取工厂实例（单例模式）
   */
  public static getInstance(): FileStorageFactory {
    if (!FileStorageFactory.instance) {
      FileStorageFactory.instance = new FileStorageFactory();
    }
    return FileStorageFactory.instance;
  }

  /**
   * 注册存储实现
   * @param type 存储类型
   * @param storage 存储实现
   */
  public registerStorage(type: StorageType, storage: IFileStorage): void {
    this.storageMap.set(type, storage);
  }

  /**
   * 获取存储实现
   * @param type 存储类型
   * @return IFileStorage 存储实现
   * @throws 如果指定类型的存储未注册则抛出异常
   */
  public getStorage(type: StorageType): IFileStorage {
    const storage = this.storageMap.get(type);
    if (!storage) {
      throw new Error(`Storage type ${type} is not registered`);
    }
    return storage;
  }

  /**
   * 检查指定类型的存储是否已注册
   * @param type 存储类型
   * @return boolean 是否已注册
   */
  public hasStorage(type: StorageType): boolean {
    return this.storageMap.has(type);
  }
}
