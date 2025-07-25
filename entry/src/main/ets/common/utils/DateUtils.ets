import { i18n, intl } from '@kit.LocalizationKit';

export default class DateUtils {
  private static dateFormat: intl.DateTimeFormat = new intl.DateTimeFormat(i18n.System.getSystemLocale(), { "dateStyle": "long", "timeStyle": "medium" });

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
   * 判断是否过期
   * @param date
   * @returns
   */
  public static isExpired(isEnableExpire:boolean, date: Date | undefined): boolean {
    if (isEnableExpire == false || !date) {
      return false;
    }
    return new Date().getTime() - date.getTime() >= 0;
  }
}