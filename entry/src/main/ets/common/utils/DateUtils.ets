import { i18n, intl } from '@kit.LocalizationKit';

export class DateUtils {
  private static dateFormat: Intl.DateTimeFormat =
    new Intl.DateTimeFormat(i18n.System.getSystemLocaleInstance().language, { "dateStyle": "long", "timeStyle": "medium" });

  /**
   * 获取当前时间：yyyyMMdd
   * @returns
   */
  public static getCurrentDate(): string {
    const now = new Date();

    // 提取时间组件
    const year = now.getFullYear().toString();
    const month = (now.getMonth() + 1).toString().padStart(2, '0'); // 月份从0开始需+1
    const day = now.getDate().toString().padStart(2, '0');
    return `${year}${month}${day}`;
  }

  /**
   * 获取当前时间：yyyyMMddHHmmss
   * @returns
   */
  public static getCurrentTime(): string {
    const now = new Date();

    // 提取时间组件
    const year = now.getFullYear().toString();
    const month = (now.getMonth() + 1).toString().padStart(2, '0'); // 月份从0开始需+1
    const day = now.getDate().toString().padStart(2, '0');
    const hours = now.getHours().toString().padStart(2, '0');
    const minutes = now.getMinutes().toString().padStart(2, '0');
    const seconds = now.getSeconds().toString().padStart(2, '0');

    // 组合成 yyyyMMddHHmmss 格式
    return `${year}${month}${day}${hours}${minutes}${seconds}`;
  }

  /**
   * 格式化时间
   * @param date
   * @returns
   */
  public static format(date: Date | undefined): string {
    if (!date) {
      return '';
    }
    return DateUtils.dateFormat.format(date);
  }

  /**
   * 判断是否过期（委托 willExpireInDays，窗口 0 天）
   * @param isEnableExpire 是否启用到期
   * @param date 到期时间
   * @returns
   */
  public static isExpired(isEnableExpire: boolean | undefined, date: Date | undefined): boolean {
    return DateUtils.willExpireInDays(isEnableExpire, date, 0);
  }

  /**
   * 判断条目是否已过期或将在 N 天内到期（M1 条目到期提醒）
   * 语义：expiryTime <= now + N 天 视为到期（与旧 isExpired 的 >= 0 边界保持一致）
   * @param expires 是否启用到期
   * @param expiryTime 到期时间
   * @param days 提前提醒天数窗口
   * @returns true 表示已过期或将在 N 天内到期
   */
  public static willExpireInDays(expires: boolean | undefined, expiryTime: Date | undefined, days: number): boolean {
    if (!expires || !expiryTime) {
      return false;
    }
    return expiryTime.getTime() <= new Date().getTime() + days * 24 * 60 * 60 * 1000;
  }

  /**
   * 判断日期是否是今天，不判断日期
   */
  public static isToday(date: Date | undefined): boolean {
    if (!date) {
      return false;
    }
    const now = new Date();
    return date.getFullYear() == now.getFullYear() && date.getMonth() == now.getMonth() && date.getDate() == now.getDate();
  }

  /**
   * 获取日期是否不是今天
   */
  public static isNotToday(data: Date | undefined): boolean {
    return !DateUtils.isToday(data);
  }

  /**
   * 获取偏移量
   * @param unit
   * @returns
   */
  public static offset(date: Date, offset: number, unit: DateUnit): Date {
    return new Date(date.getTime() + (offset * DateUtils.getOffset(unit)));
  }

  /**
   * 获取偏移量
   * @param unit
   * @returns
   */
  private static getOffset(unit: DateUnit): number {
    switch (unit) {
      case DateUnit.Millisecond:
        return 1;
      case DateUnit.Second:
        return 1000;
      case DateUnit.Minute:
        return 1000 * 60;
      case DateUnit.Hour:
        return 1000 * 60 * 60;
      case DateUnit.Day:
        return 1000 * 60 * 60 * 24;
      case DateUnit.Week:
        return 1000 * 60 * 60 * 24 * 7;
      case DateUnit.Month:
        return 1000 * 60 * 60 * 24 * 30;
      case DateUnit.Year:
        return 1000 * 60 * 60 * 24 * 365;
      default:
        return 0;
    }
  }
}

/**
 * 时间单位
 */
export enum DateUnit {
  Millisecond = 'millisecond',
  Second = 'second',
  Minute = 'minute',
  Hour = 'hour',
  Day = 'day',
  Week = 'week',
  Month = 'month',
  Year = 'year'
}