import preferences from '@ohos.data.preferences';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils } from 'kdbxweb';
import { CommonUtils } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDrivePathCacheStore';

/**
 * 独立 preferences 文件名
 * 不复用主设置存储（SettingsService），避免缓存写入触发分布式同步与观察者通知
 */
const STORE_NAME = 'huawei_drive_path_cache';
/**
 * 缓存数据键
 */
const KEY_PATH_CACHE = 'path_id_cache';
/**
 * 数据格式版本（不兼容变更时递增，旧数据直接丢弃）
 */
const CACHE_VERSION = 1;
/**
 * 账号指纹长度（取 SHA-256 hex 前16位足够区分账号）
 */
const OWNER_HASH_LENGTH = 16;

/**
 * 持久化的路径→fileId 缓存条目
 */
export interface HuaweiDrivePathCacheEntry {
  /**
   * 规范化路径（无前导'/'）
   */
  p: string;
  /**
   * 华为云盘文件ID
   */
  id: string;
}

/**
 * 持久化的缓存数据
 */
export interface HuaweiDrivePathCacheData {
  /**
   * 账号指纹（refreshToken 明文的 SHA-256 hex 截断，磁盘不保存明文令牌）
   */
  owner: string;
  /**
   * 根目录真实 fileId
   */
  rootId: string;
  /**
   * 路径→fileId 条目
   */
  entries: HuaweiDrivePathCacheEntry[];
}

/**
 * JSON 反序列化的原始模型（严格校验前）
 */
interface PathCacheRaw {
  v: number;
  owner: string;
  rootId: string;
  entries: Array<HuaweiDrivePathCacheEntry>;
}

/**
 * 华为云盘 路径→fileId 缓存的磁盘持久化存储
 * 独立 preferences 文件，冷启动时水合到 HuaweiDriveStorage 的静态缓存，
 * 避免每次启动都通过逐级 list 下钻解析路径
 */
export class HuaweiDrivePathCacheStore {
  private static store: preferences.Preferences | null = null;
  private static opening: Promise<preferences.Preferences> | null = null;

  /**
   * 惰性打开独立 preferences 文件（单飞，避免并发重复打开）
   */
  private static async getStore(): Promise<preferences.Preferences> {
    if (HuaweiDrivePathCacheStore.store) {
      return HuaweiDrivePathCacheStore.store;
    }
    if (HuaweiDrivePathCacheStore.opening) {
      return HuaweiDrivePathCacheStore.opening;
    }
    HuaweiDrivePathCacheStore.opening = preferences.getPreferences(CommonUtils.getContext(), STORE_NAME)
      .then((opened: preferences.Preferences) => {
        HuaweiDrivePathCacheStore.store = opened;
        HuaweiDrivePathCacheStore.opening = null;
        return opened;
      });
    return HuaweiDrivePathCacheStore.opening;
  }

  /**
   * 计算账号指纹（明文 refreshToken 的 SHA-256 hex 前16位）
   * 仅在内存→磁盘边界使用，磁盘上不留明文令牌
   * @param ownerKey 内存中的账号指纹（refreshToken 明文）
   */
  public static async ownerHash(ownerKey: string): Promise<string> {
    if (!ownerKey) {
      return '';
    }
    const md = cryptoFramework.createMd('SHA256');
    const encoder = new util.TextEncoder();
    const dataBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(ownerKey) };
    await md.update(dataBlob);
    const result = await md.digest();
    return ByteUtils.bytesToHex(result.data).substring(0, OWNER_HASH_LENGTH);
  }

  /**
   * 读取持久化缓存
   * @returns 校验通过的数据；无数据/格式不符/读取失败返回 null
   */
  public static async load(): Promise<HuaweiDrivePathCacheData | null> {
    try {
      const store = await HuaweiDrivePathCacheStore.getStore();
      const value: preferences.ValueType = store.getSync(KEY_PATH_CACHE, '');
      if (typeof value !== 'string' || !value) {
        return null;
      }
      return HuaweiDrivePathCacheStore.parse(value);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Load path cache failed: %{public}s', (error as Error).message);
      return null;
    }
  }

  /**
   * 保存缓存（序列化 + put + flush 落盘），失败仅告警不影响主流程
   */
  public static async save(data: HuaweiDrivePathCacheData): Promise<void> {
    try {
      const store = await HuaweiDrivePathCacheStore.getStore();
      const raw: PathCacheRaw = {
        v: CACHE_VERSION,
        owner: data.owner,
        rootId: data.rootId,
        entries: data.entries
      };
      await store.put(KEY_PATH_CACHE, JSON.stringify(raw));
      await store.flush();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Save path cache failed: %{public}s', (error as Error).message);
    }
  }

  /**
   * 清空磁盘缓存（退出登录时调用，避免残留上一个账号的映射数据）
   */
  public static async clear(): Promise<void> {
    try {
      const store = await HuaweiDrivePathCacheStore.getStore();
      await store.delete(KEY_PATH_CACHE);
      await store.flush();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Clear path cache failed: %{public}s', (error as Error).message);
    }
  }

  /**
   * 严格解析：cast 到原始模型 → 逐字段校验 → 构造严格模型
   * 任何字段异常均返回 null（视为无缓存，走正常网络解析）
   */
  private static parse(jsonStr: string): HuaweiDrivePathCacheData | null {
    try {
      const raw = JSON.parse(jsonStr) as PathCacheRaw;
      if (typeof raw.v !== 'number' || raw.v !== CACHE_VERSION) {
        return null;
      }
      if (typeof raw.owner !== 'string' || !raw.owner) {
        return null;
      }
      if (typeof raw.rootId !== 'string') {
        return null;
      }
      if (!Array.isArray(raw.entries)) {
        return null;
      }
      const entries: HuaweiDrivePathCacheEntry[] = [];
      for (const item of raw.entries) {
        if (item && typeof item.p === 'string' && typeof item.id === 'string' && item.p && item.id) {
          entries.push({ p: item.p, id: item.id });
        }
      }
      return { owner: raw.owner, rootId: raw.rootId, entries: entries };
    } catch {
      return null;
    }
  }
}
