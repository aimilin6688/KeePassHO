import { distributedKVStore } from '@kit.ArkData';
import { bundleManager, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EventBus } from '../EventBus';
import { BusinessError } from '@kit.BasicServicesKit';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';

const DOMAIN = 0x0000;
const TAG = 'DistributedKVService';

// 设备状态变化回调数据
interface DeviceStateChangeData {
  action: distributedDeviceManager.DeviceStateChange;
  device: distributedDeviceManager.DeviceBasicInfo;
}

/**
 * 分布式KV存储服务
 */
export class DistributedKVService {
  private static kvManager: distributedKVStore.KVManager | undefined = undefined;
  private static kvStore: distributedKVStore.SingleKVStore | undefined = undefined;
  private static appId: string | undefined = undefined;
  private static readonly kvStoreName: string = 'SingleKVStore';
  private static deviceManager: distributedDeviceManager.DeviceManager | undefined = undefined;
  private static context: common.UIAbilityContext | undefined = undefined;

  /**
   * 初始化
   * @param context 上下文
   * @returns
   */
  public static init(context: common.UIAbilityContext): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
        DistributedKVService.context = context;
        // 获取当前应用的包名
        bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).then((result) => {
          DistributedKVService.appId = result.name;
          const kvManagerConfig: distributedKVStore.KVManagerConfig = {
            context: context,
            bundleName: result.name
          };
          // 创建KVManager
          DistributedKVService.kvManager = distributedKVStore.createKVManager(kvManagerConfig);
          if (DistributedKVService.kvManager == undefined) {
            hilog.error(DOMAIN, TAG, 'Failed to create KVManager.');
            return reject(new Error('Failed to create KVManager'));
          }
          hilog.debug(DOMAIN, TAG, 'Succeeded in creating KVManager.');

          // 使用 S1 安全级别以确保跨设备兼容性
          const options: distributedKVStore.Options = {
            createIfMissing: true,
            encrypt: false,
            backup: false,
            autoSync: false,
            kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
            securityLevel: distributedKVStore.SecurityLevel.S1
          };
          // 获取KVStore
          DistributedKVService.kvManager.getKVStore<distributedKVStore.SingleKVStore>(DistributedKVService.kvStoreName, options)
            .then((store: distributedKVStore.SingleKVStore) => {
              hilog.info(DOMAIN, TAG, "Succeeded in getting KVStore");
              DistributedKVService.kvStore = store;
              // 订阅远端数据变化
              DistributedKVService.kvStore.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_REMOTE, DistributedKVService.onDataChange);
              // 订阅同步完成事件
              DistributedKVService.kvStore.on('syncComplete', DistributedKVService.onSyncComplete);
              // 初始化设备管理器
              DistributedKVService.initDeviceManager();
              // 监听分布式数据服务终止
              if (DistributedKVService.kvManager) {
                DistributedKVService.kvManager.on('distributedDataServiceDie', DistributedKVService.onServiceDie);
              }
              // 初始化完成后触发一次同步，拉取远端最新数据
              DistributedKVService.sync(distributedKVStore.SyncMode.PUSH_PULL);
              resolve();
            })
            .catch((err: BusinessError<Object>) => {
              hilog.error(DOMAIN, TAG, `Failed to get KVStore.code is ${err.code},message is ${err.message}`);
              reject(err);
            });
        })
      } catch (err) {
        hilog.error(DOMAIN, TAG, `DistributedKVService init error: ${err?.code}, ${err?.message}`);
        return reject(err)
      }
    })
  }

  /**
   * 初始化设备管理器
   */
  private static initDeviceManager(): void {
    try {
      if (!DistributedKVService.appId) {
        hilog.error(DOMAIN, TAG, 'appId is not initialized');
        return;
      }
      DistributedKVService.deviceManager = distributedDeviceManager.createDeviceManager(DistributedKVService.appId);
      // 监听设备状态变化（上线/下线）
      DistributedKVService.deviceManager.on('deviceStateChange', DistributedKVService.onDeviceStateChange);
      hilog.info(DOMAIN, TAG, 'Device manager initialized');
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to create device manager: ${err?.code}, ${err?.message}`);
    }
  }

  /**
   * 获取在线设备的 networkId 列表
   */
  public static getConnectedDeviceIds(): string[] {
    try {
      if (!DistributedKVService.deviceManager) {
        hilog.warn(DOMAIN, TAG, 'Device manager is not initialized');
        return [];
      }
      const devices = DistributedKVService.deviceManager.getAvailableDeviceListSync();
      const deviceIds: string[] = [];
      for (const device of devices) {
        if (device.networkId !== undefined && device.networkId !== '') {
          deviceIds.push(device.networkId);
        }
      }
      hilog.info(DOMAIN, TAG, `Available devices: ${deviceIds.length}`);
      return deviceIds;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to get device list: ${err?.code}, ${err?.message}`);
      return [];
    }
  }

  /**
   * 手动触发同步
   * @param mode 同步模式，默认 PUSH_PULL
   */
  public static sync(mode: distributedKVStore.SyncMode = distributedKVStore.SyncMode.PUSH_PULL): void {
    try {
      if (!DistributedKVService.kvStore) {
        hilog.warn(DOMAIN, TAG, 'KVStore is not initialized, cannot sync');
        return;
      }
      const deviceIds = DistributedKVService.getConnectedDeviceIds();
      if (deviceIds.length === 0) {
        hilog.info(DOMAIN, TAG, 'No connected devices, skip sync');
        return;
      }
      DistributedKVService.kvStore.sync(deviceIds, mode);
      hilog.info(DOMAIN, TAG, `Sync triggered with mode ${mode} to ${deviceIds.length} devices`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to sync: ${err?.code}, ${err?.message}`);
    }
  }

  /**
   * 同步完成回调
   */
  private static onSyncComplete(data: Array<[string, number]>): void {
    try {
      hilog.info(DOMAIN, TAG, `Sync complete: ${JSON.stringify(data)}`);
      EventBus.emit(EventBus.KV_SYNC_COMPLETE, data);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `onSyncComplete error: ${err?.code}, ${err?.message}`);
    }
  }

  /**
   * 分布式数据服务终止回调
   */
  private static onServiceDie(): void {
    hilog.warn(DOMAIN, TAG, 'Distributed data service died, need to re-register callbacks');
    // 服务终止后需要重新注册回调
    if (DistributedKVService.kvStore) {
      try {
        DistributedKVService.kvStore.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_REMOTE, DistributedKVService.onDataChange);
        DistributedKVService.kvStore.on('syncComplete', DistributedKVService.onSyncComplete);
        hilog.info(DOMAIN, TAG, 'Re-registered callbacks after service die');
      } catch (err) {
        hilog.error(DOMAIN, TAG, `Failed to re-register callbacks: ${err?.code}, ${err?.message}`);
      }
    }
  }

  /**
   * 设备状态变化回调（上线/下线）
   */
  private static onDeviceStateChange(data: DeviceStateChangeData): void {
    try {
      hilog.info(DOMAIN, TAG, `Device state change: action=${data.action}, device=${data.device.deviceName}`);
      if (data.action === distributedDeviceManager.DeviceStateChange.AVAILABLE) {
        hilog.info(DOMAIN, TAG, `Device available: ${data.device.deviceName}, triggering sync`);
        DistributedKVService.sync(distributedKVStore.SyncMode.PUSH_PULL);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `onDeviceStateChange error: ${err?.code}, ${err?.message}`);
    }
  }

  /**
   * 调用put()方法向键值数据库中插入数据
   * @param key
   * @param value
   * @returns
   */
  public static put(key: string, value: Uint8Array | string | number | boolean): Promise<void> {
    hilog.debug(DOMAIN, TAG, `KVStore put data. Key:${key}, Value:${value}`);
    return new Promise((resolve, reject) => {
      if (!DistributedKVService.kvStore) {
        reject(new Error('KVStore is not initialized'));
        return;
      }
      DistributedKVService.kvStore.put(key, value).then(() => {
        // 写入后自动触发推送同步
        DistributedKVService.sync(distributedKVStore.SyncMode.PUSH_ONLY);
        resolve();
      }).catch((err: BusinessError<Object>) => {
        hilog.error(DOMAIN, TAG, `Failed to put data. Key:${key}, Code:${err?.code},message:${err?.message}`);
        reject(err);
      });
    });
  }

  /**
   * 调用get()方法从键值数据库中获取数据
   * @param key
   * @returns
   */
  public static get(key: string): Promise<boolean | string | number | Uint8Array> {
    return new Promise((resolve, reject) => {
      if (!DistributedKVService.kvStore) {
        reject(new Error('KVStore is not initialized'));
        return;
      }
      DistributedKVService.kvStore.get(key).then((value) => {
        resolve(value);
      }).catch((err: BusinessError<Object>) => {
        hilog.error(DOMAIN, TAG, `Failed to get data. Key:${key}, Code:${err?.code},message:${err?.message}`);
        reject(err);
      });
    });
  }

  /**
   * 调用delete()方法从键值数据库中删除数据
   * @param key
   * @returns
   */
  public static delete(key: string): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!DistributedKVService.kvStore) {
        reject(new Error('KVStore is not initialized'));
        return;
      }
      DistributedKVService.kvStore.delete(key).then(() => {
        // 删除后同步
        DistributedKVService.sync(distributedKVStore.SyncMode.PUSH_ONLY);
        resolve();
      }).catch((err: BusinessError<Object>) => {
        hilog.error(DOMAIN, TAG, `Failed to delete data. Key:${key}, Code:${err?.code},message:${err?.message}`);
        reject(err);
      });
    });
  }

  /**
   * 关闭KVStore
   */
  public static close(): void {
    try {
      // 取消订阅设备状态变化
      if (DistributedKVService.deviceManager) {
        DistributedKVService.deviceManager.off('deviceStateChange', DistributedKVService.onDeviceStateChange);
      }
      // 取消订阅KVStore事件
      if (DistributedKVService.kvStore) {
        DistributedKVService.kvStore.off('dataChange', DistributedKVService.onDataChange);
        DistributedKVService.kvStore.off('syncComplete', DistributedKVService.onSyncComplete);
      }
      if (DistributedKVService.kvManager) {
        DistributedKVService.kvManager.off('distributedDataServiceDie', DistributedKVService.onServiceDie);
        DistributedKVService.kvManager.closeKVStore(DistributedKVService.appId, DistributedKVService.kvStoreName, (err: BusinessError<void>) => {
          if (err) {
            hilog.error(DOMAIN, TAG, `Failed to close KVStore.code is ${err?.code},message is ${err?.message}`);
            return;
          }
          hilog.info(DOMAIN, TAG, 'Succeeded in closing KVStore');
        });
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `DistributedKVService close error: ${err?.code}, ${err?.message}`);
    }
  }

  /**
   * 订阅远端数据变化
   * @param data 数据变化通知
   */
  public static onDataChange(data: distributedKVStore.ChangeNotification) {
    try {
      hilog.debug(DOMAIN, TAG, `KVStore onDataChange: ${JSON.stringify(data)}`);
      EventBus.emit(EventBus.KV_DATA_CHANGE, data);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `KVStore onDataChange error: ${err?.code}, ${err?.message}`);
    }
  }
}
