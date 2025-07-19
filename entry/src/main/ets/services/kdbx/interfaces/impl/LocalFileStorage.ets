import { fileShare, fileIo as fs } from '@kit.CoreFileKit';
import { FileInfo, IFileStorage } from '../IFileStorage';
import FileUtils from '../../../../common/utils/FIleUtils';

/**
 * 本地文件存储实现
 * 使用鸿蒙系统的文件API实现本地文件的读写操作
 */
export class LocalFileStorage implements IFileStorage {
  /**
   * 读取文件内容
   * @param path 文件路径
   * @return Promise<ArrayBuffer> 文件内容
   * @throws 如果读取失败则抛出异常
   */
  async readFile(path: string): Promise<ArrayBuffer> {

    return await FileUtils.activatePermission(path, fileShare.OperationMode.READ_MODE).then(async () => {
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
        throw new Error(`Failed to read file: ${error.message}`);
      }
    });
  }

  /**
   * 写入文件内容
   * @param path 文件路径
   * @param content 文件内容
   * @throws 如果写入失败则抛出异常
   */
  async writeFile(path: string, content: ArrayBuffer): Promise<void> {
    return await FileUtils.activatePermission(path, fileShare.OperationMode.WRITE_MODE).then(async () => {
      try {
        // 打开文件（如果不存在则创建）
        const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        // 写入内容
        await fs.write(file.fd, content);
        // 关闭文件
        await fs.close(file.fd);
        return Promise.resolve();
      } catch (error) {
        throw new Error(`Failed to write file: ${error.message}`);
      }
    });
  }

  /**
   * 检查文件是否存在
   * @param path 文件路径
   * @return Promise<boolean> 文件是否存在
   */
  async exists(path: string): Promise<boolean> {
    try {
      // fixme 这里始终返回false ，不确定什么原因
      let result = fs.accessSync(path, fs.AccessModeType.EXIST);
      console.log(`file ${path} exist: ${result}`);
      return true;
    } catch (error){
      console.log(`file not exist! ${path} msg: ${error.message}`);
      return false;
    }
  }

  /**
   * 获取文件信息
   * @param path 文件路径
   * @return Promise<FileInfo> 文件信息
   * @throws 如果获取失败则抛出异常
   */
  async getFileInfo(path: string): Promise<FileInfo> {
    try {
      // 打开文件
      const file = await fs.open(path, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      await fs.close(file.fd);
      return {
        name: path.split('/').pop() || '',
        size: stat.size,
        modifiedTime: new Date(stat.mtime),
        path: path
      };
    } catch (error) {
      throw new Error(`Failed to get file info: ${error.message}`);
    }
  }
}
