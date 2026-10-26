import { afterAll, afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { ExpiryRemindFrequency, SettingsService } from '../../../../main/ets/services/SettingsService';
import { ExpiryRemindResult, ExpiryRemindService } from '../../../../main/ets/services/ExpiryRemindService';
import { TestUtils } from '../importExport/TestUtils';
import { Kdbx, KdbxEntry, KdbxGroup } from 'kdbxweb';

/**
 * ExpiryRemindService 单元测试（M1 条目到期提醒）
 * 覆盖：收集分组（已过期/N天内到期）/ 回收站排除 / 子分组包含 /
 *       防打扰 24h 边界（23h/25h）/ 每次解锁频率 / 多库隔离 / 今日隐藏 / 开关关闭
 */
export default function ExpiryRemindServiceTest() {
  describe('ExpiryRemindService', () => {
    const DAY: number = 24 * 60 * 60 * 1000;
    const IOC_KEY_A: string = 'LOCAL::/data/test-expiry-a.kdbx';
    const IOC_KEY_B: string = 'LOCAL::/data/test-expiry-b.kdbx';

    const offsetDate = (offsetMs: number): Date => new Date(Date.now() + offsetMs);

    /**
     * 创建带到期属性的测试条目
     */
    const createExpiryEntry = (db: Kdbx, group: KdbxGroup, title: string, expires: boolean, expiryOffsetMs: number): KdbxEntry => {
      const entry: KdbxEntry = TestUtils.createTestEntry(db, group, title);
      entry.times.expires = expires;
      entry.times.expiryTime = offsetDate(expiryOffsetMs);
      return entry;
    };

    /**
     * 创建包含到期条目的测试数据库
     */
    const createDbWithExpiringEntries = async (): Promise<Kdbx> => {
      const db: Kdbx = await TestUtils.createTestDatabase('ExpiryRemindTestDb');
      const rootGroup: KdbxGroup = db.getDefaultGroup();
      createExpiryEntry(db, rootGroup, 'expired-entry', true, -DAY);
      createExpiryEntry(db, rootGroup, 'expiring-entry', true, 3 * DAY);
      return db;
    };

    /**
     * 清理动态键与设置项，恢复默认值
     */
    const cleanupKeys = (): void => {
      const instance = SettingsService.getInstance();
      instance.deleteSync(SettingsService.expiryRemindLastTimeKey(IOC_KEY_A));
      instance.deleteSync(SettingsService.expiryRemindLastTimeKey(IOC_KEY_B));
      instance.deleteSync(SettingsService.expiryRemindHiddenKey(IOC_KEY_A));
      instance.deleteSync(SettingsService.expiryRemindHiddenKey(IOC_KEY_B));
      instance.deleteSync(SettingsService.KEY_SECURITY_EXPIRE_REMIND_ENABLE);
      instance.deleteSync(SettingsService.KEY_SECURITY_EXPIRE_REMIND_DAYS);
      instance.deleteSync(SettingsService.KEY_SECURITY_EXPIRE_REMIND_FREQUENCY);
    };

    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    afterEach(() => {
      cleanupKeys();
    });

    afterAll(() => {
      cleanupKeys();
    });

    // ---------------- collectExpiringEntries 收集逻辑 ----------------

    it('collectExpiringEntries groups expired and expiring entries correctly', 0, async () => {
      const db = await createDbWithExpiringEntries();
      const result: ExpiryRemindResult = ExpiryRemindService.collectExpiringEntries(db, 7);
      expect(result.expiredCount).assertEqual(1);
      expect(result.expiringCount).assertEqual(1);
      expect(result.totalCount).assertEqual(2);
      expect(result.expiredEntries[0].fields.get('Title')).assertEqual('expired-entry');
      expect(result.expiringEntries[0].fields.get('Title')).assertEqual('expiring-entry');
    });

    it('collectExpiringEntries ignores entries not expiring and entries beyond window', 0, async () => {
      const db = await TestUtils.createTestDatabase('ExpiryRemindWindowDb');
      const rootGroup: KdbxGroup = db.getDefaultGroup();
      createExpiryEntry(db, rootGroup, 'never-expires', false, DAY);
      createExpiryEntry(db, rootGroup, 'far-future', true, 30 * DAY);
      const result: ExpiryRemindResult = ExpiryRemindService.collectExpiringEntries(db, 7);
      expect(result.totalCount).assertEqual(0);
    });

    it('collectExpiringEntries includes entries in subgroups', 0, async () => {
      const db = await TestUtils.createTestDatabase('ExpiryRemindSubGroupDb');
      const rootGroup: KdbxGroup = db.getDefaultGroup();
      const subGroup: KdbxGroup = TestUtils.createTestGroup(db, rootGroup, 'sub');
      createExpiryEntry(db, subGroup, 'sub-expiring', true, 2 * DAY);
      const result: ExpiryRemindResult = ExpiryRemindService.collectExpiringEntries(db, 7);
      expect(result.expiringCount).assertEqual(1);
      expect(result.expiringEntries[0].fields.get('Title')).assertEqual('sub-expiring');
    });

    it('collectExpiringEntries excludes recycle bin entries', 0, async () => {
      const db = await TestUtils.createTestDatabase('ExpiryRemindRecycleDb');
      const rootGroup: KdbxGroup = db.getDefaultGroup();
      const entry: KdbxEntry = createExpiryEntry(db, rootGroup, 'removed-expiring', true, 2 * DAY);
      // Kdbx.create 已启用回收站：remove 将条目移入回收站
      db.remove(entry);
      expect(db.isInRecycleBin(entry)).assertTrue();
      const result: ExpiryRemindResult = ExpiryRemindService.collectExpiringEntries(db, 7);
      expect(result.totalCount).assertEqual(0);
    });

    it('collectExpiringEntries excludes entries in nested groups inside recycle bin', 0, async () => {
      const db = await TestUtils.createTestDatabase('ExpiryRemindRecycleNestedDb');
      const rootGroup: KdbxGroup = db.getDefaultGroup();
      const entry: KdbxEntry = createExpiryEntry(db, rootGroup, 'nested-removed-expiring', true, 2 * DAY);
      db.remove(entry);
      const recycleBinUuid = db.meta.recycleBinUuid;
      expect(recycleBinUuid !== undefined).assertTrue();
      if (recycleBinUuid === undefined) {
        return;
      }
      const recycleBinGroup: KdbxGroup | undefined = db.getGroup(recycleBinUuid);
      expect(recycleBinGroup !== undefined).assertTrue();
      if (recycleBinGroup === undefined) {
        return;
      }
      const nestedGroup: KdbxGroup = TestUtils.createTestGroup(db, recycleBinGroup, 'nested-in-bin');
      db.move(entry, nestedGroup);
      expect(db.isInRecycleBin(entry)).assertTrue();
      const result: ExpiryRemindResult = ExpiryRemindService.collectExpiringEntries(db, 7);
      expect(result.totalCount).assertEqual(0);
    });

    // ---------------- isWithinRemindInterval 防打扰纯函数 ----------------

    it('isWithinRemindInterval returns true within 24h for DAILY frequency', 0, () => {
      const now = Date.now();
      expect(ExpiryRemindService.isWithinRemindInterval(now - 23 * 60 * 60 * 1000, ExpiryRemindFrequency.DAILY, now)).assertTrue();
    });

    it('isWithinRemindInterval returns false beyond 24h for DAILY frequency', 0, () => {
      const now = Date.now();
      expect(ExpiryRemindService.isWithinRemindInterval(now - 25 * 60 * 60 * 1000, ExpiryRemindFrequency.DAILY, now)).assertFalse();
    });

    it('isWithinRemindInterval returns false for never reminded (0)', 0, () => {
      expect(ExpiryRemindService.isWithinRemindInterval(0, ExpiryRemindFrequency.DAILY, Date.now())).assertFalse();
    });

    it('isWithinRemindInterval always returns false for EVERY_UNLOCK frequency', 0, () => {
      const now = Date.now();
      expect(ExpiryRemindService.isWithinRemindInterval(now, ExpiryRemindFrequency.EVERY_UNLOCK, now)).assertFalse();
    });

    // ---------------- evaluate 解锁评估（防打扰 + 记录时间戳） ----------------

    it('evaluate returns null when remind switch is off', 0, async () => {
      const db = await createDbWithExpiringEntries();
      await SettingsService.getInstance().put(SettingsService.KEY_SECURITY_EXPIRE_REMIND_ENABLE, false);
      const result = ExpiryRemindService.getInstance().evaluate(db, IOC_KEY_A);
      expect(result === null).assertTrue();
    });

    it('evaluate returns null when no entries are expiring', 0, async () => {
      const db = await TestUtils.createTestDatabase('ExpiryRemindEmptyDb');
      const result = ExpiryRemindService.getInstance().evaluate(db, IOC_KEY_A);
      expect(result === null).assertTrue();
    });

    it('evaluate reminds when last remind was 25h ago and records timestamp', 0, async () => {
      const db = await createDbWithExpiringEntries();
      const lastTimeKey = SettingsService.expiryRemindLastTimeKey(IOC_KEY_A);
      await SettingsService.getInstance().put(lastTimeKey, Date.now() - 25 * 60 * 60 * 1000);
      const before = Date.now();
      const result = ExpiryRemindService.getInstance().evaluate(db, IOC_KEY_A);
      expect(result !== null).assertTrue();
      expect(result!.totalCount).assertEqual(2);
      const recorded = SettingsService.getInstance().getSync(lastTimeKey, 0);
      expect(recorded >= before).assertTrue();
    });

    it('evaluate is suppressed within 24h and keeps the old timestamp', 0, async () => {
      const db = await createDbWithExpiringEntries();
      const lastTimeKey = SettingsService.expiryRemindLastTimeKey(IOC_KEY_A);
      const staleTime = Date.now() - 23 * 60 * 60 * 1000;
      await SettingsService.getInstance().put(lastTimeKey, staleTime);
      const result = ExpiryRemindService.getInstance().evaluate(db, IOC_KEY_A);
      expect(result === null).assertTrue();
      expect(SettingsService.getInstance().getSync(lastTimeKey, 0)).assertEqual(staleTime);
    });

    it('evaluate reminds on every unlock for EVERY_UNLOCK frequency', 0, async () => {
      const db = await createDbWithExpiringEntries();
      const lastTimeKey = SettingsService.expiryRemindLastTimeKey(IOC_KEY_A);
      await SettingsService.getInstance().put(SettingsService.KEY_SECURITY_EXPIRE_REMIND_FREQUENCY, ExpiryRemindFrequency.EVERY_UNLOCK);
      await SettingsService.getInstance().put(lastTimeKey, Date.now());
      const result = ExpiryRemindService.getInstance().evaluate(db, IOC_KEY_A);
      expect(result !== null).assertTrue();
    });

    it('evaluate isolates reminder state across databases', 0, async () => {
      const db = await createDbWithExpiringEntries();
      const lastTimeKeyA = SettingsService.expiryRemindLastTimeKey(IOC_KEY_A);
      await SettingsService.getInstance().put(lastTimeKeyA, Date.now());
      // A 库处于静默期：不提醒
      expect(ExpiryRemindService.getInstance().evaluate(db, IOC_KEY_A) === null).assertTrue();
      // B 库无记录：正常提醒
      const resultB = ExpiryRemindService.getInstance().evaluate(db, IOC_KEY_B);
      expect(resultB !== null).assertTrue();
    });

    // ---------------- 今日隐藏（不再提示） ----------------

    it('hideToday makes isHiddenToday true and evaluate return null', 0, async () => {
      const db = await createDbWithExpiringEntries();
      expect(ExpiryRemindService.getInstance().isHiddenToday(IOC_KEY_A)).assertFalse();
      await ExpiryRemindService.getInstance().hideToday(IOC_KEY_A);
      expect(ExpiryRemindService.getInstance().isHiddenToday(IOC_KEY_A)).assertTrue();
      const result = ExpiryRemindService.getInstance().evaluate(db, IOC_KEY_A);
      expect(result === null).assertTrue();
    });
  });
}
