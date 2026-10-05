import { FileContentInfo, FileStorageFactory, IFileStorage, FileInfo, StorageConfig, StorageType, WriteOption } from '../../storage';
import { StorageError } from '../../storage/StorageError';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {ResourceManager} from '../../common/utils';
import { LocationInfo } from '../beans/LocationParam';

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
   * 创建一个KDBX文件管理器实例
   * @param locationInfo 文件位置信息
   * @return KDBX文件管理器实例
   */
  public static of(locationInfo: LocationInfo) {
    return new KdbxFileManager(locationInfo.storageType, locationInfo.storageConfig);
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
   * @param option 写入选项，支持条件写入（expectedVersion 不一致时底层抛出 VERSION_CONFLICT）
   * @throws 如果保存失败则抛出异常
   */
  public async write(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void> {
    try {
      // 写入文件内容
      return await this.storage.write(path, content, option);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to save KDBX file: %{public}s', error.message)
      // 原样上抛，保留 StorageError 的错误码（如 VERSION_CONFLICT）供编排层识别
      if (error instanceof StorageError) {
        throw error;
      }
      throw new Error(error.message);
    }
  }

  /**
   * 流式读取文件到本地目标路径（分块下载/复制，避免整缓冲驻留内存）
   * @param path 远端文件路径
   * @param destPath 本地目标文件路径（调用方负责生命周期）
   * @return Promise<FileInfo> 远端文件信息（含 version）
   * @throws 如果读取失败则抛出异常
   */
  public async readToFile(path: string, destPath: string): Promise<FileInfo> {
    try {
      return await this.storage.readToFile(path, destPath);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to readToFile KDBX: %{public}s', error.message)
      if (error instanceof StorageError) {
        throw error;
      }
      throw new Error(error.message);
    }
  }

  /**
   * 流式从本地源文件写入远端（分块上传/复制，避免整缓冲驻留内存）
   * @param path 远端文件路径
   * @param srcPath 本地源文件路径
   * @param option 写入选项，支持条件写入
   * @return Promise<FileInfo> 写入后的远端文件信息
   * @throws 如果写入失败则抛出异常
   */
  public async writeFromFile(path: string, srcPath: string, option?: WriteOption): Promise<FileInfo> {
    try {
      return await this.storage.writeFromFile(path, srcPath, option);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to writeFromFile KDBX: %{public}s', error.message)
      if (error instanceof StorageError) {
        throw error;
      }
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
      hilog.error(DOMAIN, TAG, `Failed to get KDBX file info: ${error.message}`)
      throw new Error(error.message);
    }
  }

  /**
   * 获取KDBX文件信息
   * @param path 文件路径
   * @return Promise<FileInfo> 文件信息
   * @throws 如果获取失败则抛出异常
   */
  public async listDir(path: string): Promise<Array<FileInfo>> {
    try {
      return await this.storage.listDir(path);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to list dir: %{public}s', error.message)
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



