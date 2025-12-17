import { distributedKVStore } from '@kit.ArkData';
import { bundleManager, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EventBus } from '../EventBus';

const DOMAIN = 0x0000;
const TAG = 'DistributedKVService';

/**
 * 分布式KV存储服务
 */
export class DistributedKVService {
  private static kvManager: distributedKVStore.KVManager | undefined = undefined;
  private static kvStore: distributedKVStore.SingleKVStore | undefined = undefined;
  private static appId: string | undefined = undefined;
  private static readonly kvStoreName: string = 'SingleKVStore';

  /**
   * 初始化
   * @param context 上下文
   * @returns
   */
  public static init(context: common.UIAbilityContext): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
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

          const options: distributedKVStore.Options = {
            createIfMissing: true,
            encrypt: false,
            backup: false,
            autoSync: true,
            kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
            securityLevel: distributedKVStore.SecurityLevel.S3
          };
          // 获取KVStore
          DistributedKVService.kvManager.getKVStore<distributedKVStore.SingleKVStore>(DistributedKVService.kvStoreName, options)
            .then((store: distributedKVStore.SingleKVStore) => {
              hilog.info(DOMAIN, TAG, "Succeeded in getting KVStore");
              DistributedKVService.kvStore = store;
              // 订阅远端数据变化
              DistributedKVService.kvStore.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_REMOTE, DistributedKVService.onDataChange);
            })
            .catch((err: BusinessError<Object>) => {
              hilog.error(DOMAIN, TAG, `Failed to get KVStore.code is ${err.code},message is ${err.message}`);
            });
        })
      } catch (err) {
        hilog.error(DOMAIN, TAG, `DistributedKVService init error: ${err?.code}, ${err?.message}`);
        return reject(err)
      }
    })
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
      return DistributedKVService.kvStore?.put(key, value).catch((err: BusinessError<Object>) => {
        hilog.error(DOMAIN, TAG, `Failed to put data. Key:${key}, Code:${err?.code},message:${err?.message}`);
        return reject(err);
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
      return DistributedKVService.kvStore?.get(key).catch((err: BusinessError<Object>) => {
        hilog.error(DOMAIN, TAG, `Failed to get data. Key:${key}, Code:${err?.code},message:${err?.message}`);
        return reject(err);
      });
    });
  }

  /**
   * 调用get()方法从键值数据库中获取数据
   * @param key
   * @returns
   */
  public static delete(key: string): Promise<void> {
    return new Promise((resolve, reject) => {
      return DistributedKVService.kvStore?.delete(key).catch((err: BusinessError<Object>) => {
        hilog.error(DOMAIN, TAG, `Failed to delete data. Key:${key}, Code:${err?.code},message:${err?.message}`);
        return reject(err);
      });
    });
  }

  /**
   * 关闭KVStore
   */
  public static close(): void {
    try {
      if (DistributedKVService.kvManager) {
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