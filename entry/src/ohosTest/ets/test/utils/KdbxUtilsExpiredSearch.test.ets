import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { TestUtils } from '../importExport/TestUtils';
import { Kdbx, KdbxEntry, KdbxGroup } from 'kdbxweb';

/**
 * is:expired / is:expired-N 搜索语法单元测试（M2 搜索语法增强）
 * 覆盖：is:expired 精确匹配已过期 / is:expired-N 匹配 N 天内到期（含已过期）/
 *       is:expired-0 等价 is:expired / 回收站排除 / 普通关键词搜索不受影响 /
 *       非法语法按普通关键词处理 / 大小写不敏感 / searchInEntries 同样支持
 */
export default function KdbxUtilsExpiredSearchTest() {
  describe('KdbxUtilsExpiredSearch', () => {
    const DAY: number = 24 * 60 * 60 * 1000;

    const offsetDate = (offsetMs: number): Date => new Date(Date.now() + offsetMs);

    const createExpiryEntry = (db: Kdbx, group: KdbxGroup, title: string,
      expires: boolean, expiryOffsetMs: number): KdbxEntry => {
      const entry: KdbxEntry = TestUtils.createTestEntry(db, group, title);
      entry.times.expires = expires;
      entry.times.expiryTime = offsetDate(expiryOffsetMs);
      return entry;
    };

    const createDbWithMixedEntries = async (): Promise<Kdbx> => {
      const db: Kdbx = await TestUtils.createTestDatabase('ExpiredSearchTestDb');
      const rootGroup: KdbxGroup = db.getDefaultGroup();
      createExpiryEntry(db, rootGroup, 'expired-entry', true, -DAY);
      createExpiryEntry(db, rootGroup, 'expiring-entry', true, 3 * DAY);
      createExpiryEntry(db, rootGroup, 'far-entry', true, 30 * DAY);
      createExpiryEntry(db, rootGroup, 'never-entry', false, DAY);
      return db;
    };

    const resultTitles = (entries: KdbxEntry[]): string[] => {
      return entries.map((entry: KdbxEntry): string => {
        return KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_TITLE);
      });
    };

    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
    });

    afterAll(() => {
    });

    it('is:expired matches only already expired entries', 0, async () => {
      const db: Kdbx = await createDbWithMixedEntries();
      const result = KdbxUtils.searchInGroup(db.getDefaultGroup(), 'is:expired', db, false);
      expect(result.filteredEntries.length).assertEqual(1);
      expect(resultTitles(result.filteredEntries)[0]).assertEqual('expired-entry');
    });

    it('is:expired-7 matches expired and entries expiring within 7 days', 0, async () => {
      const db: Kdbx = await createDbWithMixedEntries();
      const result = KdbxUtils.searchInGroup(db.getDefaultGroup(), 'is:expired-7', db, false);
      expect(result.filteredEntries.length).assertEqual(2);
      const titles: string[] = resultTitles(result.filteredEntries);
      expect(titles.includes('expired-entry')).assertTrue();
      expect(titles.includes('expiring-entry')).assertTrue();
    });

    it('is:expired-0 is equivalent to is:expired', 0, async () => {
      const db: Kdbx = await createDbWithMixedEntries();
      const result = KdbxUtils.searchInGroup(db.getDefaultGroup(), 'is:expired-0', db, false);
      expect(result.filteredEntries.length).assertEqual(1);
      expect(resultTitles(result.filteredEntries)[0]).assertEqual('expired-entry');
    });

    it('is:expired search excludes recycle bin entries', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase('ExpiredSearchRecycleDb');
      const rootGroup: KdbxGroup = db.getDefaultGroup();
      const entry: KdbxEntry = createExpiryEntry(db, rootGroup, 'removed-expired', true, -DAY);
      db.remove(entry);
      const result = KdbxUtils.searchInGroup(db.getDefaultGroup(), 'is:expired', db, false);
      expect(result.filteredEntries.length).assertEqual(0);
    });

    it('normal keyword search is unaffected by expiry syntax', 0, async () => {
      const db: Kdbx = await createDbWithMixedEntries();
      const result = KdbxUtils.searchInGroup(db.getDefaultGroup(), 'entry', db, false);
      // 普通关键词仍按字段匹配，不触发到期语法
      expect(result.filteredEntries.length).assertEqual(4);
    });

    it('invalid expired syntax is treated as plain keyword search', 0, async () => {
      const db: Kdbx = await createDbWithMixedEntries();
      // is:expired-abc 不是合法语法，按普通关键词处理，不应命中任何条目
      const result = KdbxUtils.searchInGroup(db.getDefaultGroup(), 'is:expired-abc', db, false);
      expect(result.filteredEntries.length).assertEqual(0);
    });

    it('expired search syntax is case-insensitive', 0, async () => {
      const db: Kdbx = await createDbWithMixedEntries();
      const result = KdbxUtils.searchInGroup(db.getDefaultGroup(), 'IS:Expired-3', db, false);
      expect(result.filteredEntries.length).assertEqual(2);
    });

    it('searchInEntries supports expired search syntax', 0, async () => {
      const db: Kdbx = await createDbWithMixedEntries();
      const rootGroup: KdbxGroup = db.getDefaultGroup();
      const entries: Array<KdbxEntry> = [...rootGroup.entries];
      const matched: Array<KdbxEntry> = KdbxUtils.searchInEntries(entries, 'is:expired');
      expect(matched.length).assertEqual(1);
      expect(resultTitles(matched)[0]).assertEqual('expired-entry');
    });
  });
}
