import preferences from '@ohos.data.preferences';
import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils } from 'kdbxweb';
import { CommonUtils } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDrivePathCacheStore';

/**
 * 持久化文件名（filesDir 下 JSON 文件）
 * 不复用主设置存储（SettingsService），避免缓存写入触发分布式同步与观察者通知
 */
const FILE_NAME = 'huawei_drive_path_cache.json';
/**
 * 旧 preferences 后端文件名（主线程一次性迁移用）
 */
const LEGACY_PREFERENCES_NAME = 'huawei_drive_path_cache';
/**
 * 缓存数据键（旧 preferences 后端键名，迁移时读取）
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
 * 后端为 filesDir 下 JSON 文件：Worker 线程无 Context/preferences（设计文档 §11.1），
 * 文件后端经注入路径在主线程与 Worker 通用，修复 Worker 内"水合/落盘失败 → 每次操作重新逐级下钻"的问题。
 * 冷启动时水合到 HuaweiDriveStorage 的静态缓存，避免每次启动都通过逐级 list 下钻解析路径；
 * 主线程首次访问时一次性迁移旧 preferences 数据。
 */
export class HuaweiDrivePathCacheStore {
  /**
   * 持久化文件路径（懒取：主线程取自 Context，Worker 取注入路径）
   */
  private static cachedFilePath: string = '';
  /**
   * 旧 preferences 迁移完成标记（仅主线程，一次即可）
   */
  private static migrated: boolean = false;
  /**
   * 写链：串行化文件写入，避免并发丢失更新
   */
  private static writeChain: Promise<void> = Promise.resolve();

  /**
   * 持久化文件路径
   */
  private static getFilePath(): string {
    if (!HuaweiDrivePathCacheStore.cachedFilePath) {
      HuaweiDrivePathCacheStore.cachedFilePath = CommonUtils.getAppFilesDir() + '/' + FILE_NAME;
    }
    return HuaweiDrivePathCacheStore.cachedFilePath;
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
      await HuaweiDrivePathCacheStore.migrateLegacyOnce();
      if (!fs.accessSync(HuaweiDrivePathCacheStore.getFilePath(), fs.AccessModeType.EXIST)) {
        return null;
      }
      const jsonStr: string = fs.readTextSync(HuaweiDrivePathCacheStore.getFilePath());
      if (!jsonStr) {
        return null;
      }
      return HuaweiDrivePathCacheStore.parse(jsonStr);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Load path cache failed: %{public}s', (error as Error).message);
      return null;
    }
  }

  /**
   * 保存缓存（序列化 + 临时文件 rename 原子落盘），失败仅告警不影响主流程
   */
  public static async save(data: HuaweiDrivePathCacheData): Promise<void> {
    const write: () => Promise<void> = async (): Promise<void> => {
      const raw: PathCacheRaw = {
        v: CACHE_VERSION,
        owner: data.owner,
        rootId: data.rootId,
        entries: data.entries
      };
      const jsonStr: string = JSON.stringify(raw);
      const tmpPath: string = HuaweiDrivePathCacheStore.getFilePath() + '.tmp';
      const file = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        await fs.write(file.fd, jsonStr);
        await fs.fsync(file.fd);
      } finally {
        await fs.close(file.fd);
      }
      await fs.rename(tmpPath, HuaweiDrivePathCacheStore.getFilePath());
    };
    HuaweiDrivePathCacheStore.writeChain = HuaweiDrivePathCacheStore.writeChain.then(write)
      .catch((error: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'Save path cache failed: %{public}s', error.message);
      });
    return HuaweiDrivePathCacheStore.writeChain;
  }

  /**
   * 清空磁盘缓存（退出登录时调用，避免残留上一个账号的映射数据）
   */
  public static async clear(): Promise<void> {
    try {
      if (fs.accessSync(HuaweiDrivePathCacheStore.getFilePath(), fs.AccessModeType.EXIST)) {
        await fs.unlink(HuaweiDrivePathCacheStore.getFilePath());
      }
      // 旧 preferences 残留一并清理（仅主线程可达）
      if (CommonUtils.hasContext()) {
        try {
          const legacy = await preferences.getPreferences(CommonUtils.getContext(),
            LEGACY_PREFERENCES_NAME);
          await legacy.delete(KEY_PATH_CACHE);
          await legacy.flush();
        } catch {
          // 旧数据不存在：忽略
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Clear path cache failed: %{public}s', (error as Error).message);
    }
  }

  /**
   * 主线程一次性迁移旧 preferences 后端数据（Worker 无 Context，跳过）
   * 文件侧已有数据时跳过（文件为新后端的最新状态）
   */
  private static async migrateLegacyOnce(): Promise<void> {
    if (HuaweiDrivePathCacheStore.migrated || !CommonUtils.hasContext()) {
      return;
    }
    HuaweiDrivePathCacheStore.migrated = true;
    try {
      if (fs.accessSync(HuaweiDrivePathCacheStore.getFilePath(), fs.AccessModeType.EXIST)) {
        return;
      }
      const legacy = await preferences.getPreferences(CommonUtils.getContext(),
        LEGACY_PREFERENCES_NAME);
      const value: preferences.ValueType = legacy.getSync(KEY_PATH_CACHE, '');
      if (typeof value !== 'string' || !value) {
        return;
      }
      const data: HuaweiDrivePathCacheData | null = HuaweiDrivePathCacheStore.parse(value);
      if (data) {
        await HuaweiDrivePathCacheStore.save(data);
        hilog.info(DOMAIN, TAG, 'Legacy preferences path cache migrated to file store');
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Migrate legacy path cache failed: %{public}s', (error as Error).message);
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
