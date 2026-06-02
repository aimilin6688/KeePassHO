import { IFileStorage, FileInfo, FileType } from '../IFileStorage';
import { StorageConfig, PageConfig } from '../StorageConfig';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { PCloudClient, PCloudMetadata, PCloudError } from './PCloudClient';
import { PCloudStorageConfig, PCloudPageConfig } from './PCloudConfig';

const PCLOUD_ERROR_NEED_LOGIN = 1000;
const PCLOUD_ERROR_NOT_FOUND = 2005;

/**
 * pCloud 文件存储实现
 *
 * 路径约定：
 * - 文件夹：d{folderid}（如 "d0" = 根目录）
 * - 文件：f{fileid}（如 "f1729212"）
 * - 写入路径：d{folderId}/{fileName}（如 "d230807/myfile.kdbx"）
 */
export class PCloudStorage implements IFileStorage {
  private config: PCloudStorageConfig | null = null;
  private client: PCloudClient | null = null;

  getPageConfig(): PageConfig {
    return PCloudPageConfig;
  }

  init(config: StorageConfig): void {
    this.config = config as PCloudStorageConfig;
    this.client = new PCloudClient();
    this.client.setAccessToken(this.config.accessToken);
  }

  async read(path: string): Promise<ArrayBuffer> {
    this.ensureReady();
    this.config!.touchActive();

    try {
      return await this.client!.downloadFile(path);
    } catch (error) {
      const err = error as Error;
      this.handlePCloudError(error, 'Read');
      throw new StorageError(
        StorageErrorCodes.FILE_READ_ERROR,
        'Read failed: ' + err.message
      );
    }
  }

  async write(path: string, content: ArrayBuffer): Promise<void> {
    this.ensureReady();
    this.config!.touchActive();

    // path 格式: "d{folderId}/{fileName}"
    const lastSlash = path.lastIndexOf('/');
    if (lastSlash < 0) {
      throw new StorageError(
        StorageErrorCodes.FILE_WRITE_ERROR,
        'Invalid path format, expected "d{folderId}/{fileName}"'
      );
    }

    const folderId = path.substring(0, lastSlash);
    const folderNumericId = folderId.startsWith('d') ? folderId.substring(1) : folderId;
    const fileName = path.substring(lastSlash + 1);

    try {
      await this.client!.uploadFile(folderNumericId, fileName, content);
    } catch (error) {
      const err = error as Error;
      this.handlePCloudError(error, 'Write');
      throw new StorageError(
        StorageErrorCodes.FILE_WRITE_ERROR,
        'Write failed: ' + err.message
      );
    }
  }

  async exists(path: string): Promise<boolean> {
    this.ensureReady();
    this.config!.touchActive();

    try {
      await this.client!.stat(path);
      return true;
    } catch (error) {
      if (error instanceof PCloudError && error.code === PCLOUD_ERROR_NOT_FOUND) {
        return false;
      }
      this.handlePCloudError(error, 'Exists');
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('Unknown error in exists');
    }
  }

  async getInfo(path: string): Promise<FileInfo> {
    this.ensureReady();
    this.config!.touchActive();

    try {
      const meta = await this.client!.stat(path);
      return this.metadataToFileInfo(meta, path);
    } catch (error) {
      const err = error as Error;
      this.handlePCloudError(error, 'GetInfo');
      throw new StorageError(
        StorageErrorCodes.FILE_INFO_ERROR,
        'Get info failed: ' + err.message
      );
    }
  }

  async listDir(path: string): Promise<FileInfo[]> {
    this.ensureReady();
    this.config!.touchActive();

    try {
      const items = await this.client!.listFolder(path);
      const result: FileInfo[] = [];
      for (let i = 0; i < items.length; i++) {
        result.push(this.metadataToFileInfo(items[i], this.buildResourceId(items[i])));
      }
      return result;
    } catch (error) {
      const err = error as Error;
      this.handlePCloudError(error, 'ListDir');
      throw new StorageError(
        StorageErrorCodes.FILE_INFO_ERROR,
        'List directory failed: ' + err.message
      );
    }
  }

  /**
   * pCloud metadata → FileInfo 转换
   */
  private metadataToFileInfo(meta: PCloudMetadata, resourceId: string): FileInfo {
    let childrenCount: number = 0;
    if (meta.isfolder && meta.contents) {
      childrenCount = meta.contents.length;
    }
    return {
      name: meta.name,
      size: meta.size ? meta.size : 0,
      modifiedTime: new Date(meta.modified).getTime(),
      path: resourceId,
      type: meta.isfolder ? FileType.DIR : FileType.FILE,
      childrenCount: childrenCount
    };
  }

  /**
   * 构建资源标识符
   * 文件夹 → "d{folderid}"，文件 → "f{fileid}"
   */
  private buildResourceId(meta: PCloudMetadata): string {
    if (meta.isfolder) {
      if (meta.folderid === undefined) {
        throw new Error('buildResourceId: folderid is undefined');
      }
      return 'd' + meta.folderid;
    }
    if (meta.fileid === undefined) {
      throw new Error('buildResourceId: fileid is undefined');
    }
    return 'f' + meta.fileid;
  }

  /**
   * 确保已初始化
   */
  private ensureReady(): void {
    if (!this.client || !this.config) {
      throw new StorageError(
        StorageErrorCodes.CLIENT_UNDEFINED,
        'PCloudStorage not initialized'
      );
    }
  }

  /**
   * 统一处理 pCloud API 错误
   * 1000 = 需要登录（token 过期），转换为 StorageError
   */
  private handlePCloudError(error: Object, operation: string): void {
    if (error instanceof PCloudError && error.code === PCLOUD_ERROR_NEED_LOGIN) {
      throw new StorageError(
        StorageErrorCodes.CONNECT_ERROR,
        operation + ' failed: Token expired, please re-login'
      );
    }
  }
}
