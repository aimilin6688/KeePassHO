import { IFileStorage } from '../IFileStorage';
import { StorageType } from '../StorageType';
import { BaiduNetdiskConfig } from './BaiduNetdiskConfig';
import { BaiduNetdiskClient } from './BaiduNetdiskClient';
import { basename } from '../pathUtil';

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
    this.rootPath = config.pageConfig.rootPath || '/';
    // 确保路径以 / 开头并以 / 结尾
    if (!this.rootPath.startsWith('/')) {
      this.rootPath = '/' + this.rootPath;
    }
    if (!this.rootPath.endsWith('/')) {
      this.rootPath += '/';
    }
  }

  /**
   * 解析路径为网盘绝对路径
   */
  private resolvePath(path: string): string {
    if (path.startsWith('/')) {
      return path;
    }
    return this.rootPath + path;
  }

  /**
   * 读取文件内容，返回 ArrayBuffer
   */
  async read(path: string): Promise<ArrayBuffer> {
    const fullPath = this.resolvePath(path);
    console.log(`[BaiduNetdiskStorage] Reading: ${fullPath}`);
    return this.client.downloadFile(fullPath);
  }

  /**
   * 写入文件内容
   */
  async write(path: string, content: ArrayBuffer): Promise<void> {
    const fullPath = this.resolvePath(path);
    console.log(`[BaiduNetdiskStorage] Writing: ${fullPath}, size=${content.byteLength}`);
    const success = await this.client.uploadFile(fullPath, content);
    if (!success) {
      throw new Error(`Failed to write file: ${fullPath}`);
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
   */
  async getInfo(path: string): Promise<{
    name: string;
    path: string;
    size: number;
    isDirectory: boolean;
    lastModified: number;
  } | null> {
    const fullPath = this.resolvePath(path);
    const item = await this.client.getFileInfo(fullPath);
    if (!item) {
      return null;
    }
    return {
      name: item.server_filename,
      path: item.path,
      size: item.size,
      isDirectory: item.isdir === 1,
      lastModified: item.server_mtime * 1000, // 秒转毫秒
    };
  }

  /**
   * 列出目录内容
   */
  async listDir(path: string): Promise<Array<{
    name: string;
    path: string;
    size: number;
    isDirectory: boolean;
    lastModified: number;
  }>> {
    const fullPath = this.resolvePath(path);
    console.log(`[BaiduNetdiskStorage] Listing: ${fullPath}`);
    const items = await this.client.listFiles(fullPath);
    return items.map(item => ({
      name: item.server_filename,
      path: item.path,
      size: item.size,
      isDirectory: item.isdir === 1,
      lastModified: item.server_mtime * 1000,
    }));
  }

  /**
   * 测试连接是否可用
   */
  async testConnection(): Promise<boolean> {
    try {
      await this.client.listFiles(this.rootPath);
      return true;
    } catch (e) {
      console.error('[BaiduNetdiskStorage] Connection test failed:', e);
      return false;
    }
  }
}
