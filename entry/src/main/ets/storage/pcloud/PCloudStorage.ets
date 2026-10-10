import { FileInfo, FileType, TransferProgressCallback, WriteOption } from '../IFileStorage';
import { BaseFileStorage } from '../BaseFileStorage';
import { StorageConfig, PageConfig } from '../StorageConfig';
import { HTTP_UPLOAD_MAX_BYTES, StorageError, StorageErrorCodes } from '../StorageError';
import { PCloudClient, PCloudMetadata, PCloudError } from './PCloudClient';
import { PCloudStorageConfig, PCloudPageConfig } from './PCloudConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'PCloudStorage';

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
export class PCloudStorage extends BaseFileStorage {
  private config: PCloudStorageConfig | null = null;
  private client: PCloudClient | null = null;

  getPageConfig(): PageConfig {
    return PCloudPageConfig;
  }

  init(config: StorageConfig): void {
    this.config = config as PCloudStorageConfig;
    this.client = new PCloudClient(this.config.apiBaseUrl);
    this.client.setAccessToken(this.config.accessToken);
  }

  /**
   * 声明版本快速路径可用：pCloud 版本标识 = fileid:hash:size:modified（buildVersion），
   * hash 为内容 hash，内容更新必变 hash/modified/size 至少一项，探测结果稳定可信
   */
  supportsVersionFastPath(): boolean {
    return true;
  }

  /**
   * 流式分块下载到本地文件（S7：Range GET 循环 8MB 块直写盘，内存与文件大小解耦）
   * @param onProgress 下载进度回调（可选）：逐块上报（transferredBytes, totalBytes）
   */
  async readToFile(path: string, destPath: string, onProgress?: TransferProgressCallback): Promise<FileInfo> {
    this.ensureReady();
    this.config!.touchActive();
    try {
      await this.client!.downloadFileRangeToFile(path, destPath, onProgress);
      return await this.getInfo(path);
    } catch (error) {
      const err = error as Error;
      this.handlePCloudError(error, 'ReadToFile');
      throw new StorageError(
        StorageErrorCodes.FILE_READ_ERROR,
        'ReadToFile failed: ' + err.message
      );
    }
  }

  /**
   * 流式从本地文件上传（S7：pCloud PUT 协议 + rcp UploadFromFile，请求体不驻内存，解除 CP-UP 约束）
   * 条件写入：传入 expectedVersion 时写前复核远端版本，不一致抛出版本冲突
   * @param onProgress 上传进度回调（可选）：按 rcp 内部拉取块上报（transferredBytes, totalBytes）
   * @throws StorageError(VERSION_CONFLICT) 远端版本与期望不一致
   * @throws StorageError(FILE_WRITE_ERROR) 上传失败
   */
  async writeFromFile(path: string, srcPath: string, option?: WriteOption,
    onProgress?: TransferProgressCallback): Promise<FileInfo> {
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
      // 条件写入：写前复核远端版本，不一致抛出版本冲突
      await this.checkExpectedVersion(folderNumericId, fileName, option);
      await this.client!.uploadFileFromFile(folderNumericId, fileName, srcPath, onProgress);
      return await this.getInfo(path);
    } catch (error) {
      // 版本冲突直接透传，保持错误码不被改写
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      const err = error as Error;
      this.handlePCloudError(error, 'WriteFromFile');
      throw new StorageError(
        StorageErrorCodes.FILE_WRITE_ERROR,
        'WriteFromFile failed: ' + err.message
      );
    }
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

  /**
   * 写入文件内容
   * 条件写入：传入 expectedVersion 时写前复核远端版本，不一致抛出版本冲突
   * @param path 文件路径
   * @param content 文件内容
   * @param option 写入选项（条件写入）
   * @throws StorageError(VERSION_CONFLICT) 远端版本与期望不一致
   */
  async write(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void> {
    this.ensureReady();
    this.config!.touchActive();

    // CP-UP：整缓冲上传超过 http 栈上限必然失败，提前拒绝并给出明确原因
    if (content.byteLength > HTTP_UPLOAD_MAX_BYTES) {
      throw new StorageError(StorageErrorCodes.UPLOAD_TOO_LARGE, `${content.byteLength} bytes`);
    }

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
      // 条件写入：写前复核远端版本，不一致抛出版本冲突
      await this.checkExpectedVersion(folderNumericId, fileName, option);
      await this.client!.uploadFile(folderNumericId, fileName, content);
    } catch (error) {
      // 版本冲突直接透传，保持错误码不被改写
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      const err = error as Error;
      this.handlePCloudError(error, 'Write');
      throw new StorageError(
        StorageErrorCodes.FILE_WRITE_ERROR,
        'Write failed: ' + err.message
      );
    }
  }

  /**
   * 获取文件信息；明确不存在（PCLOUD_ERROR_NOT_FOUND）返回 null，其他错误上抛
   */
  async getInfoOrNull(path: string): Promise<FileInfo | null> {
    this.ensureReady();
    this.config!.touchActive();

    try {
      const meta = await this.client!.stat(path);
      return this.metadataToFileInfo(meta, path);
    } catch (error) {
      if (error instanceof PCloudError && error.code === PCLOUD_ERROR_NOT_FOUND) {
        return null;
      }
      this.handlePCloudError(error, 'GetInfoOrNull');
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('Unknown error in getInfoOrNull');
    }
  }

  /**
   * 获取文件信息（基类派生：getInfoOrNull 为 null 时抛 FILE_INFO_ERROR）
   */

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
      childrenCount: childrenCount,
      version: PCloudStorage.buildVersion(meta)
    };
  }

  /**
   * 构建不透明版本标识（基线A）：fileid + hash + size + modified 复合串
   * 内容更新必然改变 hash/modified/size 中至少一项，同一内容重复探测结果稳定
   * @param meta pCloud 文件/文件夹元数据
   */
  private static buildVersion(meta: PCloudMetadata): string {
    const id: number = meta.fileid ?? meta.folderid ?? 0;
    const hash: number = meta.hash ?? 0;
    const size: number = meta.size ?? 0;
    return `${id}:${hash}:${size}:${meta.modified}`;
  }

  /**
   * 条件写入：写前复核远端版本（目录列表按文件名定位当前元数据），不一致抛出版本冲突
   * 远端文件不存在（新库首存）或列表失败时放行，由后续上传环节自行报错（对齐 S3 语义）
   * @param folderNumericId 目标文件夹数字 ID
   * @param fileName 文件名
   * @param option 写入选项
   * @throws StorageError(VERSION_CONFLICT) 版本不一致时抛出
   */
  private async checkExpectedVersion(folderNumericId: string, fileName: string, option?: WriteOption): Promise<void> {
    const expectedVersion: string | null = option?.expectedVersion ?? null;
    if (expectedVersion === null) {
      return;
    }
    try {
      const items: PCloudMetadata[] = await this.client!.listFolder(folderNumericId);
      for (const item of items) {
        if (!item.isfolder && item.name === fileName) {
          const currentVersion: string = PCloudStorage.buildVersion(item);
          if (currentVersion !== expectedVersion) {
            hilog.warn(DOMAIN, TAG,
              'pCloud version conflict, folder: %{public}s, file: %{public}s, expected: %{public}s, current: %{public}s',
              folderNumericId, fileName, expectedVersion, currentVersion);
            throw new StorageError(StorageErrorCodes.VERSION_CONFLICT, 'Remote file version changed');
          }
          return;
        }
      }
      // 目标文件不存在（新库首存）：放行
    } catch (error) {
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      // 列表失败（含远端不存在）：放行（fail-open），由上传环节自行报错
    }
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
