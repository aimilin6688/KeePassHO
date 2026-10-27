import { Kdbx, KdbxEntry, KdbxGroup } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DateUtils } from '../common/utils/DateUtils';
import { KdbxUtils } from '../common/utils/KdbxUtils';
import { ExpiryRemindFrequency, SettingsService } from './SettingsService';

const DOMAIN = 0x0000;
const TAG = 'ExpiryRemindService';

/**
 * 到期提醒评估结果（M1 条目到期提醒）
 */
export class ExpiryRemindResult {
  /** 已过期条目 */
  expiredEntries: KdbxEntry[] = [];
  /** 将在提醒窗口内到期的条目 */
  expiringEntries: KdbxEntry[] = [];
  /** 提醒窗口天数 */
  remindDays: number = SettingsService.KEY_SECURITY_EXPIRE_REMIND_DAYS_DEFAULT;

  get expiredCount(): number {
    return this.expiredEntries.length;
  }

  get expiringCount(): number {
    return this.expiringEntries.length;
  }

  get totalCount(): number {
    return this.expiredEntries.length + this.expiringEntries.length;
  }
}

/**
 * 到期提醒服务（M1）：解锁后收集已过期 / N 天内到期条目，
 * 结合防打扰策略（每库 24h 间隔 / 每次解锁 / 关闭记录时间）决定是否提醒。
 */
export class ExpiryRemindService {
  private static instance: ExpiryRemindService = new ExpiryRemindService();
  /** 防打扰静默期：24 小时 */
  static readonly REMIND_INTERVAL_MS: number = 24 * 60 * 60 * 1000;

  private constructor() {
  }

  public static getInstance(): ExpiryRemindService {
    return ExpiryRemindService.instance;
  }

  /**
   * 收集已过期与 N 天内到期的条目（遍历全库含子分组，排除回收站）
   * @param database 数据库
   * @param days 提醒窗口天数
   */
  public static collectExpiringEntries(database: Kdbx, days: number): ExpiryRemindResult {
    const result: ExpiryRemindResult = new ExpiryRemindResult();
    result.remindDays = days;
    const rootGroup: KdbxGroup | undefined = database.getDefaultGroup();
    if (!rootGroup) {
      return result;
    }
    ExpiryRemindService.collectFromGroup(database, rootGroup, days, result);
    return result;
  }

  private static collectFromGroup(database: Kdbx, group: KdbxGroup, days: number, result: ExpiryRemindResult): void {
    // 回收站及其子分组不参与提醒；isInRecycleBin 仅沿父链判断，回收站组自身需单独比较
    const recycleBinUuid = database.meta.recycleBinUuid;
    if ((recycleBinUuid !== undefined && group.uuid.equals(recycleBinUuid)) || database.isInRecycleBin(group)) {
      return;
    }
    for (const entry of group.entries) {
      // TAN 条目不参与到期提醒（用后过期是正常生命周期，P2-4 M3）
      if (KdbxUtils.isTanEntry(entry)) {
        continue;
      }
      // kdbxweb 中 expires 可能为 null，统一规范化为 boolean
      const expires: boolean = entry.times.expires === true;
      if (DateUtils.isExpired(expires, entry.times.expiryTime)) {
        result.expiredEntries.push(entry);
      } else if (DateUtils.willExpireInDays(expires, entry.times.expiryTime, days)) {
        result.expiringEntries.push(entry);
      }
    }
    for (const subGroup of group.groups) {
      ExpiryRemindService.collectFromGroup(database, subGroup, days, result);
    }
  }

  /**
   * 是否处于防打扰静默期内（纯函数，true = 不提醒）
   * @param lastRemindTime 上次提醒时间戳（0 表示从未提醒）
   * @param frequency 提醒频率
   * @param now 当前时间戳
   */
  public static isWithinRemindInterval(lastRemindTime: number, frequency: ExpiryRemindFrequency, now: number): boolean {
    if (frequency === ExpiryRemindFrequency.EVERY_UNLOCK) {
      return false;
    }
    return now - lastRemindTime < ExpiryRemindService.REMIND_INTERVAL_MS;
  }

  /**
   * 解锁后评估到期提醒：开关 → 防打扰 → 收集。
   * 存在临期条目且通过全部判定时记录本次提醒时间并返回结果，否则返回 null。
   * @param database 当前数据库
   * @param iocKey 库会话键（storageType::filePath）
   */
  public evaluate(database: Kdbx, iocKey: string): ExpiryRemindResult | null {
    try {
      if (!SettingsService.isExpireRemindEnable()) {
        return null;
      }
      if (iocKey.length === 0) {
        return null;
      }
      const frequency: ExpiryRemindFrequency = SettingsService.getExpireRemindFrequency();
      const lastTimeKey: string = SettingsService.expiryRemindLastTimeKey(iocKey);
      const lastRemindTime: number = SettingsService.getInstance().getSync(lastTimeKey, 0);
      if (ExpiryRemindService.isWithinRemindInterval(lastRemindTime, frequency, Date.now())) {
        return null;
      }
      const days: number = SettingsService.getExpireRemindDays();
      const result: ExpiryRemindResult = ExpiryRemindService.collectExpiringEntries(database, days);
      if (result.totalCount === 0) {
        return null;
      }
      SettingsService.getInstance().put(lastTimeKey, Date.now()).catch(() => {
        hilog.warn(DOMAIN, TAG, 'Failed to persist expire remind last time');
      });
      return result;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'evaluate failed: %{public}s', err.message);
      return null;
    }
  }

  /**
   * 「关闭」到期提醒条：仅隐藏当前提示条。
   * 每 24 小时频率：记录关闭时间，下次解锁按 24h 间隔判断是否再次提醒；
   * 每次解锁频率：不记录（每次解锁都提醒，关闭不产生静默期）。
   * @param iocKey 库会话键（storageType::filePath）
   */
  public async closeRemind(iocKey: string): Promise<void> {
    if (iocKey.length === 0) {
      return;
    }
    const frequency: ExpiryRemindFrequency = SettingsService.getExpireRemindFrequency();
    if (frequency !== ExpiryRemindFrequency.DAILY) {
      return;
    }
    await SettingsService.getInstance().put(SettingsService.expiryRemindLastTimeKey(iocKey), Date.now());
  }
}
