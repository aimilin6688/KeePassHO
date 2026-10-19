import { describe, expect, it } from '@ohos/hypium';
import { DateUtils, DateUnit } from '../../../../main/ets/common/utils/DateUtils';

/**
 * DateUtils 单元测试。
 *
 * 覆盖：日期/时间字符串生成、Intl 格式化、过期判断、今天判断、
 * 各时间单位偏移量（含负向偏移）与 DateUnit 枚举值。
 */
export default function DateUtilsTest() {
  describe('DateUtilsTest', () => {
    it('getCurrentDate returns yyyyMMdd matching local date components', 0, () => {
      const now = new Date();
      const expected = `${now.getFullYear()}` +
        `${(now.getMonth() + 1).toString().padStart(2, '0')}` +
        `${now.getDate().toString().padStart(2, '0')}`;
      const actual = DateUtils.getCurrentDate();
      expect(actual).assertEqual(expected);
      expect(actual.length).assertEqual(8);
    });

    it('getCurrentTime returns yyyyMMddHHmmss matching local time components', 0, () => {
      const now = new Date();
      const expected = `${now.getFullYear()}` +
        `${(now.getMonth() + 1).toString().padStart(2, '0')}` +
        `${now.getDate().toString().padStart(2, '0')}` +
        `${now.getHours().toString().padStart(2, '0')}` +
        `${now.getMinutes().toString().padStart(2, '0')}` +
        `${now.getSeconds().toString().padStart(2, '0')}`;
      const actual = DateUtils.getCurrentTime();
      expect(actual).assertEqual(expected);
      expect(actual.length).assertEqual(14);
    });

    it('format returns empty string for undefined date', 0, () => {
      expect(DateUtils.format(undefined)).assertEqual('');
    });

    it('format returns a non-empty localized string for a real date', 0, () => {
      const formatted = DateUtils.format(new Date(2026, 9, 20, 12, 30, 0));
      expect(formatted.length > 0).assertTrue();
    });

    it('isExpired returns false when expiry disabled regardless of date', 0, () => {
      const past = new Date(Date.now() - 10000);
      expect(DateUtils.isExpired(false, past)).assertFalse();
    });

    it('isExpired returns false for undefined date even when enabled', 0, () => {
      expect(DateUtils.isExpired(true, undefined)).assertFalse();
    });

    it('isExpired returns true for a past date when enabled', 0, () => {
      const past = new Date(Date.now() - 10000);
      expect(DateUtils.isExpired(true, past)).assertTrue();
    });

    it('isExpired returns false for a future date when enabled', 0, () => {
      const future = new Date(Date.now() + 10000);
      expect(DateUtils.isExpired(true, future)).assertFalse();
    });

    it('isExpired boundary: now counts as expired (>= 0)', 0, () => {
      const now = new Date();
      expect(DateUtils.isExpired(true, now)).assertTrue();
    });

    it('isToday returns false for undefined', 0, () => {
      expect(DateUtils.isToday(undefined)).assertFalse();
    });

    it('isToday returns true for now and false for yesterday', 0, () => {
      expect(DateUtils.isToday(new Date())).assertTrue();
      expect(DateUtils.isToday(new Date(Date.now() - 24 * 3600 * 1000))).assertFalse();
    });

    it('isNotToday inverts isToday', 0, () => {
      expect(DateUtils.isNotToday(undefined)).assertTrue();
      expect(DateUtils.isNotToday(new Date())).assertFalse();
      expect(DateUtils.isNotToday(new Date(Date.now() - 24 * 3600 * 1000))).assertTrue();
    });

    it('offset adds the exact millisecond delta per unit', 0, () => {
      const base = new Date(2026, 0, 2, 3, 4, 5, 100);
      const baseMs = base.getTime();
      expect(DateUtils.offset(base, 5, DateUnit.Millisecond).getTime() - baseMs).assertEqual(5);
      expect(DateUtils.offset(base, 5, DateUnit.Second).getTime() - baseMs).assertEqual(5000);
      expect(DateUtils.offset(base, 5, DateUnit.Minute).getTime() - baseMs).assertEqual(300000);
      expect(DateUtils.offset(base, 5, DateUnit.Hour).getTime() - baseMs).assertEqual(18000000);
      expect(DateUtils.offset(base, 5, DateUnit.Day).getTime() - baseMs).assertEqual(432000000);
      expect(DateUtils.offset(base, 5, DateUnit.Week).getTime() - baseMs).assertEqual(3024000000);
      expect(DateUtils.offset(base, 5, DateUnit.Month).getTime() - baseMs).assertEqual(12960000000);
      expect(DateUtils.offset(base, 5, DateUnit.Year).getTime() - baseMs).assertEqual(157680000000);
    });

    it('offset supports negative and zero offsets', 0, () => {
      const base = new Date(2026, 5, 15, 10, 0, 0, 0);
      const baseMs = base.getTime();
      expect(DateUtils.offset(base, -2, DateUnit.Day).getTime() - baseMs).assertEqual(-172800000);
      expect(DateUtils.offset(base, 0, DateUnit.Hour).getTime() - baseMs).assertEqual(0);
    });

    it('offset does not mutate the original date', 0, () => {
      const base = new Date(2026, 5, 15, 10, 0, 0, 0);
      const baseMs = base.getTime();
      DateUtils.offset(base, 3, DateUnit.Day);
      expect(base.getTime()).assertEqual(baseMs);
    });

    it('DateUnit enum exposes string unit names', 0, () => {
      expect(DateUnit.Millisecond).assertEqual('millisecond');
      expect(DateUnit.Second).assertEqual('second');
      expect(DateUnit.Minute).assertEqual('minute');
      expect(DateUnit.Hour).assertEqual('hour');
      expect(DateUnit.Day).assertEqual('day');
      expect(DateUnit.Week).assertEqual('week');
      expect(DateUnit.Month).assertEqual('month');
      expect(DateUnit.Year).assertEqual('year');
    });
  });
}
