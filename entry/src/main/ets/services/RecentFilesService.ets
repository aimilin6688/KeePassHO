import preferences from '@ohos.data.preferences';
import { KdbxFileManager } from './kdbx/KdbxFileManager';
import { RecentFile } from './TypeDefined';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils, DeviceUtils, FileUtils } from '../common/utils';
import { fileShare } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { CryptoUtils } from '../common/utils/CryptoUtils';
import { SettingsService } from './SettingsService';
import { ErrorCodes, KeePassHoError } from './error/KeepassHoError';
import { SyncSettingsService } from './store/SyncSettingsService';
import { CacheConstants } from '../storage';

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
  private static readonly MAX_RECENT_FILES = 30; // 最多保存10个最近打开的文件
  private static readonly PASSWORD_VALIDITY_DAYS = 90; // 密码有效期为90天
  private preferences: preferences.Preferences | null = null;

  /**
   * 初始化主题管理器
   * @param context UIAbilityContext
   */
  public async init(context: common.UIAbilityContext): Promise<void> {
    try {
      this.preferences = preferences.getPreferencesSync(context, { name: RecentFilesService.PREFERENCES_NAME } as preferences.Options);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to get preferences: ${(err as BusinessError).code}, ${(err as BusinessError).message}`);
    }
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): RecentFilesService {
    return RecentFilesService.instance;
  }

  /**
   * 当文件拥有持久性授权时，才能添加到最近访问中
   * @param recentFile 最近打开的文件
   * @returns 结果
   * @throws KeePassHoError 路经不存在或者没有持久性授权
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
   * @throws KeePassHoError 路经不存在或者没有持久性授权
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
      if (!this.preferences) {
        return;
      }

      // 获取当前的最近文件列表
      const recentFiles = await this.getRecentFiles();

      // 检查文件是否已经在列表中
      const existingIndex = recentFiles.findIndex(file => file.filePath === recentFile.filePath);
      if (existingIndex !== -1) {
        // 如果未提供新的搜索历史,保留原有的搜索历史
        if (recentFile.searchHistory === undefined) {
          recentFile.searchHistory = recentFiles[existingIndex].searchHistory;
        }
        // 如果未提供新的密码保存时间,保留原有的时间
        if (recentFile.password && !recentFile.passwordSaveTime) {
          recentFile.passwordSaveTime = recentFiles[existingIndex].passwordSaveTime;
        }
        // 如果文件已经在列表中，则将其移除
        recentFiles.splice(existingIndex, 1);
      }

      // 如果保存了密码但没有记录时间,则记录当前时间
      if (recentFile.password && !recentFile.passwordSaveTime) {
        recentFile.passwordSaveTime = new Date().getTime();
        hilog.info(DOMAIN, TAG, 'Password save time set for file: %{public}s, time: %{public}d', recentFile.filePath, recentFile.passwordSaveTime);
      }

      // 将新文件添加到列表顶部
      recentFiles.unshift(recentFile);

      // 如果列表超过最大数量，删除最旧的记录
      if (recentFiles.length > RecentFilesService.MAX_RECENT_FILES) {
        recentFiles.pop();
      }

      // 保存更新后的列表
      await this.preferences.put(RecentFilesService.RECENT_FILES_KEY, JSON.stringify(recentFiles));
      await this.preferences.flush();

      // 同步到远端设备
      SyncSettingsService.syncRecentFiles(recentFiles);
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
      if (!this.preferences) {
        return [];
      }
      const recentFilesJson = await this.preferences.get(RecentFilesService.RECENT_FILES_KEY, '[]');
      let localFiles: RecentFile[] = JSON.parse(recentFilesJson.toString()) as RecentFile[];
      // 总是尝试与远端数据合并
      localFiles = await this.syncWithRemote(localFiles);
      // 检查并清除过期密码
      localFiles = this.checkAndClearExpiredPasswords(localFiles);

      return localFiles;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Get all recent files error: ${error}`);
      return [];
    }
  }

  /**
   * 检查并清除过期的密码
   * @param recentFiles 最近文件列表
   * @returns 清理后的最近文件列表
   */
  private checkAndClearExpiredPasswords(recentFiles: RecentFile[]): RecentFile[] {
    let needUpdate = false;
    const now = new Date().getTime();
    const maxAge = RecentFilesService.PASSWORD_VALIDITY_DAYS * 24 * 60 * 60 * 1000; // 90天的毫秒数

    recentFiles.forEach(file => {
      if (file.password && file.passwordSaveTime) {
        const age = now - file.passwordSaveTime;
        if (age > maxAge) {
          hilog.info(DOMAIN, TAG, 'Password expired for file: %{public}s, age: %{public}d ms', file.filePath, age);
          file.password = undefined;
          file.passwordSaveTime = undefined;
          needUpdate = true;
        }
      }
    });

    // 如果有密码被清除,更新存储
    if (needUpdate && this.preferences) {
      this.preferences.put(RecentFilesService.RECENT_FILES_KEY, JSON.stringify(recentFiles))
        .then(() => {
          return this.preferences!.flush();
        })
        .catch((error: Error) => {
          hilog.error(DOMAIN, TAG, `Update expired passwords error: ${error}`);
        });
    }
    return recentFiles;
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
      CommonUtils.showToast(error?.message);
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
   * 与远端数据同步
   * @param localFiles 本地文件列表
   * @returns 同步后的文件列表
   */
  private async syncWithRemote(localFiles: RecentFile[]): Promise<RecentFile[]> {
    try {
      if (!SyncSettingsService.isSyncEnabled()) {
        return localFiles;
      }

      // 确保同步服务已初始化
      await SyncSettingsService.init();
      const remoteFiles = await SyncSettingsService.getRemoteRecentFiles();

      if (remoteFiles && remoteFiles.length > 0) {
        hilog.info(DOMAIN, TAG, `Found ${remoteFiles.length} remote recent files, merging with local`);
        // 合并本地和远端文件列表
        const mergedFiles = RecentFilesService.mergeRecentFileLists(localFiles, remoteFiles);

        // 如果有合并结果，保存到本地
        if (mergedFiles.length > 0) {
          await this.doAddMerged(mergedFiles);
        }

        return mergedFiles;
      }

      return localFiles;
    } catch (syncError) {
      hilog.warn(DOMAIN, TAG, `Failed to sync with remote: ${syncError}`);
      return localFiles;
    }
  }

  /**
   * 合并最近文件列表
   * @param localFiles 本地文件列表
   * @param remoteFiles 远端文件列表
   * @returns 合并后的文件列表
   */
  public static mergeRecentFileLists(localFiles: RecentFile[], remoteFiles: RecentFile[]): RecentFile[] {
    const fileMap = new Map<string, RecentFile>();

    // 添加本地文件（优先级更高）
    localFiles.forEach(file => {
      if (file.filePath) {
        fileMap.set(file.filePath, file);
      }
    });

    // 添加远端文件（如果不存在则添加）
    remoteFiles.forEach(file => {
      if (file.filePath && !fileMap.has(file.filePath)) {
        fileMap.set(file.filePath, file);
      }
    });

    // 转换为数组：先保留本地文件的顺序，然后添加远端独有的文件
    const mergedFiles: RecentFile[] = [];

    // 首先添加本地文件，保持原有顺序
    localFiles.forEach(file => {
      if (file.filePath && fileMap.has(file.filePath)) {
        mergedFiles.push(fileMap.get(file.filePath)!);
        fileMap.delete(file.filePath); // 从map中删除，避免重复添加
      }
    });

    // 然后添加远端独有的文件
    remoteFiles.forEach(file => {
      if (file.filePath && fileMap.has(file.filePath)) {
        mergedFiles.push(fileMap.get(file.filePath)!);
      }
    });

    // 限制最大数量
    if (mergedFiles.length > RecentFilesService.MAX_RECENT_FILES) {
      return mergedFiles.slice(0, RecentFilesService.MAX_RECENT_FILES);
    }

    return mergedFiles;
  }

  /**
   * 合并最近文件列表（用于同步）
   * @param mergedFiles 合并后的文件列表
   */
  public async doAddMerged(mergedFiles: RecentFile[]): Promise<void> {
    try {
      if (!this.preferences) {
        return;
      }

      // 创建副本并限制最大数量
      let filesToSave = mergedFiles;
      if (filesToSave.length > RecentFilesService.MAX_RECENT_FILES) {
        filesToSave = filesToSave.slice(0, RecentFilesService.MAX_RECENT_FILES);
      }

      // 保存合并后的列表
      await this.preferences.put(RecentFilesService.RECENT_FILES_KEY, JSON.stringify(filesToSave));
      await this.preferences.flush();

      hilog.info(DOMAIN, TAG, `Merged recent files, count: ${filesToSave.length}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Merge recent files error: ${error}`);
      throw new Error(error);
    }
  }

  /**
   * 移除最近打开的文件
   * @param filePath 文件路径
   */
  public async removeRecentFile(recentFile: RecentFile): Promise<void> {
    try {
      if (!this.preferences) {
        return;
      }
      // 获取当前的最近文件列表
      const recentFiles = await this.getRecentFiles();

      // 移除指定文件
      const updatedFiles = recentFiles.filter(file => file.filePath !== recentFile.filePath);

      // 保存更新后的列表
      await this.preferences.put(RecentFilesService.RECENT_FILES_KEY, JSON.stringify(updatedFiles));
      await this.preferences.flush();

      // 同步到远端设备
      SyncSettingsService.syncRecentFiles(updatedFiles);

      // 删除本地缓存
      CacheConstants.deleteCache(recentFile.filePath);

      hilog.debug(DOMAIN, TAG, 'Remove recent file filePath:%{public}s', recentFile.filePath);
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
      if (!this.preferences) {
        return;
      }
      await this.preferences.put(RecentFilesService.RECENT_FILES_KEY, '[]');
      await this.preferences.flush();
      CacheConstants.deleteAllCache();
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
      }).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, `Clear password error: ${error}`);
        return false;
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
        }).catch((error: Error) => {
          hilog.error(DOMAIN, TAG, `Clear password error: ${error}`);
          return false;
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
      }).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, `Clear password error: ${error}`);
        return false;
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
      }).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, `Clear password error: ${error}`);
        return false;
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
