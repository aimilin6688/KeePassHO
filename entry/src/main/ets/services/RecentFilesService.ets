import preferences from '@ohos.data.preferences';
import { FileService } from './FileService';
import { KdbxFileManager } from './kdbx/KdbxFileManager';
import { RecentFile } from './TypeDefined';

/**
 * 最近打开的文件服务
 * 用于管理最近打开的文件列表
 */
export class RecentFilesService {
  private static instance: RecentFilesService;
  private static readonly PREFERENCES_NAME = 'recent_files';
  private static readonly RECENT_FILES_KEY = 'recent_files_list';
  private static readonly MAX_RECENT_FILES = 10; // 最多保存10个最近打开的文件

  /**
   * 获取单例实例
   */
  public static getInstance(): RecentFilesService {
    if (!RecentFilesService.instance) {
      RecentFilesService.instance = new RecentFilesService();
    }
    return RecentFilesService.instance;
  }

  /**
   * 获取首选项实例
   */
  private async getPreferences(): Promise<preferences.Preferences> {
    const context = getContext(this);
    return await preferences.getPreferences(context, RecentFilesService.PREFERENCES_NAME);
  }

  /**
   * 添加最近打开的文件
   * @param fileParam 文件参数
   * @param storageType 存储类型
   */
  public async addRecentFile(recentFile: RecentFile): Promise<void> {
    try {
      // 获取当前的最近文件列表
      const recentFiles = await this.getRecentFiles();

      // 检查文件是否已经在列表中
      const existingIndex = recentFiles.findIndex(file => file.filePath === recentFile.filePath);
      if (existingIndex !== -1) {
        // 如果文件已经在列表中，将其移到列表顶部
        recentFiles.splice(existingIndex, 1);
      }

      // 将新文件添加到列表顶部
      recentFiles.unshift(recentFile);

      // 如果列表超过最大数量，删除最旧的记录
      if (recentFiles.length > RecentFilesService.MAX_RECENT_FILES) {
        recentFiles.pop();
      }

      // 保存更新后的列表
      const prefs = await this.getPreferences();
      await prefs.put(RecentFilesService.RECENT_FILES_KEY, JSON.stringify(recentFiles));
      await prefs.flush();
    } catch (error) {
      console.error(`添加最近文件失败: ${error}`);
      throw new Error(error);
    }
  }

  /**
   * 获取最近打开的文件列表
   */
  public async getRecentFiles(): Promise<RecentFile[]> {
    try {
      const prefs = await this.getPreferences();
      const recentFilesJson = await prefs.get(RecentFilesService.RECENT_FILES_KEY, '[]');
      return JSON.parse(recentFilesJson.toString());
    } catch (error) {
      console.error(`获取最近文件列表失败: ${error}`);
      return [];
    }
  }

  /**
   * 读取最近打开的文件的内容
   * @param filePath 文件路径
   */
  public async readRecentFile(recentFile: RecentFile): Promise<void> {
    const fileContent = await new KdbxFileManager(recentFile.storageType).loadKdbxFile(recentFile.filePath);
    // 设置文件参数
    FileService.getInstance().setFileParam({
      filePath: recentFile.filePath,
      fileName: recentFile.fileName,
      fileContent: fileContent,
      storageType: recentFile.storageType
    });
  }

  /**
   * 加载最近打开的文件
   * 返回最近打开的第一个文件的参数，如果没有则返回null
   */
  public async loadMostRecentFile(): Promise<RecentFile | null> {
    try {
      const recentFiles = await this.getRecentFiles();
      if (recentFiles.length === 0) {
        return null;
      }

      // 获取最近打开的第一个文件
      const recentFile = recentFiles[0];
      // 检查文件是否存在
      const fileExists = await this.checkFileExists(recentFile);
      if (!fileExists) {
        // 如果文件不存在，从列表中移除
        await this.removeRecentFile(recentFile);
        // 递归调用，尝试加载下一个文件
        return await this.loadMostRecentFile();
      }

      return recentFile;
    } catch (error) {
      console.error(`加载最近文件失败: ${error}`);
      return null;
    }
  }

  /**
   * 检查文件是否存在
   * @param filePath 文件路径
   */
  public async checkFileExists(recentFile: RecentFile): Promise<boolean> {
    try {
      return new KdbxFileManager(recentFile.storageType).exists(recentFile.filePath);
    } catch (error) {
      return false;
    }
  }

  /**
   * 移除最近打开的文件
   * @param filePath 文件路径
   */
  public async removeRecentFile(recentFile: RecentFile): Promise<void> {
    try {
      // 获取当前的最近文件列表
      const recentFiles = await this.getRecentFiles();

      // 移除指定文件
      const updatedFiles = recentFiles.filter(file => file.filePath !== recentFile.filePath);

      // 保存更新后的列表
      const prefs = await this.getPreferences();
      await prefs.put(RecentFilesService.RECENT_FILES_KEY, JSON.stringify(updatedFiles));
      await prefs.flush();
    } catch (error) {
      console.error(`移除最近文件失败: ${error}`);
      throw new Error(error);
    }
  }

  /**
   * 清除所有最近打开的文件
   */
  public async clearRecentFiles(): Promise<void> {
    try {
      const prefs = await this.getPreferences();
      await prefs.put(RecentFilesService.RECENT_FILES_KEY, '[]');
      await prefs.flush();
    } catch (error) {
      console.error(`清除最近文件列表失败: ${error}`);
      throw new Error(error);
    }
  }

  /**
   * 获取最近打开的文件
   * @param filePath 文件路径
   */
  public async getRecentFile(filePath: string): Promise<RecentFile | null> {
    // 遍历最近打开的文件路径，找到匹配的文件
    for (const recentFile of await this.getRecentFiles()) {
      if (recentFile.filePath === filePath) {
        // 如果找到匹配的文件，返回该文件
        return recentFile;
      }
    }
    return null;
  }
}
