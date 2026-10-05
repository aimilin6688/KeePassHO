import { hilog } from '@kit.PerformanceAnalysisKit';
import { AttachmentStore, ByteUtils } from 'kdbxweb';
import { Constants } from '../../common/constants/Constants';
import { AssetUtils } from '../../common/utils/AssetUtils';
import { CommonUtils } from '../../common/utils/CommonUtils';

const DOMAIN = 0x0000;
const TAG = 'AttachmentCacheService';
const KEY_LENGTH_BYTES = 32;

/**
 * 附件加密磁盘缓存服务（S4 附件磁盘化）。
 *
 * 缓存密钥 32 字节随机数，持久化于 Asset Kit（DEVICE_FIRST_UNLOCKED + 可信同步），
 * 主线程在创建 Worker 时解析快照注入；Worker 线程无 Context/Asset Kit 环境，
 * 仅使用注入密钥（与 filesDir/cacheDir 注入同一模式）。
 *
 * 任一环节失败（无密钥/目录不可写）均优雅降级为 undefined（纯内存模式），
 * 不影响数据库加载，仅放弃磁盘化收益。
 */
export class AttachmentCacheService {
  private static store: AttachmentStore | undefined = undefined;
  private static storeCreateFailed: boolean = false;
  // Worker 线程注入的缓存密钥（base64）
  private static injectedKeyBase64: string = '';

  /**
   * Worker 初始化：注入主线程解析的缓存密钥
   */
  public static setWorkerKey(keyBase64: string): void {
    AttachmentCacheService.injectedKeyBase64 = keyBase64;
  }

  /**
   * 主线程：解析（不存在则生成并持久化）缓存密钥，供 Worker 初始化消息使用。
   * 任何失败返回空字符串（Worker 端禁用磁盘化）。
   */
  public static getWorkerKeyBase64(): string {
    try {
      let keyBase64 = AssetUtils.querySync(Constants.ATTACH_CACHE_ASSET_ALIAS);
      if (!keyBase64) {
        const key = ByteUtils.randomData(KEY_LENGTH_BYTES);
        keyBase64 = ByteUtils.bytesToBase64(key);
        AssetUtils.saveSync(Constants.ATTACH_CACHE_ASSET_ALIAS, keyBase64);
      }
      return keyBase64;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'resolve cache key failed: %{public}s', `${error}`);
      return '';
    }
  }

  /**
   * 当前线程的附件缓存 store；未初始化时创建。
   * @returns store；密钥不可用/目录不可写时返回 undefined（纯内存模式）
   */
  public static getStore(): AttachmentStore | undefined {
    if (AttachmentCacheService.store) {
      return AttachmentCacheService.store;
    }
    if (AttachmentCacheService.storeCreateFailed) {
      return undefined;
    }
    try {
      const keyBase64 = AttachmentCacheService.resolveKeyBase64();
      if (!keyBase64) {
        // 密钥不可用：本线程禁用磁盘化，避免主/子线程模式不一致的中间态
        AttachmentCacheService.storeCreateFailed = true;
        return undefined;
      }
      const keyBytes = ByteUtils.base64ToBytes(keyBase64);
      if (keyBytes.length !== KEY_LENGTH_BYTES) {
        hilog.error(DOMAIN, TAG, 'bad cache key length: %{public}d', keyBytes.length);
        AttachmentCacheService.storeCreateFailed = true;
        return undefined;
      }
      const dir = `${CommonUtils.getAppFilesDir()}/${Constants.ATTACH_CACHE_DIR_NAME}`;
      AttachmentCacheService.store = new AttachmentStore(dir, keyBytes);
      AttachmentCacheService.scheduleSweep();
      return AttachmentCacheService.store;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'create store failed: %{public}s', `${error}`);
      AttachmentCacheService.storeCreateFailed = true;
      return undefined;
    }
  }

  /**
   * S4 附件磁盘化阈值（字节）；store 不可用时为 undefined（禁用）
   */
  public static getAttachmentsDiskThreshold(): number | undefined {
    if (!AttachmentCacheService.getStore()) {
      return undefined;
    }
    return Constants.ATTACH_DISK_THRESHOLD_BYTES;
  }

  /**
   * 重置线程内缓存（如设置页清除缓存后重建）
   */
  public static reset(): void {
    AttachmentCacheService.store = undefined;
    AttachmentCacheService.storeCreateFailed = false;
  }

  /**
   * LRU 清理缓存目录（best effort，异步执行不阻塞）
   */
  public static scheduleSweep(): void {
    const store = AttachmentCacheService.store;
    if (!store) {
      return;
    }
    store.sweep(Constants.ATTACH_CACHE_MAX_TOTAL_BYTES).catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'sweep failed: %{public}s', `${error}`);
    });
  }

  private static resolveKeyBase64(): string {
    if (CommonUtils.hasContext()) {
      // 主线程：Asset Kit 实时解析（不存在则生成）
      return AttachmentCacheService.getWorkerKeyBase64();
    }
    // Worker 线程：使用 INIT 消息注入的密钥快照
    return AttachmentCacheService.injectedKeyBase64;
  }
}
