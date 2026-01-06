import { IFileStorage, PageConfig, StorageType } from './index';
import { LocalFileStorage } from './local/LocalFileStorage';
import { WebDAVStorage } from './webdav/WebDAVStorage';
import { OneDriveStorage } from './onedrive/OneDriveStorage';
import { FTPStorage } from './ftp/FTPStorage';

/**
 * 文件存储工厂类
 * 用于创建和管理不同类型的文件存储实现
 */
export class FileStorageFactory {
  private static instance: FileStorageFactory;
  private storageMap: Map<StorageType, IFileStorage> = new Map();

  /**
   * 私有构造函数
   */
  private constructor() {
    this.registerStorage(StorageType.LOCAL, new LocalFileStorage());
    this.registerStorage(StorageType.WEBDAV, new WebDAVStorage());
    this.registerStorage(StorageType.ONEDRIVE, new OneDriveStorage());
    this.registerStorage(StorageType.FTP, new FTPStorage());
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
   * 删除存储实现
   * @param type 存储类型
   * @param storage 存储实现
   */
  public removeStorage(type: StorageType): void {
    this.storageMap.delete(type);
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

  /**
   * 获取所有存储实现
   * @return Map<StorageType, IFileStorage> 存储实现
   */
  public getStorageMap(): Map<StorageType, IFileStorage> {
    return this.storageMap;
  }
}

/**
 * 文件存储类
 * 用于存储和读取文件
 */
export class FileStorage {
  /**
   * 注册存储实现
   * @param type 存储类型
   * @param storage 存储实现
   */
  public static registerStorage(type: StorageType, storage: IFileStorage): void {
    FileStorageFactory.getInstance().registerStorage(type, storage);
  }

  /**
   * 删除存储实现
   * @param type 存储类型
   * @param storage 存储实现
   */
  public static removeStorage(type: StorageType): void {
    FileStorageFactory.getInstance().removeStorage(type);
  }

  /**
   * 获取存储实现
   * @param type 存储类型
   * @return IFileStorage 存储实现
   * @throws 如果指定类型的存储未注册则抛出异常
   */
  public static getStorage(type: StorageType): IFileStorage {
    return FileStorageFactory.getInstance().getStorage(type);
  }

  /**
   * 检查指定类型的存储是否已注册
   * @param type 存储类型
   * @return boolean 是否已注册
   */
  public static hasStorage(type: StorageType): boolean {
    return FileStorageFactory.getInstance().hasStorage(type);
  }

  /**
   * 获取所有存储页面配置信息
   * @return Array<PageConfig> 存储实现
   */
  public static getAllPageConfig(): Array<PageConfig> {
    const pageConfigs: Array<PageConfig> = [];
    for (const storage of FileStorageFactory.getInstance().getStorageMap().values()) {
      pageConfigs.push(storage.getPageConfig());
    }
    return pageConfigs;
  }
}
