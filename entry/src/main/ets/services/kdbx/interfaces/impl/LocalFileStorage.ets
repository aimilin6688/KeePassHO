import { fileShare, fileIo as fs } from '@kit.CoreFileKit';
import { FileInfo, IFileStorage } from '../IFileStorage';
import FileUtils from '../../../../common/utils/FIleUtils';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileType, StorageConfig } from '..';
import { StorageError, StorageErrorCodes } from '../../../error/StorageError';
import { FilenameUtils } from '../../../../common/utils/FilenameUtils';

const DOMAIN = 0x0000;
const TAG = 'LocalFileStorage';

/**
 * 本地文件存储实现
 * 使用鸿蒙系统的文件API实现本地文件的读写操作
 */
export class LocalFileStorage implements IFileStorage {
  /**
   * 初始化
   * @param config
   */
  public init(config: StorageConfig): void {
  }

  /**
   * 检测文件是否与相关权限，如果有权限则激活该权限
   * @param path 文件路径
   * @param operationMode 权限模式
   * @returns 结果
   */
  private async checkFilePermission(path: string, operationMode: fileShare.OperationMode): Promise<boolean> {
    // 校验文件权限
    return await FileUtils.checkPersistPermission(path, operationMode).then((result) => {
      if (result[0]) {
        return FileUtils.activatePermission(path, operationMode).then(() => {
          return Promise.resolve(true);
        });
      } else {
        return Promise.resolve(false);
      }
    });
  }

  /**
   * 读取文件内容
   * @param path 文件路径
   * @return Promise<ArrayBuffer> 文件内容
   * @throws 如果读取失败则抛出异常
   */
  public async read(path: string): Promise<ArrayBuffer> {
    return this.checkFilePermission(path, fileShare.OperationMode.READ_MODE).then((result) => {
      return this.doRead(path);
    });
  }

  /**
   * 读取文件内容
   * @param path 文件路径
   * @returns 结果
   */
  public async doRead(path: string): Promise<ArrayBuffer> {
    try {
      // 打开文件
      const file = await fs.open(path, fs.OpenMode.READ_ONLY);
      // 获取文件信息
      const fileInfo = await fs.stat(file.fd);
      // 创建缓冲区
      const buffer = new ArrayBuffer(fileInfo.size);
      // 读取文件内容
      await fs.read(file.fd, buffer);
      // 关闭文件
      await fs.close(file.fd);
      return buffer;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to read file: %{public}s', error.message)
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, error.message);
    }
  }

  /**
   * 写入文件内容, 写入前根据授权内容判断是否授权或激活授权
   * @param path 文件路径
   * @param content 文件内容
   * @throws 如果写入失败则抛出异常
   */
  public async write(path: string, content: ArrayBuffer): Promise<void> {
    return this.checkFilePermission(path, fileShare.OperationMode.WRITE_MODE).then((result) => {
      return this.doWrite(path, content);
    });
  }

  /**
   * 写入文件内容
   * @param path 文件路径
   * @param content 文件内容
   * @returns Promise<void>
   */
  public async doWrite(path: string, content: ArrayBuffer): Promise<void> {
    try {
      // 打开文件（如果不存在则创建）
      const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      // 写入内容
      await fs.write(file.fd, content);
      // 关闭文件
      await fs.close(file.fd);
      return Promise.resolve();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to write file: %{public}s', error.message)
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, error.message);
    }
  }

  /**
   * 检查文件是否存在
   * @param path 文件路径
   * @return Promise<boolean> 文件是否存在
   */
  public async exists(path: string): Promise<boolean> {
    try {
      // fixme 这里始终返回false ，不确定什么原因
      let result = fs.accessSync(path, fs.AccessModeType.EXIST);
      hilog.info(DOMAIN, TAG, `Check file exist: ${result}, path: ${path}`);
      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `file not exist! ${path} msg: ${error.message}`);
      return false;
    }
  }

  /**
   * 获取文件信息
   * @param path 文件路径
   * @return Promise<FileInfo> 文件信息
   * @throws 如果获取失败则抛出异常
   */
  public async getInfo(path: string): Promise<FileInfo> {
    return this.checkFilePermission(path, fileShare.OperationMode.READ_MODE).then((result) => {
      return this.doGetInfo(path);
    });
  }

  /**
   * 获取文件信息
   * @param path 文件路径
   * @returns 结果
   */
  public async doGetInfo(path: string): Promise<FileInfo> {
    try {
      // 打开文件
      const file = await fs.open(path, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      await fs.close(file.fd);
      return {
        name: FilenameUtils.getFileName(path),
        size: stat.size,
        modifiedTime: stat.mtime * 1000,
        path: path,
        type: stat.isDirectory() ? FileType.DIR : FileType.FILE,
        childrenCount: 0
      } as FileInfo;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to get file info: %{public}s', error.message)
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, error.message);
    }
  }

  /**
   * 获取目录内容
   * @param path
   * @returns
   */
  public listDir(path: string): Promise<FileInfo[]> {
    throw new StorageError(StorageErrorCodes.NOT_IMPLEMENTED);
  }
}
