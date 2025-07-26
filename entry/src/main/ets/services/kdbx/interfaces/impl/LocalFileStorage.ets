import { fileShare, fileIo as fs } from '@kit.CoreFileKit';
import { FileInfo, IFileStorage } from '../IFileStorage';
import FileUtils from '../../../../common/utils/FIleUtils';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageConfig } from '..';

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
  init(config: StorageConfig): void {
  }
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
        hilog.error(DOMAIN, TAG, 'Failed to read file: %{public}s', error.message)
        throw new Error(`Failed to read file: ${error.message}`);
      }
    });
  }

  /**
   * 写入文件内容, 写入前根据授权内容判断是否授权或激活授权
   * @param path 文件路径
   * @param content 文件内容
   * @throws 如果写入失败则抛出异常
   */
  async writeFile(path: string, content: ArrayBuffer): Promise<void> {
    // 校验文件权限
   return await FileUtils.checkPersistPermission(path, fileShare.OperationMode.WRITE_MODE | fileShare.OperationMode.READ_MODE).then((result) =>{
     if(result[0]){
       return FileUtils.activatePermission(path, fileShare.OperationMode.WRITE_MODE).then(async () => {
          return await this.writeFileContent(path, content);
       });
     }else{
        return this.writeFileContent(path, content);
     }
   });
  }

  /**
   * 写入文件内容
   * @param path 文件路径
   * @param content 文件内容
   * @returns Promise<void>
   */
  private async writeFileContent(path: string, content: ArrayBuffer):Promise<void>{
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
      throw new Error(`Failed to write file: ${error.message}`);
    }
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
      hilog.info(DOMAIN, TAG, `file ${path} exist: ${result}`);
      return true;
    } catch (error){
      hilog.info(DOMAIN, TAG, `file not exist! ${path} msg: ${error.message}`);
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
        name: FileUtils.getFileName(path),
        size: stat.size,
        modifiedTime: new Date(stat.mtime),
        path: path
      };
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to get file info: %{public}s', error.message)
      throw new Error(`Failed to get file info: ${error.message}`);
    }
  }
}
