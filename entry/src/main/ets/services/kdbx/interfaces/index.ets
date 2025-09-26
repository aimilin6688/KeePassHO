import { FileStorageFactory } from './FileStorageFactory';
import { IFileStorage } from './IFileStorage';
import { StorageType } from './StorageType';

export * from './IFileStorage';
export * from './StorageType';
export * from './FileStorageFactory';
export * from './impl/LocalFileStorage';
export * from './StorageConfig';

/**
 * 获取默认的文件存储实例（本地存储）
 * @return IFileStorage
 */
export function getDefaultStorage(): IFileStorage {
  return FileStorageFactory.getInstance().getStorage(StorageType.LOCAL);
}
