import { fileShare, fileIo as fs } from '@kit.CoreFileKit';
import { FileInfo, IFileStorage, WriteOption } from '../IFileStorage';
import { FilenameUtils, FileUtils } from '../../common/utils';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileType, PageConfig, StorageConfig } from '..';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { LocalFilePageConfig } from './LocalFileConfig';


const DOMAIN = 0x0000;
const TAG = 'LocalFileStorage';

/**
 * 本地文件存储实现
 * 使用鸿蒙系统的文件API实现本地文件的读写操作
 */
export class LocalFileStorage implements IFileStorage {
  /**
   * 获取页面配置
   * @returns
   */
  public getPageConfig(): PageConfig {
    return LocalFilePageConfig;
  }

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
        }).catch((error: Error) => {
          hilog.error(DOMAIN, TAG, `Failed to activate permission: ${error.message}`);
          return Promise.resolve(false);
        });
      } else {
        return Promise.resolve(false);
      }
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, `Failed to check persist permission: ${error.message}`);
      return Promise.resolve(false);
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
   * 流式读取文件到本地目标路径（fs 内核拷贝，零用户态整缓冲）
   * 顺带修复非原子写：destPath 与 path 在不同卷时退化为 read+write
   */
  public async readToFile(path: string, destPath: string): Promise<FileInfo> {
    await this.checkFilePermission(path, fileShare.OperationMode.READ_MODE);
    try {
      // file://docs/... URI 经 fs.copyFile(URI, path) 路径解析会 ENOENT（docs FUSE 不被内核拷贝识别）；
      // 先 fs.open 拿 fd（URI 解析在 open 阶段生效，已由 getInfo 验证可读），再 copyFile(srcFd, destFd)
      // 做内核态拷贝，兼容 docs URI 与沙箱路径，保留流式零整缓冲优势
      const srcFile = await fs.open(path, fs.OpenMode.READ_ONLY);
      try {
        const destFile = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try {
          await fs.copyFile(srcFile.fd, destFile.fd);
        } finally {
          await fs.close(destFile.fd);
        }
      } finally {
        await fs.close(srcFile.fd);
      }
      return await this.doGetInfo(path);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to copyFile: %{public}s', error.message);
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, error.message);
    }
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
   * @param option 写入选项，支持条件写入
   * @throws 如果写入失败则抛出异常
   */
  public async write(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void> {
    return this.checkFilePermission(path, fileShare.OperationMode.WRITE_MODE).then((result) => {
      return this.doWrite(path, content, option);
    });
  }

  /**
   * 写入文件内容
   * @param path 文件路径
   * @param content 文件内容
   * @param option 写入选项，传入 expectedVersion 时写前复核版本
   * @returns Promise<void>
   */
  public async doWrite(path: string, content: ArrayBuffer, option?: WriteOption): Promise<void> {    try {
      const expectedVersion: string | null = option?.expectedVersion ?? null;
      if (expectedVersion !== null) {
        const currentInfo: FileInfo = await this.doGetInfo(path);
        const currentVersion: string | null = currentInfo.version ?? null;
        if (currentVersion === null || currentVersion !== expectedVersion) {
          hilog.warn(DOMAIN, TAG, 'Local file version conflict, path: %{public}s, expected: %{public}s, current: %{public}s',
            path, expectedVersion, currentVersion);
          throw new StorageError(StorageErrorCodes.VERSION_CONFLICT, 'Local file version changed');
        }
      }
      // 打开文件（如果不存在则创建，TRUNC 清空旧内容，防止新内容比旧内容短时残留脏数据）
      const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      // 写入内容
      await fs.write(file.fd, content);
      // 关闭文件
      await fs.close(file.fd);
      return Promise.resolve();
    } catch (error) {
      // 版本冲突直接透传，保持错误码不被改写
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      hilog.error(DOMAIN, TAG, 'Failed to write file: %{public}s', error.message)
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, error.message);
    }
  }

  /**
   * 流式从本地源文件写入：写临时文件 + fsync + 原子 rename 替换
   * 顺带修复非原子写（崩溃中断不破坏现有文件）
   */
  public async writeFromFile(path: string, srcPath: string, option?: WriteOption): Promise<FileInfo> {
    await this.checkFilePermission(path, fileShare.OperationMode.WRITE_MODE);
    const expectedVersion: string | null = option?.expectedVersion ?? null;
    // 写前复核版本（与 doWrite 一致，两条路径共用）
    if (expectedVersion !== null) {
      const currentInfo: FileInfo = await this.doGetInfo(path);
      const currentVersion: string | null = currentInfo.version ?? null;
      if (currentVersion === null || currentVersion !== expectedVersion) {
        hilog.warn(DOMAIN, TAG, 'Local writeFromFile version conflict, expected: %{public}s, current: %{public}s',
          expectedVersion, currentVersion);
        throw new StorageError(StorageErrorCodes.VERSION_CONFLICT, 'Local file version changed');
      }
    }
    // file://docs/... URI 不支持 sibling temp 文件创建 + rename 原子替换（docs daemon 拒绝非 picked 文件）；
    // 退化为 fd→fd 直接拷贝（与 doWrite 同为非原子，受 docs URI 限制）
    if (path.startsWith('file://')) {
      try {
        const srcFile = await fs.open(srcPath, fs.OpenMode.READ_ONLY);
        try {
          const destFile = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          try {
            await fs.copyFile(srcFile.fd, destFile.fd);
          } finally {
            await fs.close(destFile.fd);
          }
        } finally {
          await fs.close(srcFile.fd);
        }
        return await this.doGetInfo(path);
      } catch (error) {
        if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
          throw error;
        }
        hilog.error(DOMAIN, TAG, 'Failed to writeFromFile: %{public}s', error.message);
        throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, error.message);
      }
    }
    // 沙箱路径：写临时文件 + fsync + 原子 rename 替换（崩溃中断不破坏现有文件）
    const tempPath: string = path + '.tmp.' + Date.now();
    try {
      // 拷贝到临时文件并落盘
      await fs.copyFile(srcPath, tempPath);
      const tmpFile = await fs.open(tempPath, fs.OpenMode.READ_ONLY);
      try {
        await fs.fsync(tmpFile.fd);
      } finally {
        await fs.close(tmpFile.fd);
      }
      // 原子替换
      await fs.rename(tempPath, path);
      return await this.doGetInfo(path);
    } catch (error) {
      // 清理临时文件
      try {
        await fs.unlink(tempPath);
      } catch {
        // ignore
      }
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        throw error;
      }
      hilog.error(DOMAIN, TAG, 'Failed to writeFromFile: %{public}s', error.message);
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
        childrenCount: 0,
        version: `${stat.size}|${stat.mtime}`
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
