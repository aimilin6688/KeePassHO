import { StorageType } from '..';
import { PageConfig, StorageConfig } from '../StorageConfig';

/**
 * 本地文件存储配置类
 */
export class LocalFileStorageConfig implements StorageConfig {
  /**
   * 文件大小（字节）
   */
  size: number = 0;

  constructor(size?: number) {
    if (size) {
      this.size = size;
    }
  }
}

/**
 * 本地文件存储页面配置类
 */
export const LocalFilePageConfig = {
  icon: $r('app.media.ic_file'),
  title: $r('app.string.local_file_button_title'),
  selectDesc: $r('app.string.location_local_desc_select'),
  saveDesc: $r('app.string.location_local_desc_save'),
  pageUrl: 'storage/local/LocalFilePage',
  storageType: StorageType.LOCAL
} as PageConfig;