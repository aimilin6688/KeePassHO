import { FileInfo, IFileStorage } from '../IFileStorage';
import { WebDAVStorageConfig } from '../StorageConfig';
import { Client } from '@dove/webdav';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ResourceManager from '../../../../common/utils/ResourceManager';
import KdbxUtils from '../../../../common/utils/KdbxUtils';
import FileUtils from '../../../../common/utils/FIleUtils';

const DOMAIN = 0x0000;
const TAG = 'WebDAVStorage';

/**
 * WebDAV存储实现类
 */
export class WebDAVStorage implements IFileStorage {
  private config: WebDAVStorageConfig | undefined;
  private client: Client | undefined;

  constructor(config?: WebDAVStorageConfig) {
    if (config) {
      this.init(config);
    }
  }

  public init(config: WebDAVStorageConfig) {
    this.config = config;
    this.client = new Client(config.url, config.username, config.password);
  }

  /**
   * 读取文件内容
   * @param path  文件路径
   * @returns 结果
   */
  public readFile(path: string): Promise<ArrayBuffer> {
    if(!this.client){
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      throw new Error('WebDAV not init');
    }
    try {
      return this.client.get(path).then((res)=>{
        if(res != null){
          return res;
        }
        return new ArrayBuffer(0);
      })
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'WebDAV readFile error:%{public}s', error.message);
      throw new Error(error.message);
    }
  }

  public async writeFile(path: string, data: ArrayBuffer): Promise<void> {
    // try {
    //   await this.client.putFileContents(path, data);
    // } catch (error) {
    //   console.error('WebDAV writeFile error:', error);
    //   throw new Error('Failed to write file to WebDAV');
    // }
  }

  /**
   * 检查文件是否存在
   * @param path
   * @returns
   */
  public async exists(path: string): Promise<boolean> {
    return this.getFileInfo(path).then((fileInfo)=>{
      return fileInfo != null;
    });
  }

  /**
   * 获取文件信息
   * @param path
   * @returns
   */
  public async getFileInfo(path: string): Promise<FileInfo> {
    if(!this.client){
      hilog.error(DOMAIN, TAG, 'WebDAV not init:%{public}s', JSON.stringify(this.config));
      throw new Error('WebDAV not init');
    }
    try {
      await this.client.connect();
      let fileInfos = await this.client.list(path);
      if(!fileInfos || fileInfos.length == 0 || fileInfos.length >= 2){
        hilog.error(DOMAIN, TAG, 'WebDAV list file:%{public}s', JSON.stringify(fileInfos));
        throw new Error(ResourceManager.getString($r('app.string.file_not_exists')));
      }
      let fileInfo = fileInfos[0];
      if(fileInfo.isFolder){
        hilog.error(DOMAIN, TAG, 'WebDAV file %{public}s is folder', fileInfo.href);
        throw new Error(ResourceManager.getString($r('app.string.file_is_folder')));
      }
      return {
        name: FileUtils.getFileName(fileInfo.href),
        size: fileInfo.contentLength,
        modifiedTime: new Date(),
        path: fileInfo.href
      } as FileInfo;
    } catch (error) {
      console.error('WebDAV getFileInfo error:', error);
      throw new Error(error.message);
    } finally {
      this.client.close();
    }
  }
}
