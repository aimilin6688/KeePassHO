import { describe, expect, it } from '@ohos/hypium';
import { DateUtils } from '../../../../main/ets/common/utils/DateUtils';

/**
 * DateUtils.willExpireInDays 单元测试（M1 条目到期提醒）
 * 覆盖：未启用到期 / 无到期时间 / 已过期 / N 天窗口边界 / isExpired 委托回归
 */
export default function DateUtilsWillExpireTest() {
  describe('DateUtilsWillExpire', () => {
    const DAY: number = 24 * 60 * 60 * 1000;

    /**
     * 构造相对当前时间偏移 offsetMs 的日期
     */
    const offsetDate = (offsetMs: number): Date => new Date(Date.now() + offsetMs);

    it('returns false when expires is false even if expiryTime is set', 0, () => {
      expect(DateUtils.willExpireInDays(false, offsetDate(-DAY), 7)).assertFalse();
    });

    it('returns false when expires is undefined', 0, () => {
      expect(DateUtils.willExpireInDays(undefined, offsetDate(-DAY), 7)).assertFalse();
    });

    it('returns false when expiryTime is undefined', 0, () => {
      expect(DateUtils.willExpireInDays(true, undefined, 7)).assertFalse();
    });

    it('returns true for an already expired entry regardless of days', 0, () => {
      expect(DateUtils.willExpireInDays(true, offsetDate(-DAY), 0)).assertTrue();
      expect(DateUtils.willExpireInDays(true, offsetDate(-DAY), 7)).assertTrue();
      expect(DateUtils.willExpireInDays(true, offsetDate(-DAY), 3650)).assertTrue();
    });

    it('returns false for a future entry when days is 0', 0, () => {
      expect(DateUtils.willExpireInDays(true, offsetDate(10 * 1000), 0)).assertFalse();
    });

    it('returns true when expiry is within N days (N days minus 1ms)', 0, () => {
      expect(DateUtils.willExpireInDays(true, offsetDate(7 * DAY - 1), 7)).assertTrue();
    });

    it('returns false when expiry is beyond N days (N days plus 1ms)', 0, () => {
      expect(DateUtils.willExpireInDays(true, offsetDate(7 * DAY + 1), 7)).assertFalse();
    });

    it('returns false when expiry is far beyond a large window', 0, () => {
      expect(DateUtils.willExpireInDays(true, offsetDate(365 * DAY), 30)).assertFalse();
    });

    it('returns true when expiry is within a large window', 0, () => {
      expect(DateUtils.willExpireInDays(true, offsetDate(100 * DAY), 3650)).assertTrue();
    });

    it('isExpired delegates to willExpireInDays with days 0 (regression)', 0, () => {
      // 已过期：与旧逻辑一致返回 true
      expect(DateUtils.isExpired(true, offsetDate(-1))).assertTrue();
      // 未启用到期：返回 false
      expect(DateUtils.isExpired(false, offsetDate(-DAY))).assertFalse();
      // 未启用到期且无时间：返回 false
      expect(DateUtils.isExpired(false, undefined)).assertFalse();
      // 未来时间：返回 false
      expect(DateUtils.isExpired(true, offsetDate(10 * 1000))).assertFalse();
    });
  });
}
