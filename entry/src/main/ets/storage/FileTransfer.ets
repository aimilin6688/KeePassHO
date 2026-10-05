import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileInfo, FileType, IFileStorage, WriteOption } from './IFileStorage';
import { FilenameUtils } from '../common/utils';

const DOMAIN = 0x0000;
const TAG = 'FileTransfer';

/**
 * 流式文件传输默认实现（整缓冲包装）
 *
 * 未迁移到真正流式的适配器，其 readToFile/writeFromFile 委托本类：
 * readToFile  = read() 整缓冲 → 写入 destPath
 * writeFromFile = 读 srcPath 整缓冲 → write()
 *
 * 适配器逐个迁移为真正的分块传输后，本类仅保留给小文件场景与未迁移适配器。
 */
export class FileTransfer {

  /**
   * 默认 readToFile：读取整缓冲后落盘
   * @param storage 存储实现
   * @param path 远端路径
   * @param destPath 本地目标路径
   */
  public static async readToFileDefault(storage: IFileStorage, path: string,
    destPath: string): Promise<FileInfo> {
    const content: ArrayBuffer = await storage.read(path);
    await FileTransfer.writeBufferToFile(content, destPath);
    const info: FileInfo = await storage.getInfo(path);
    return info;
  }

  /**
   * 默认 writeFromFile：读源文件整缓冲后 write()
   * @param storage 存储实现
   * @param path 远端路径
   * @param srcPath 本地源文件路径
   * @param option 写入选项
   */
  public static async writeFromFileDefault(storage: IFileStorage, path: string,
    srcPath: string, option?: WriteOption): Promise<FileInfo> {
    const content: ArrayBuffer = await FileTransfer.readFileToBuffer(srcPath);
    await storage.write(path, content, option);
    return await storage.getInfo(path);
  }

  /**
   * 将 ArrayBuffer 写入本地文件（创建/截断）
   */
  public static async writeBufferToFile(content: ArrayBuffer, destPath: string): Promise<void> {
    let file: fs.File | null = null;
    try {
      file = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, content);
      await fs.fsync(file.fd);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'writeBufferToFile failed: %{public}s', err.message);
      throw err;
    } finally {
      if (file !== null) {
        try {
          await fs.close(file.fd);
        } catch {
          // ignore
        }
      }
    }
  }

  /**
   * 读取本地文件为 ArrayBuffer（整缓冲）
   */
  public static async readFileToBuffer(srcPath: string): Promise<ArrayBuffer> {
    let file: fs.File | null = null;
    try {
      file = await fs.open(srcPath, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer);
      return buffer;
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'readFileToBuffer failed: %{public}s', err.message);
      throw err;
    } finally {
      if (file !== null) {
        try {
          await fs.close(file.fd);
        } catch {
          // ignore
        }
      }
    }
  }

  /**
   * 由本地文件 stat 构造 FileInfo（version 用 size|mtime 复合串）
   */
  public static async fileInfoFromLocal(localPath: string, originalPath: string): Promise<FileInfo> {
    const file = await fs.open(localPath, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(file.fd);
      const info: FileInfo = {
        name: FilenameUtils.getFileName(originalPath),
        size: stat.size,
        modifiedTime: stat.mtime * 1000,
        path: originalPath,
        type: stat.isDirectory() ? FileType.DIR : FileType.FILE,
        childrenCount: 0,
        version: `${stat.size}|${stat.mtime}`
      } as FileInfo;
      return info;
    } finally {
      try {
        await fs.close(file.fd);
      } catch {
        // ignore
      }
    }
  }
}
