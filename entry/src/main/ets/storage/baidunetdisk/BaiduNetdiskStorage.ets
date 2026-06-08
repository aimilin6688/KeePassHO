import { IFileStorage, FileInfo, FileInfoImpl, FileType } from '../IFileStorage';
import { PageConfig } from '../StorageConfig';
import { StorageType } from '../StorageType';
import { BaiduNetdiskConfig } from './BaiduNetdiskConfig';
import { BaiduNetdiskClient } from './BaiduNetdiskClient';

/**
 * 百度网盘存储实现
 * 实现 IFileStorage 接口，提供对百度网盘的文件读写能力
 */
export class BaiduNetdiskStorage implements IFileStorage {
  readonly type: StorageType = StorageType.BAIDU_NETDISK;
  readonly displayName: string = '百度网盘';

  private config: BaiduNetdiskConfig;
  private client: BaiduNetdiskClient;
  private rootPath: string = '/';

  constructor(config: BaiduNetdiskConfig) {
    this.config = config;
    this.client = new BaiduNetdiskClient(config);
    this.rootPath = config.rootPath || '/';
    // 确保路径以 / 开头并以 / 结尾
    if (!this.rootPath.startsWith('/')) {
      this.rootPath = '/' + this.rootPath;
    }
    if (!this.rootPath.endsWith('/')) {
      this.rootPath += '/';
    }
  }

  /**
   * 获取页面配置
   */
  getPageConfig(): PageConfig {
    const pageConfig: PageConfig = {
      icon: $r('app.media.ic_save'),
      title: '百度网盘',
      selectDesc: '使用百度网盘存储密码库文件',
      saveDesc: '保存百度网盘配置',
      pageUrl: 'pages/storage/BaiduNetdiskPage',
      storageType: StorageType.BAIDU_NETDISK
    };
    return pageConfig;
  }

  /**
   * 初始化存储配置（从 Settings 中读取百度网盘配置并更新）
   */
  init(config: import('../StorageConfig').StorageConfig): void {
    // StorageConfig 为空接口，实际配置由 BaiduNetdiskConfig.load() 加载
    // 此处仅触发配置加载
    console.log('[BaiduNetdiskStorage] init called');
  }

  /**
   * 解析路径为网盘绝对路径
   */
  private resolvePath(inputPath: string): string {
    if (inputPath.startsWith('/')) {
      return inputPath;
    }
    return this.rootPath + inputPath;
  }

  /**
   * 读取文件内容，返回 ArrayBuffer
   */
  async read(path: string): Promise<ArrayBuffer> {
    const fullPath = this.resolvePath(path);
    console.log('[BaiduNetdiskStorage] Reading: ' + fullPath);
    return this.client.downloadFile(fullPath);
  }

  /**
   * 写入文件内容
   */
  async write(path: string, content: ArrayBuffer): Promise<void> {
    const fullPath = this.resolvePath(path);
    console.log('[BaiduNetdiskStorage] Writing: ' + fullPath + ', size=' + content.byteLength);
    const success = await this.client.uploadFile(fullPath, content);
    if (!success) {
      throw new Error('Failed to write file: ' + fullPath);
    }
  }

  /**
   * 检查文件或目录是否存在
   */
  async exists(path: string): Promise<boolean> {
    const fullPath = this.resolvePath(path);
    return this.client.exists(fullPath);
  }

  /**
   * 获取文件或目录信息
   * @returns FileInfo 对象
   */
  async getInfo(path: string): Promise<FileInfo> {
    const fullPath = this.resolvePath(path);
    const item = await this.client.getFileInfo(fullPath);
    const result = new FileInfoImpl();
    if (!item) {
      result.name = this.extractFileName(fullPath);
      result.path = fullPath;
      result.size = 0;
      result.modifiedTime = 0;
      result.type = FileType.FILE;
      result.childrenCount = 0;
      return result;
    }
    result.name = item.server_filename;
    result.path = item.path;
    result.size = item.size;
    result.modifiedTime = item.server_mtime * 1000; // 秒转毫秒
    result.type = item.isdir === 1 ? FileType.DIR : FileType.FILE;
    result.childrenCount = 0;
    return result;
  }

  /**
   * 列出目录内容
   * @returns Array<FileInfo>
   */
  async listDir(path: string): Promise<Array<FileInfo>> {
    const fullPath = this.resolvePath(path);
    console.log('[BaiduNetdiskStorage] Listing: ' + fullPath);
    const items = await this.client.listFiles(fullPath);
    const result: Array<FileInfo> = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const info = new FileInfoImpl();
      info.name = item.server_filename;
      info.path = item.path;
      info.size = item.size;
      info.modifiedTime = item.server_mtime * 1000;
      info.type = item.isdir === 1 ? FileType.DIR : FileType.FILE;
      info.childrenCount = 0;
      result.push(info);
    }
    return result;
  }

  /**
   * 测试连接是否可用
   */
  async testConnection(): Promise<boolean> {
    try {
      await this.client.listFiles(this.rootPath);
      return true;
    } catch (e) {
      console.error('[BaiduNetdiskStorage] Connection test failed: ' + (e as Error).message);
      return false;
    }
  }

  private extractFileName(path: string): string {
    const lastSlash = path.lastIndexOf('/');
    if (lastSlash >= 0) {
      return path.substring(lastSlash + 1);
    }
    return path;
  }
}
