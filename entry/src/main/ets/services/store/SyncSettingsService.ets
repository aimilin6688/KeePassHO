import { DistributedKVService } from './DistributedKVService';
import { SettingsService } from '../SettingsService';
import { EventBus } from '../EventBus';
import { RecentFilesService } from '../RecentFilesService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RecentFile } from '../TypeDefined';
import { distributedKVStore } from '@kit.ArkData';
import { emitter } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';

const DOMAIN = 0x0000;
const TAG = 'SyncSettingsService';

/**
 * 同步数据类型
 */
interface SyncData {
  key: string;
  value: preferences.ValueType | RecentFile[];
  timestamp: number;
  deviceId: string;
}

/**
 * 同步设置服务
 * 负责管理设置和最近文件的跨设备同步
 */
export class SyncSettingsService {
  private static instance: SyncSettingsService | null = null;
  private static deviceId: string = '';
  private static isInitialized: boolean = false;

  private constructor() {
  }

  public static getInstance(): SyncSettingsService {
    if (!SyncSettingsService.instance) {
      SyncSettingsService.instance = new SyncSettingsService();
    }
    return SyncSettingsService.instance;
  }

  /**
   * 初始化同步服务
   */
  public static async init(): Promise<void> {
    if (SyncSettingsService.isInitialized) {
      return;
    }

    try {
      // 获取设备ID作为唯一标识
      SyncSettingsService.deviceId = await SyncSettingsService.generateDeviceId();

      // 订阅远端数据变化
      EventBus.on(EventBus.KV_DATA_CHANGE, (data: emitter.EventData) => SyncSettingsService.handleRemoteDataChange(data.data as distributedKVStore.ChangeNotification));

      SyncSettingsService.isInitialized = true;
      hilog.info(DOMAIN, TAG, `SyncSettingsService initialized with deviceId: ${SyncSettingsService.deviceId}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to initialize SyncSettingsService: ${error}`);
    }
  }

  /**
   * 生成设备ID
   */
  private static async generateDeviceId(): Promise<string> {
    // 使用时间戳和随机数生成设备ID
    const timestamp = Date.now();
    const random = Math.random().toString(36).substr(2, 9);
    return `device_${timestamp}_${random}`;
  }

  /**
   * 检查是否启用同步
   */
  public static isSyncEnabled(): boolean {
    return SettingsService.getInstance().getSync(
      SettingsService.KEY_APP_SYNC_SETTING_ENABLE,
      SettingsService.KEY_APP_SYNC_SETTING_ENABLE_DEFAULT
    );
  }

  /**
   * 同步设置到远端
   */
  public static async syncSetting(key: string, value: preferences.ValueType): Promise<void> {
    if (!(SyncSettingsService.isSyncEnabled())) {
      return;
    }

    try {
      const syncData: SyncData = {
        key: key,
        value: value,
        timestamp: Date.now(),
        deviceId: SyncSettingsService.deviceId
      };

      await DistributedKVService.put(`sync_${key}`, JSON.stringify(syncData) as string);
      hilog.debug(DOMAIN, TAG, `Synced setting: ${key}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to sync setting ${key}: ${error}`);
    }
  }

  /**
   * 同步最近文件到远端
   */
  public static async syncRecentFiles(recentFiles: RecentFile[]): Promise<void> {
    if (!(SyncSettingsService.isSyncEnabled())) {
      return;
    }

    try {
      const syncData: SyncData = {
        key: 'recent_files',
        value: recentFiles,
        timestamp: Date.now(),
        deviceId: SyncSettingsService.deviceId
      };

      await DistributedKVService.put('sync_recent_files', JSON.stringify(syncData) as string);
      hilog.debug(DOMAIN, TAG, 'Synced recent files');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to sync recent files: ${error}`);
    }
  }

  /**
   * 处理远端数据变化
   */
  private static async handleRemoteDataChange(data: distributedKVStore.ChangeNotification): Promise<void> {
    if (!(SyncSettingsService.isSyncEnabled())) {
      return;
    }

    try {
      hilog.debug(DOMAIN, TAG, `Received remote data change: ${JSON.stringify(data)}`);

      if (data.insertEntries && data.insertEntries.length > 0) {
        for (const entry of data.insertEntries) {
          const value = typeof entry.value === 'string' ? entry.value : JSON.stringify(entry.value);
          await SyncSettingsService.processRemoteEntry(entry.key, value);
        }
      }

      if (data.updateEntries && data.updateEntries.length > 0) {
        for (const entry of data.updateEntries) {
          const value = typeof entry.value === 'string' ? entry.value : JSON.stringify(entry.value);
          await SyncSettingsService.processRemoteEntry(entry.key, value);
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to handle remote data change: ${error}`);
    }
  }

  /**
   * 处理远端条目
   */
  private static async processRemoteEntry(key: string, value: Uint8Array | string | number | boolean): Promise<void> {
    // 只处理同步相关的键
    if (!key.startsWith('sync_')) {
      return;
    }

    try {
      const syncData: SyncData = JSON.parse((value as string).toString()) as SyncData;

      // 忽略自己发出的同步数据
      if (syncData.deviceId === SyncSettingsService.deviceId) {
        return;
      }

      const settingKey = syncData.key;

      if (settingKey === 'recent_files') {
        return SyncSettingsService.mergeRecentFiles(syncData);
      } else {
        return SyncSettingsService.mergeSetting(syncData);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to process remote entry ${key}: ${error}`);
    }
  }

  /**
   * 合并设置
   */
  private static async mergeSetting(remoteSyncData: SyncData): Promise<void> {
    try {
      const settingsService = SettingsService.getInstance();
      const currentValue = await settingsService.get(remoteSyncData.key, '' as preferences.ValueType);

      if (currentValue === '' || currentValue === undefined) {
        // 本地没有值，直接使用远端值
        await settingsService.put(remoteSyncData.key, remoteSyncData.value as preferences.ValueType);
        hilog.debug(DOMAIN, TAG, `Applied remote setting: ${remoteSyncData.key}`);
        return;
      }

      // 获取本地时间戳（如果有的话）
      const localTimestamp = await SyncSettingsService.getLocalTimestamp(remoteSyncData.key);

      if (!localTimestamp || remoteSyncData.timestamp > localTimestamp) {
        // 远端数据更新，使用远端值
        await settingsService.put(remoteSyncData.key, remoteSyncData.value as preferences.ValueType);
        await SyncSettingsService.setLocalTimestamp(remoteSyncData.key, remoteSyncData.timestamp);
        hilog.debug(DOMAIN, TAG, `Merged remote setting: ${remoteSyncData.key}`);
      } else {
        hilog.debug(DOMAIN, TAG, `Local setting is newer: ${remoteSyncData.key}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to merge setting ${remoteSyncData.key}: ${error}`);
    }
  }

  /**
   * 合并最近文件
   */
  private static async mergeRecentFiles(remoteSyncData: SyncData): Promise<void> {
    try {
      const recentFilesService = RecentFilesService.getInstance();
      const localRecentFiles = await recentFilesService.getRecentFiles();
      const remoteRecentFiles: RecentFile[] = remoteSyncData.value as RecentFile[];

      const localTimestamp = await SyncSettingsService.getLocalTimestamp('recent_files');

      if (!localTimestamp || remoteSyncData.timestamp > localTimestamp) {
        // 远端数据更新，合并文件列表
        const mergedFiles = RecentFilesService.mergeRecentFileLists(localRecentFiles, remoteRecentFiles);
        await recentFilesService.doAddMerged(mergedFiles);
        await SyncSettingsService.setLocalTimestamp('recent_files', remoteSyncData.timestamp);
        hilog.debug(DOMAIN, TAG, 'Merged remote recent files');
      } else {
        hilog.debug(DOMAIN, TAG, 'Local recent files are newer');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to merge recent files: ${error}`);
    }
  }



  /**
   * 获取本地时间戳
   */
  private static async getLocalTimestamp(key: string): Promise<number | null> {
    try {
      const timestamp = await SettingsService.getInstance().get(`timestamp_${key}`, 0);
      return timestamp > 0 ? timestamp : null;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get local timestamp for ${key}: ${error}`);
      return null;
    }
  }

  /**
   * 设置本地时间戳
   */
  private static async setLocalTimestamp(key: string, timestamp: number): Promise<void> {
    try {
      await SettingsService.getInstance().put(`timestamp_${key}`, timestamp);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to set local timestamp for ${key}: ${error}`);
    }
  }

  /**
   * 手动触发全量同步
   */
  public static async triggerFullSync(): Promise<void> {
    if (!(SyncSettingsService.isSyncEnabled())) {
      return;
    }

    try {
      hilog.info(DOMAIN, TAG, 'Triggering full sync');

      // 先从远端拉取最新数据进行合并
      await SyncSettingsService.fetchAndMergeRemoteData();

      // 然后同步本地数据到远端
      await SyncSettingsService.pushLocalDataToRemote();

      hilog.info(DOMAIN, TAG, 'Full sync completed');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to trigger full sync: ${error}`);
    }
  }

  /**
   * 从远端获取数据并与本地合并
   */
  private static async fetchAndMergeRemoteData(): Promise<void> {
    try {
      hilog.debug(DOMAIN, TAG, 'Fetching and merging remote data');

      // 获取并合并远端最近文件
      const remoteRecentFiles = await SyncSettingsService.getRemoteRecentFiles();
      if (remoteRecentFiles) {
        const remoteSyncData: SyncData = {
          key: 'recent_files',
          value: remoteRecentFiles,
          timestamp: Date.now(), // 使用当前时间作为合并时间戳
          deviceId: SyncSettingsService.deviceId
        };
        await SyncSettingsService.mergeRecentFiles(remoteSyncData);
      }

      // 获取并合并远端设置数据
      await SyncSettingsService.fetchAndMergeRemoteSettings();

      hilog.debug(DOMAIN, TAG, 'Remote data fetch and merge completed');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to fetch and merge remote data: ${error}`);
    }
  }

  /**
   * 获取并合并远端设置数据
   */
  private static async fetchAndMergeRemoteSettings(): Promise<void> {
    try {
      // 获取所有本地设置键
      const allSettings = SettingsService.getAll();
      const localSettingKeys = Object.keys(allSettings);

      // 过滤掉时间戳键和同步相关键，只获取真实的设置键
      const realSettingKeys = localSettingKeys.filter(key => 
        !key.startsWith('timestamp_') && 
        key !== SettingsService.KEY_APP_SYNC_SETTING_ENABLE
      );

      for (const key of realSettingKeys) {
        try {
          const remoteSyncDataJson = await DistributedKVService.get(`sync_${key}`);
          if (remoteSyncDataJson) {
            const remoteSyncData: SyncData = JSON.parse(remoteSyncDataJson.toString()) as SyncData;
            if (remoteSyncData.key === key && remoteSyncData.deviceId !== SyncSettingsService.deviceId) {
              await SyncSettingsService.mergeSetting(remoteSyncData);
            }
          }
        } catch (error) {
          hilog.error(DOMAIN, TAG, `Failed to fetch and merge remote setting ${key}: ${error}`);
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to fetch and merge remote settings: ${error}`);
    }
  }

  /**
   * 推送本地数据到远端
   */
  private static async pushLocalDataToRemote(): Promise<void> {
    try {
      hilog.debug(DOMAIN, TAG, 'Pushing local data to remote');

      // 推送设置数据
      const settingsService = SettingsService.getInstance();
      
      // 获取所有本地设置键，自动发现需要同步的设置
      const allSettings = SettingsService.getAll();
      const localSettingKeys = Object.keys(allSettings);

      // 过滤掉时间戳键和同步相关键，只同步真实的设置键
      const realSettingKeys = localSettingKeys.filter(key => 
        !key.startsWith('timestamp_') && 
        key !== SettingsService.KEY_APP_SYNC_SETTING_ENABLE
      );

      for (const key of realSettingKeys) {
        try {
          const value = await settingsService.get(key, '' as preferences.ValueType);
          if (value !== undefined && value !== '') {
            await SyncSettingsService.syncSetting(key, value);
          }
        } catch (error) {
          hilog.error(DOMAIN, TAG, `Failed to push setting ${key} during full sync: ${error}`);
        }
      }

      // 推送最近文件
      const recentFiles = await RecentFilesService.getInstance().getRecentFiles();
      await SyncSettingsService.syncRecentFiles(recentFiles);

      hilog.info(DOMAIN, TAG, 'Local data push to remote completed');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to push local data to remote: ${error}`);
    }
  }

  /**
   * 从远端获取最近文件数据
   */
  public static async getRemoteRecentFiles(): Promise<RecentFile[] | null> {
    try {
      const syncDataJson = await DistributedKVService.get('sync_recent_files');
      if (syncDataJson) {
        const syncData: SyncData = JSON.parse(syncDataJson.toString()) as SyncData;
        if (syncData.key === 'recent_files' && syncData.deviceId !== SyncSettingsService.deviceId) {
          return syncData.value as RecentFile[];
        }
      }
      return null;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get remote recent files: ${error}`);
      return null;
    }
  }
}