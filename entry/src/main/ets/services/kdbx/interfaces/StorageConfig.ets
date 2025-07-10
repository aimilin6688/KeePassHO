/**
 * 存储配置接口
 */
export interface StorageConfig {}

/**
 * 本地文件存储配置类
 */
export class LocalFileStorageConfig implements StorageConfig {
  /**
   * 文件大小（字节）
   */
  size: number = 0;

  constructor(size: number) {
    this.size = size;
  }
}