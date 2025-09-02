import preferences from '@ohos.data.preferences';
import { KdbxFileManager } from './kdbx/KdbxFileManager';
import { RecentFile } from './TypeDefined';

import { hilog } from '@kit.PerformanceAnalysisKit';
import FileUtils from '../common/utils/FIleUtils';
import { fileShare } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import DeviceUtils from '../common/utils/DeviceUtils';
import { CryptoUtils } from '../common/utils/CryptoUtils';
import { SettingsService } from './SettingsService';
import { ErrorCodes, KeePassHoError } from './error/KeepassHoError';

const DOMAIN = 0x0000;
const TAG = 'RecentFilesService';

/**
 * 最近打开的文件服务
 * 用于管理最近打开的文件列表
 */
export class RecentFilesService {
  private static instance: RecentFilesService = new RecentFilesService();
  private static readonly PREFERENCES_NAME = 'recent_files';
  private static readonly RECENT_FILES_KEY = 'recent_files_list';
  private static readonly MAX_RECENT_FILES = 10; // 最多保存10个最近打开的文件
  private context: common.UIAbilityContext | null = null;

  /**
   * 初始化主题管理器
   * @param context UIAbilityContext
   */
  public init(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): RecentFilesService {
    return RecentFilesService.instance;
  }

  /**
   * 获取首选项实例
   */
  private async getPreferences(): Promise<preferences.Preferences> {
    if (this.context === null) {
      hilog.error(DOMAIN, TAG, 'Context is null');
      throw new Error('Context is null');
    }
    return await preferences.getPreferences(this.context, RecentFilesService.PREFERENCES_NAME);
  }

  /**
   * 当文件拥有持久性授权时，才能添加到最近访问中
   * @param recentFile 最近打开的文件
   * @returns 结果
   */
  public async addRecentFile(recentFile: RecentFile): Promise<void> {
    if (recentFile.filePath === undefined || recentFile.filePath === '') {
      throw new KeePassHoError(ErrorCodes.FILE_PATH_EMPTY);
    }
    if (!recentFile.filePath.startsWith("file://")) {
      return this.doAdd(recentFile);
    }
    // 如果拥有持久化授权，则添加到最近访问列表中
    return FileUtils.checkPersistPermission(recentFile.filePath, fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE)
      .then((result) => {
        hilog.info(DOMAIN, TAG, 'Check path %{public}s persist permission: %{public}s', recentFile.filePath, result[0]);
        if (result[0]) {
          return this.doAdd(recentFile);
        } else {
          hilog.info(DOMAIN, TAG, 'Add recent file filePath:%{public}s no permission', recentFile.filePath);
          if (DeviceUtils.isEmulator()) {
            return this.doAdd(recentFile);
          } else {
            throw new KeePassHoError(ErrorCodes.FILE_NOT_PERMISSION);
          }
        }
      });
  }

  /**
   * 添加最近打开的文件
   * @param fileParam 文件参数
   */
  public static async addRecentFile(recentFile: RecentFile): Promise<void> {
    return RecentFilesService.getInstance().addRecentFile(recentFile);
  }

  /**
   * 添加最近打开的文件
   * @param fileParam 文件参数
   */
  private async doAdd(recentFile: RecentFile): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Add recent file filePath:%{public}s', recentFile.filePath);
      // 获取当前的最近文件列表
      const recentFiles = await this.getRecentFiles();

      // 检查文件是否已经在列表中
      const existingIndex = recentFiles.findIndex(file => file.filePath === recentFile.filePath);
      if (existingIndex !== -1) {
        // 如果文件已经在列表中，则将其移除
        if (recentFile.searchHistory === undefined) {
          recentFile.searchHistory = recentFiles[existingIndex].searchHistory;
        }
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
      hilog.error(DOMAIN, TAG, `Add recent file error: ${error}`);
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
      hilog.error(DOMAIN, TAG, `Get all recent files error: ${error}`);
      return [];
    }
  }

  /**
   * 获取最近打开的文件列表
   * @returns
   */
  public static getRecentFiles(): Promise<RecentFile[]> {
    return RecentFilesService.getInstance().getRecentFiles();
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
      hilog.error(DOMAIN, TAG, `Load most recent file error: ${error}`);
      return null;
    }
  }

  /**
   * 检查文件是否存在
   * @param filePath 文件路径
   */
  public async checkFileExists(recentFile: RecentFile): Promise<boolean> {
    try {
      return new KdbxFileManager(recentFile.storageType, recentFile.storageConfig).exists(recentFile.filePath);
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
      hilog.error(DOMAIN, TAG, `Remove recent file error: ${error}`);
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
      hilog.error(DOMAIN, TAG, `Clear Recent file error: ${error}`);
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

  /**
   * 获取最近打开的文件
   * @param filePath 文件路径
   */
  public static getRecentFile(filePath: string): Promise<RecentFile | null> {
    return RecentFilesService.getInstance().getRecentFile(filePath);
  }

  /**
   * 清空最近文件的密码
   * @param filePath 最近文件
   * @returns 结果
   */
  public static clearPassword(filePath: string): Promise<boolean> {
    return RecentFilesService.getRecentFile(filePath).then((recentFile) => {
      if (!recentFile) {
        return false;
      }
      recentFile.password = undefined;
      return RecentFilesService.addRecentFile(recentFile).then(result => {
        return true;
      });
    });
  }

  /**
   * 设置最近文件的密码
   * @param filePath 文件路径
   * @param password 密码
   * @returns 结果
   */
  public static setPassword(filePath: string, password: string): Promise<boolean> {
    if (!filePath || !password) {
      return Promise.resolve(false);
    }
    return RecentFilesService.getRecentFile(filePath).then((recentFile) => {
      if (!recentFile) {
        return false;
      }
      return CryptoUtils.encryptText(password).then(result => {
        recentFile.password = result;
        return RecentFilesService.addRecentFile(recentFile).then(result => {
          return true;
        });
      });
    });
  }


  /**
   * 清空文件数据库的搜索历史
   * @param filePath 最近文件
   * @returns 结果
   */
  public static clearSearchHistory(filePath: string): Promise<boolean> {
    return RecentFilesService.getRecentFile(filePath).then((recentFile) => {
      if (!recentFile) {
        return false;
      }
      recentFile.searchHistory = [];
      return RecentFilesService.addRecentFile(recentFile).then(result => {
        return true;
      });
    });
  }

  /**
   * 设置最近文件的密码
   * @param filePath 文件路径
   * @param password 密码
   * @returns 结果
   */
  public static addSearchHistory(filePath: string, keyword: string): Promise<boolean> {
    if (!filePath || !keyword) {
      return Promise.resolve(false);
    }
    const enableSearchHistory: boolean = SettingsService.isSearchHistoryEnable();
    if (!enableSearchHistory) {
      hilog.info(DOMAIN, TAG, `Search history is disabled`);
      return Promise.resolve(false);
    }
    return RecentFilesService.getRecentFile(filePath).then((recentFile) => {
      if (!recentFile) {
        return false;
      }
      // 添加搜索历史
      recentFile.searchHistory = recentFile.searchHistory ? recentFile.searchHistory : [];
      // 已经存在则直接移除
      recentFile.searchHistory = recentFile.searchHistory.filter(item => item !== keyword);
      // 添加搜索历史
      recentFile.searchHistory.unshift(keyword);
      // 最多保存10条
      recentFile.searchHistory = recentFile.searchHistory.slice(-10);
      return RecentFilesService.addRecentFile(recentFile).then(result => {
        return true;
      });
    });
  }

  /**
   * 获取搜索历史记录
   */
  public static getSearchHistory(filePath: string): Promise<Array<string>> {
    const enableSearchHistory: boolean = SettingsService.isSearchHistoryEnable();
    if (!enableSearchHistory) {
      hilog.info(DOMAIN, TAG, `Search history is disabled`);
      return Promise.resolve([]);
    }
    return RecentFilesService.getRecentFile(filePath).then((recentFile) => {
      if (!recentFile) {
        return [];
      }
      return recentFile.searchHistory ? recentFile.searchHistory : [];
    });
  }
}
